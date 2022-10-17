import Lean
import Lean.Meta
import Lean.Data
import Init.System
open Lean Meta Elab

set_option synthInstance.maxHeartbeats 1000000

/- 
Obtaining names of constants
-/

def isBlackListed  (declName : Name) : MetaM  Bool := do
  let env ← getEnv
  return (declName.isInternal
  || isAuxRecursor env declName
  || isNoConfusion env declName
  || isRecCore env declName
  || isMatcherCore env declName)

def isAux (declName : Name) : MetaM  Bool := do
  let env ← getEnv
  return (isAuxRecursor env declName
          || isNoConfusion env declName)
  
def isNotAux  (declName : Name) : MetaM  Bool := do
  let nAux ← isAux declName
  return (not nAux)

def isWhiteListed (declName : Name) : MetaM Bool := do
  try
  let bl ← isBlackListed  declName
  return !bl
  catch _ => return false

def excludePrefixes := [`Lean, `Std, `IO, 
          `Char, `String, `ST, `StateT, `Repr, `ReaderT, `EIO, `BaseIO, `UInt8, ``UInt16, ``UInt32, ``UInt64]

/-- names of global constants -/
def constantNames  : MetaM (Array Name) := do
  let env ← getEnv
  let decls := env.constants.map₁.toArray
  let allNames := decls.map $ fun (name, _) => name 
  let names ← allNames.filterM (isWhiteListed)
  let names := names.filter fun n => !(excludePrefixes.any (fun pfx => pfx.isPrefixOf n))
  return names

def constantNamesCore : CoreM (Array Name) := 
  constantNames.run'

/-- names with types of global constants -/
def constantNameTypes  : MetaM (Array (Name ×  Expr)) := do
  let env ← getEnv
  let decls := env.constants.map₁.toArray
  let allNames := decls.map $ fun (name, dfn) => (name, dfn.type) 
  let names ← allNames.filterM (fun (name, _) => isWhiteListed name)
  return names

initialize exprRecCache : IO.Ref (HashMap Expr (Array Name)) ← IO.mkRef (HashMap.empty)

def getCached? (e : Expr) : IO (Option (Array Name)) := do
  let cache ← exprRecCache.get
  return cache.find? e

def cache (e: Expr) (offs : Array Name) : IO Unit := do
  let cache ← exprRecCache.get
  exprRecCache.set (cache.insert  e offs)
  return ()

/-- given name, optional expression of definition for the corresponding constant -/
def nameExpr? : Name → MetaM ( Option Expr) := 
  fun name => do
      let info := ((← getEnv).find? name)
      return Option.bind info ConstantInfo.value?

/-- optionally infer type of expression -/
def inferType?(e: Expr) : MetaM (Option Expr) := do
  try
    let type ← inferType e
    return some type
  catch _ => return none

/-- recursively find (whitelisted) names of constants in an expression; -/
partial def recExprNames (depth: Nat): Expr → MetaM (Array Name) := 
  fun e =>
  do 
  match depth with
  | 0 => return #[]
  | k + 1 => 
  -- let fmt ← PrettyPrinter.ppExpr e
  -- IO.println s!"expr : {e}"
  match ← getCached? e with
  | some offs => return offs
  | none =>
    -- IO.println "matching"
    let res ← match e with
      | Expr.bvar ..       => return #[]
      | Expr.fvar ..       => return #[]
      | Expr.const name ..  =>
        do
        if ← (isWhiteListed name) 
          then return #[name] 
          else
          if ← (isNotAux name)  then
            match ←  nameExpr?  name with
            | some e => recExprNames k e
            | none => return #[]
          else pure #[]        
      | Expr.app f a .. => 
          do  
            -- IO.println "app"
            let ftype? ← inferType? f 
            -- IO.println "got ftype"
            let expl? := 
              ftype?.map $ fun ftype =>
              (ftype.binderInfo.isExplicit)
            let expl := expl?.getD true
            -- IO.println s!"got expl: {expl}"
            let s ←  
              if !expl then 
                -- IO.println a
                match a with
                | Expr.const name ..  =>
                    do
                    if ← (isWhiteListed name) 
                      then
                        return (← recExprNames k f).push name
                      else recExprNames k f 
                | _ =>                  
                  -- IO.println s!"using only f: {f}"   
                  recExprNames k f 
                else return (← recExprNames k f) ++ (← recExprNames k a)
            return s
      | Expr.lam _ _ b _ => 
          do
            -- IO.println s!"lam; body: {b}"
            return ← recExprNames k b 
      | Expr.forallE _ _ b _ => do
          return  ← recExprNames k b 
      | Expr.letE _ _ v b _ => 
            return (← recExprNames k b) ++ (← recExprNames k v)
      | _ => pure #[]
    cache e res
    return res

/-- names that are offspring of the constant with a given name -/
def offSpring? (depth: Nat)(name: Name) : MetaM (Option (Array Name)) := do
  let expr? ← nameExpr?  name
  match expr? with
  | some e => 
    return  some <| (← recExprNames depth e)
  | none =>
    IO.println s!"no expr for {name}" 
    return none

initialize simplifyCache : IO.Ref (HashMap Expr Expr) ← IO.mkRef HashMap.empty

def Lean.Expr.simplify(e: Expr) : MetaM Expr := do 
  try 
  let cache ← simplifyCache.get
  match cache.find? e with
  | none => 
    let (r, _) ← simp e (← Simp.Context.mkDefault)
    simplifyCache.set (cache.insert e r.expr)
    return r.expr
  | some expr => return expr
  catch _ => return e

def excludeSuffixes := #[`dcasesOn, `recOn, `casesOn]

#eval (`dcasesOn).isSuffixOf (`AlgebraicGeometry.IsAffine.dcasesOn)

/-- 
Array of constants, names in their definition, and names in their type. 
-/
def offSpringShallowTriple(excludePrefixes: List Name := [])(depth: Nat)
              : MetaM (Unit) :=
  do
  let keys ←  constantNameTypes  
  IO.println s!"Tokens: {keys.size}"
  let goodKeys := keys.filter fun (name, _) =>
    !(excludePrefixes.any (fun pfx => pfx.isPrefixOf name)) && !(excludeSuffixes.any (fun pfx => pfx.isSuffixOf name))
  IO.println s!"Tokens considered (excluding system code): {goodKeys.size}"
  let mut count := 0
  for (n, type) in  (goodKeys) do
      IO.println s!"Token: {n}"
      let l := (← offSpring? depth n).getD #[]
      IO.println s!"Offspring: {l.size}"
      -- let type ← type.simplify
      -- IO.println "simplified"
      let l := l.filter fun n => !(excludePrefixes.any (fun pfx => pfx.isPrefixOf n)) && !(excludeSuffixes.any (fun pfx => pfx.isSuffixOf n))
      -- IO.println s!"Computing offspring for {type}"
      let tl ←  recExprNames depth type
      IO.println s!"Type offspring: {tl.size}"
      let tl := tl.filter fun n => !(excludePrefixes.any (fun pfx => pfx.isPrefixOf n))
      -- IO.println s!"Type offspring (excluding system code): {tl.size}"
      IO.eprintln s!"- name: {n}"
      IO.eprintln <| s!"  defn: " ++ ((s!"{l}").drop 1)
      IO.eprintln <| s!"  type: " ++ ((s!"{tl}").drop 1)
      IO.eprintln ""
      count := count + 1
      IO.println s!"Completed: {count} (out of {goodKeys.size})"
  return ()

  
def offSpringShallowTripleCore (depth: Nat): 
    CoreM Unit := 
          (offSpringShallowTriple excludePrefixes depth).run' 

#eval ([`this, `that]).toString
