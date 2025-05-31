import Lean
import Qq
import LeanAide.Aides
import LeanAide.TranslateM
import LeanCodePrompts.Translate
import LeanAide.RunTactics
import LeanAide.AutoTactic

open Lean Meta Qq Elab

initialize registerTraceClass `LeanAide.Codegen

namespace LeanAide

instance : Repr SyntaxNodeKinds where
  reprPrec kinds n :=
    let names : List Name := kinds
    Repr.reprPrec names n

instance : ToString SyntaxNodeKinds where
  toString kinds :=
    let names : List Name := kinds
    ToString.toString names

namespace Codegen

/--
Attribute for generating Lean code, more precisely Syntax of a given category, from JSON data. More precisely, we generate `TranslateM <| Option <| TSyntax Q` from a JSON object, with the matching key as part of the attribute. In some cases, no syntax is generated as the goal is purely to have a side-effect to modify the context.

As the same statement can generate different syntax categories (e.g. `def` and `let`) this is not specified in the attribute. Instead the target category is part of the signature of the function.
-/
syntax (name := codegen) "codegen" (str,*)? : attr

/-- Environment extension storing code generation lemmas -/
initialize codegenExt :
    SimpleScopedEnvExtension (Name × (Option String)) (Std.HashMap (Option String) (Array Name)) ←
  registerSimpleScopedEnvExtension {
    addEntry := fun m (n, key?) =>
        m.insert key? <| (m.getD key? #[] ).push n
    initial := {}
  }

def codegenKeyM (stx : Syntax) : CoreM <| Option (Array String) := do
  match stx with
  | `(attr|codegen) => do
    return none
  | `(attr|codegen $x) => do
    return #[x.getString]
  | `(attr|codegen $xs,*) => do
    let keys := xs.getElems
    return keys.map (·.getString)
  | _ => throwUnsupportedSyntax


initialize registerBuiltinAttribute {
  name := `codegen
  descr := "Lean code generator"
  add := fun decl stx kind => MetaM.run' do
    let declTy := (← getConstInfo decl).type
    let expectedType : Q(Type) :=
    q(CodeGenerator → Option MVarId  → (kind : SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind)))
    unless ← isDefEq declTy expectedType do
      throwError -- replace with error
        s!"codegen: {decl} has type {declTy}, but expected {expectedType}"
    let keys ← codegenKeyM stx
    -- logInfo m!"codegen: {decl}; keys: {keys}"
    match keys with
    | none => do
      -- no keys, just add the name
      codegenExt.add (decl, none) kind
    | some keys =>
    for key in keys do
      codegenExt.add (decl, key) kind
}

def codegenMatches (key: String) : CoreM <| Array Name := do
  let some fs :=
    (codegenExt.getState (← getEnv)).get? key | throwError
      s!"codegen: no function found for key {key}"
  return fs

def codegenKeyless : CoreM <| Array Name := do
  return (codegenExt.getState (← getEnv)).get? none |>.getD #[]

def codeFromFunc (goal? : Option MVarId) (translator: CodeGenerator) (f: Name) (kind : SyntaxNodeKinds) (source: Json) :
    TranslateM (Option (TSyntax kind)) := do
  let expectedType : Q(Type) :=
    q(CodeGenerator → Option MVarId  →  (kind : SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind)))
  let f := mkConst f
  let code ←
    unsafe evalExpr
      (CodeGenerator → Option MVarId  → (kind : SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))) expectedType f
  code translator goal? kind source

/--
Given a JSON object, return the corresponding syntax by matching with `.getKVorType?` and then calling the function in the environment using `codeFromFunc`. The function is expected to return a `TranslateM (Option (TSyntax kind))`, where `kind` is the syntax category of the object.
-/
def getCode  (translator: CodeGenerator) (goal? : Option MVarId) (kind: SyntaxNodeKinds)
  (source: Json) :
    TranslateM (Option (TSyntax kind)) := do
  match source.getKVorType? with
  | some (key, source) => do
    let key := key.toLower
    let fs ←  codegenMatches key
    for f in fs.reverse do
      try
        -- logInfo m!"codegen: trying {f} for key {key}"
        let code? ← codeFromFunc goal? translator f kind source
        match code? with
        | some code => return some code
        | none => continue -- try next function
      catch _ =>
        continue -- try next function
    throwError
      s!"codegen: no valid function found for key {key} in JSON object {source}"
  | none => do
    let fs ← codegenKeyless
    if fs.isEmpty then
      throwError
        s!"codegen: no key or type found in JSON object {source}, and no codegen functions registered"
    for f in fs.reverse do
      try
        let code? ← codeFromFunc goal? translator f kind source
        return code?
      catch _ =>
        continue -- try next function
    throwError
      s!"codegen: no key or type found in JSON object {source} and no codegen functions returned a result"

open Lean.Parser.Tactic
def emptyTacs : CoreM (TSyntax ``tacticSeq) := do
  let xs: Array (TSyntax `tactic) := #[]
  `(tacticSeq| $xs*)

def getCodeTacticsAux (translator: CodeGenerator) (goal :  MVarId)
  (sources: List Json) (accum: TSyntax ``tacticSeq) :
    TranslateM ((TSyntax ``tacticSeq) × Option MVarId) :=
  goal.withContext do
  match sources with
  | [] => do
    return (accum, goal)
  | source::sources => do
    let code? ← try
        getCode translator (some goal) ``tacticSeq source
      catch e =>
        let err ←   e.toMessageData.toString
        let errSrx := Syntax.mkStrLit <| "Error: " ++ err
        pure <| some <| ← `(tacticSeq| have := $errSrx)
    match code? with
    | none => do -- pure side effect, no code generated
      getCodeTacticsAux translator goal sources accum
    | some code => do
      let goal? ← runForSingleGoal goal code
      match goal? with
      | none => do -- tactics closed the goal
        return (accum, none)
      | some newGoal => do
        let newAccum ← appendTactics accum code
        getCodeTacticsAux translator newGoal sources newAccum

/--
Main helper for generating tactics from a list of JSON objects.
-/
def getCodeTactics (translator: CodeGenerator) (goal :  MVarId)
  (sources: List Json) :
    TranslateM (TSyntax ``tacticSeq) :=
  withoutModifyingState do
  let accum ← emptyTacs
  let (tacs, goal?) ←
     getCodeTacticsAux translator goal sources accum
  match goal? with
  | none => do
    return tacs
  | some goal => do
    let autoTacs ←
      runTacticsAndGetTryThisI (← goal.getType) #[← `(tactic| auto?)]
    appendTactics tacs (← `(tacticSeq| $autoTacs*))

def getCodeCommands (translator: CodeGenerator) (goal? : Option MVarId)
  (sources: List Json) :
    TranslateM (TSyntax ``commandSeq) := withoutModifyingState do
  let mut accum : Array <| TSyntax ``commandSeq := #[]
  for source in sources do
    let code? ← try
        getCode translator goal? ``commandSeq source
      catch e =>
        let err ←   e.toMessageData.toString
        let errSrx := Syntax.mkStrLit <| "Error: " ++ err
        pure <| some <| ← `(commandSeq| example := $errSrx)

    match code? with
    | none => do -- error with obtaining commands
      continue
    | some code => do
      accum := accum.push code
  if accum.isEmpty then
    throwError
      s!"codegen: no commands generated from {sources}"
  let res ← flattenCommands accum
  Translate.addCommands res
  return res

def noCode : CodeGenerator → Option MVarId  →
  (kind : SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind)) := fun _ _ _ _  => do
  return none

def notImplementedCode (name: String) : CodeGenerator → Option MVarId  →
  (kind : SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind)) := fun _ _ _ _  => do
  IO.eprintln s!"codegen: {name} not implemented"
  logWarning m!"codegen: {name} not implemented"
  return none

macro "#notImplementedCode" name:str : command => do
  let thmName := mkIdent <| (name.getString ++ "Impl").toName
  `(command | @[codegen $name]
  def $thmName := notImplementedCode $name)

-- For instance, for the hypothesis in a theorem.
def contextRun (translator: CodeGenerator) (goal? : Option MVarId)
  (kind: SyntaxNodeKinds) (source: Json) :
    TranslateM Unit := do
  match source.getArr?  with
  | .ok sources => do
    for source in sources do
      let code ← getCode translator goal? kind source
      unless code.isNone do
        throwError
          s!"codegen: contextCode expected pure side effect, but got {code}"
    return
  | .error _ => do
    throwError
      s!"codegen: contextCode expected an array of JSON objects, but got {source}"

end Codegen

#eval [1, 2, 3].contains 2

#check Fact

end LeanAide
