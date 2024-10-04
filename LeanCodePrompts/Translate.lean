import Lean
import Lean.Meta
import Lean.Parser
import LeanAide.TheoremElab
import LeanAide.Lean4Names
import LeanAide.TheoremEquality
import LeanAide.IP
import LeanAide.PromptBuilder
import LeanCodePrompts.SpawnNearestEmbeddings
import Lean.Meta.Tactic.TryThis
import Batteries.Util.Pickle
import LeanCodePrompts.ChatClient
import LeanAide.StatementSyntax
import LeanAide.TranslateM
import LeanAide.PromptBuilder
import LeanAide.ConstDeps
import LeanAide.SimpleFrontend

open Lean Meta Elab Parser Command
open LeanAide.Meta

register_option lean_aide.translate.prompt_size : Nat :=
  { defValue := 10
    group := "lean_aide.translate"
    descr := "Number of document strings in a prompt (default 10)" }

register_option lean_aide.translate.concise_desc_size : Nat :=
  { defValue := 0
    group := "lean_aide.translate"
    descr := "Number of concise descriptions in a prompt (default 0)" }


register_option lean_aide.translate.choices : Nat :=
  { defValue := 10
    group := "lean_aide.translate"
    descr := "Number of outputs to request in a query (default 5)." }

register_option lean_aide.translate.use_defintions : Bool :=
  { defValue := true
    group := "lean_aide.translate"
    descr := "Whether to use docstrings of definitions (in addition to theorems)." }

register_option lean_aide.translate.definition_penalty : Nat :=
  { defValue := 20
    group := "lean_aide.translate"
    descr := "Penalty for a prompt being from a definition scaled by 10" }

register_option lean_aide.translate.model : String :=
  { defValue := "gpt-3.5-turbo"
    group := "lean_aide.translate"
    descr := "Model to use (gpt-3.5-turbo)." }

register_option lean_aide.translate.azure : Bool :=
  { defValue := false
    group := "lean_aide.translate"
    descr := "Whether to use Azure OpenAI." }

register_option lean_aide.translate.url? : String :=
  { defValue := ""
    group := "lean_aide.translate"
    descr := "Local url to query. Empty string for none" }

register_option lean_aide.translate.greedy : Bool :=
  { defValue := false
    group := "lean_aide.translate"
    descr := "Whether to choose the first elaboration." }

register_option lean_aide.translate.has_sysprompt : Bool :=
  { defValue := true
    group := "lean_aide.translate"
    descr := "Whether the server has a system prompt." }

/--
Number of similar sentences to query in interactive mode
-/
def promptSize : CoreM Nat := do
  return  lean_aide.translate.prompt_size.get (← getOptions)

/--
Number of similar concise descriptions to query in interactive mode
-/
def conciseDescSize : CoreM Nat := do
  return  lean_aide.translate.concise_desc_size.get (← getOptions)


/--
Parameters for a chat query in interactive mode
-/
def chatParams : CoreM ChatParams := do
  let opts ← getOptions
  return {
    n := lean_aide.translate.choices.get opts,
    temp := 0.8
  }

def greedy : CoreM Bool := do
  return lean_aide.translate.greedy.get (← getOptions)

def hasSysPrompt : CoreM Bool := do
  return lean_aide.translate.has_sysprompt.get (← getOptions)

/--
Chat server to use in interactive mode
-/
def chatServer : CoreM ChatServer := do
  let model := lean_aide.translate.model.get (← getOptions)
  let opts ← getOptions
  if lean_aide.translate.azure.get opts then
    return ChatServer.azure
  else
    let url := lean_aide.translate.url?.get opts
    if url.isEmpty then
      return ChatServer.openAI model
    else
      return ChatServer.generic model url (← hasSysPrompt)


/--
Flip prompt; should be corrected before use.
-/
def makeFlipPrompt(query : String)(examples: Array ChatExample) : Json:= sysMessages sysPrompt' (examples.toList.map (fun ⟨x, y⟩  => ⟨y, x⟩)) query


/-- make prompt for reverse translation from prompt pairs -/
def makeFlipStatementsPrompt(statement : String)(pairs: Array (String × String)) : String :=
      pairs.foldr (fun  (ds, thm) acc =>
s!"{thm} :=
/- {ds} -/

{acc}"
          ) s!"{statement} :=
/- "

/-!
Caching, polling etc to avoid repeatedly calling servers
-/

initialize webCacheJson : IO.Ref (HashMap String (Json × Json × Array (String × Json))) ← IO.mkRef (HashMap.empty)

initialize pendingJsonQueries : IO.Ref (HashSet String)
    ← IO.mkRef (HashSet.empty)

def getCachedJson? (s: String) : IO (Option (Json × Json × Array (String × Json))) := do
  let cache ← webCacheJson.get
  return cache.find? s

def cacheJson (s: String)(js: Json × Json × Array (String × Json))  : IO Unit := do
  let cache ← webCacheJson.get
  webCacheJson.set (cache.insert s js)
  return ()

partial def pollCacheJson (s : String) : IO <| Json × Json × Array (String × Json) := do
  let cache ← webCacheJson.get
  match cache.find? s with
  | some jsBlob => return jsBlob
  | none => do
    IO.sleep 200
    pollCacheJson s

/-- check if there is a valid elaboration after translation, autocorrection -/
def hasElab (s: String) : TranslateM Bool := do
  let elab? ← elabThm4 s
  return elab?.toOption.isSome

/--
Fixed prompts without names from Lean Chat
-/
def fixedPrompts:= #[("If $z_1, \\dots, z_n$ are complex, then $|z_1 + z_2 + \\dots + z_n|\\leq |z_1| + |z_2| + \\dots + |z_n|$.", "(n : ℕ) (f : ℕ → ℂ) :\n Complex.abs (∑ i in Finset.range n, f i) ≤ ∑ i in Finset.range n, Complex.abs (f i)"), ("If x and y are in $\\mathbb{R}^n$, then $|x+y|^2 + |x-y|^2 = 2|x|^2 + 2|y|^2$.", "(n : ℕ) (x y : EuclideanSpace ℝ (Fin n)) :\n ‖x + y‖^2 + ‖x - y‖^2 = 2*‖x‖ ^2 + 2*‖y‖^2"), ("If $x$ is an element of infinite order in $G$, prove that the elements $x^n$, $n\\in\\mathbb{Z}$ are all distinct.", "(G : Type*) [Group G] (x : G) (hx : x ≠ 1) (hx_inf : ∀ n : ℕ, x ^ n ≠ 1) : ∀ m n : ℤ, m ≠ n → x ^ m ≠ x ^ n"), ("Let $X$ be a topological space; let $A$ be a subset of $X$. Suppose that for each $x\\in A$ there is an open set $U$ containing $x$ such that $U\\subset A$. Show that $A$ is open in $X$.", "(X : Type*) [TopologicalSpace X]\n (A : Set X) (hA : ∀ x ∈ A, ∃ U : Set X, IsOpen U ∧ x ∈ U ∧ U ⊆ A):\n IsOpen A")]

/--
Fixed prompts with names from Lean Chat
-/
def fixedPromptTriples:= #[("If $z_1, \\dots, z_n$ are complex, then $|z_1 + z_2 + \\dots + z_n|\\leq |z_1| + |z_2| + \\dots + |z_n|$.", "(n : ℕ) (f : ℕ → ℂ) :\n Complex.abs (∑ i in Finset.range n, f i) ≤ ∑ i in Finset.range n, Complex.abs (f i)", "abs_sum_leq_sum_abs"), ("If x and y are in $\\mathbb{R}^n$, then $|x+y|^2 + |x-y|^2 = 2|x|^2 + 2|y|^2$.", "(n : ℕ) (x y : EuclideanSpace ℝ (Fin n)) :\n ‖x + y‖^2 + ‖x - y‖^2 = 2*‖x‖ ^2 + 2*‖y‖^2", "sum_add_square_sub_square_eq_sum_square"), ("If $x$ is an element of infinite order in $G$, prove that the elements $x^n$, $n\\in\\mathbb{Z}$ are all distinct.", "(G : Type*) [Group G] (x : G) (hx : x ≠ 1) (hx_inf : ∀ n : ℕ, x ^ n ≠ 1) : ∀ m n : ℤ, m ≠ n → x ^ m ≠ x ^ n", "distinct_powers_of_infinite_order_element"), ("Let $X$ be a topological space; let $A$ be a subset of $X$. Suppose that for each $x\\in A$ there is an open set $U$ containing $x$ such that $U\\subset A$. Show that $A$ is open in $X$.", "(X : Type*) [TopologicalSpace X]\n (A : Set X) (hA : ∀ x ∈ A, ∃ U : Set X, IsOpen U ∧ x ∈ U ∧ U ⊆ A):\n IsOpen A", "subset_of_open_subset_is_open")]

/--
Fixed prompts with names from Lean Chat in JSON format
-/
def fixedPromptsJson : Array <| String × Json :=
  fixedPromptTriples.map (fun (ds, thm, name) =>
    (ds,
    Json.mkObj [("docString", ds), ("type", thm), ("name", name)]))

/--
Given a string, find the nearest documentation strings in Mathlib and return the corresponding theorem data.
-/
def getNearestDocs (s: String)(numSim : Nat)(numConcise: Nat)(numDesc : Nat) :
  TranslateM <| Except String (Array (String × Json)) := do
    let dataMap ← getEmbedMap
    let check ← (← picklePath "docString").pathExists
    unless check do
      return Except.error "Mathlib embeddings not found; run `lake exe fetch_embeddings` first to fetch them."
    let start ← IO.monoMsNow
    let finish ← IO.monoMsNow
    IO.eprintln s!"Embedding query time: {finish - start}"
    let outJs ←
       getNearestEmbeddingsFull s (← embedQueryCached s) numSim 2.0 (dataMap := dataMap)
    logTimed "obtained neighbours"
    let outJs' ←
      if numConcise > 0 then
      getNearestEmbeddingsFull s (← embedQueryCached s) numConcise 2.0 "concise-description" (dataMap := dataMap)
      else pure <| (Json.arr #[]).compress
    logTimed "obtained concise descriptions"
    let outJs'' ←
      if numDesc > 0 then
      getNearestEmbeddingsFull s (← embedQueryCached s) numDesc 2.0 "description" (dataMap := dataMap)
      else pure <| (Json.arr #[]).compress
    logTimed "obtained descriptions"
    match Json.parse outJs, Json.parse outJs', Json.parse outJs''  with
    | Except.error e, _, _ => return Except.error e
    | _, Except.error e, _ => return Except.error e
    | _, _, Except.error e => return Except.error e
    | Except.ok js, Except.ok js', Except.ok js'' =>
      match js.getArr?, js'.getArr?, js''.getArr? with
      | Except.error e, _, _ => return Except.error e
      | _, Except.error e, _ => return Except.error e
      | _, _, Except.error e => return Except.error e
      | Except.ok jsArr, Except.ok jsArr', Except.ok jsArr'' =>
        let mut pairs : Array <| String × Json := #[]
        for js in jsArr do
          match js.getObjValAs? String "docString" with
          | Except.error e => return Except.error e
          | Except.ok doc =>
            pairs := pairs.push (doc, js)
        for js in jsArr' do
          match js.getObjValAs? String "docString" with
          | Except.error e => return Except.error e
          | Except.ok doc =>
            pairs := pairs.push (doc, js)
        for js in jsArr'' do
          match js.getObjValAs? String "docString" with
          | Except.error e => return Except.error e
          | Except.ok doc =>
            pairs := pairs.push (doc, js)
        return Except.ok pairs.reverse

/-- prompts generated from the declarations in the current file. -/
def getEnvPrompts (moduleNames : Array Name := .empty) (useMain? : Bool := true) : MetaM <| Array (String × String):= do
  if moduleNames.isEmpty && !useMain? then
    return #[]
  let env ← getEnv
  let moduleNames :=
    if useMain? then
      moduleNames.push env.mainModule
    else moduleNames
  let moduleIdxs := moduleNames.filterMap env.getModuleIdx?

  List.toArray <$> env.constants.toList.filterMapM fun ⟨nm, ci⟩ ↦ do
    let some _ := moduleIdxs.contains <$> env.getModuleIdxFor? nm  | pure none
    let some docstring ← findDocString? env nm | pure none
    let some kind := (
      match ci with
        | .defnInfo _ => some "def"
        | .thmInfo _  => some "theorem"
        |     _       => none
    ) | pure none
    let some type ← try? (Format.pretty <$> PrettyPrinter.ppExpr ci.type) | pure none
    return some ⟨docstring, s!"{kind} : {type} :="⟩


/-- given string to translate, build prompt and query OpenAI; returns JSON response
-/
def getLeanCodeJson (s: String)
    (server: ChatServer := ChatServer.openAI)(params: ChatParams := {})
    (pb: PromptExampleBuilder := .embedBuilder 8 0 0)
    (includeFixed: Bool := Bool.false)(toChat : ToChatExample := simpleChatExample)(header: String := "Theorem")
    (useDefs : String → TranslateM (Array String) := fun _ => pure #[]) : TranslateM <| Json × Json × Array (String × Json) := do
  logTimed s!"translating string `{s}` with  examples"
  setContext s
  match ← getCachedJson? s with
  | some js => return js
  | none =>
    let pending ←  pendingJsonQueries.get
    if pending.contains s then pollCacheJson s
    else
      let pending ←  pendingJsonQueries.get
      pendingJsonQueries.set (pending.insert s)
      -- work starts here; before this was caching, polling etc
      let pairs ← pb.getPromptPairs s
      let pairs := if includeFixed then pairs ++ fixedPromptsJson else pairs
      let pairs  := pairs.filter (fun (s, _) => s.length < 100)
      let dfns ← useDefs s
      let prelude :=
        if dfns.isEmpty then ""
      else
        let defsBlob := dfns.foldr (fun acc df => acc ++ "\n\n" ++ df) ""
        s!"Your goal is to translate from natural language to Lean. The following are some definitions that may be relevant:\n\n{defsBlob}"
      let pairs := pairs.map fun (doc, thm) =>
        let isThm :=
          thm.getObjValAs? Bool "isProp" |>.toOption |>.getD true
        let head := if isThm then "Theorem" else "Definition"
        (prelude ++ s!"Translate the following statement into Lean 4:\n## {head}: " ++ doc ++ "\n\nGive ONLY the Lean code", thm)
      trace[Translate.info] m!"prompt pairs: \n{pairs}"
      let examplesM := pairs.filterMapM toChat
      trace[Translate.info] m!"examples: \n{(← examplesM).size}"
      let s' := s!"Translate the following statement into Lean 4:\n## {header}: " ++ s ++ "\n\nGive ONLY the Lean code"
      let messages ← mkMessages s' (← examplesM) (← transPrompt) !server.hasSysPropmpt
      trace[Translate.info] m!"prompt: \n{messages.pretty}"
      logTimed "querying server"
      let fullJson ← server.query messages params
      let outJson :=
        (fullJson.getObjVal? "choices").toOption.getD (Json.arr #[])
      logTimed "obtained gpt response"
      let pending ←  pendingJsonQueries.get
      pendingJsonQueries.set (pending.erase s)
      cacheJson s (outJson, messages, pairs)
      return (outJson, messages, pairs)

/-- Given an array of outputs, tries to elaborate them with translation and autocorrection and returns the best choice, throwing an error if nothing elaborates.  -/
def bestElab (output: Array String) : TranslateM Expr := do
  trace[Translate.info] m!"output:\n{output}"
  let mut elabStrs : Array String := Array.empty
  let mut elaborated : Array Expr := Array.empty
  let mut fullElaborated : Array Expr := Array.empty
  let mut cache : HashMap String (Except String Expr) :=
    HashMap.empty
  for out in output do
    -- IO.println s!"elaboration called: {out}"
    let elab? ←
      match cache.find? out with
      | some elab? =>
        pure elab?
      | none =>
        let res ← elabThm4 out
        cache := cache.insert out res
        pure res
    match elab? with
      | Except.error _ => pure ()
      | Except.ok expr =>
          elaborated := elaborated.push expr
          elabStrs := elabStrs.push out
          trace[Translate.info] m!"elaborated: {out}"
          if !(← whnf expr).hasExprMVar then
            fullElaborated := fullElaborated.push expr
  if elaborated.isEmpty then
    let mut errors : Array Json := #[]
    for out in output do
      let stx ← parseThm4 out
      match stx with
      | Except.error err =>
          errors := errors.push <|
            Json.mkObj [("parsed", false),
              ("error", Json.str err), ("output", Json.str out)]
          pure ()
      | Except.ok stx => do
        errors := errors.push <|
            Json.mkObj [("parsed", true),
              ("syntax", stx.reprint.get!), ("output", Json.str out)]
    let errorJson := Json.arr errors
    appendLog "translate_fail_error" errorJson
    mkSyntheticSorry (mkSort levelZero)
  else
    logTimed "elaborated outputs, starting majority voting"
    let priority :=
        if fullElaborated.isEmpty then elaborated else fullElaborated
    let groupSorted ← groupThmExprsSorted priority
    logTimed "finished majority voting"
    return (groupSorted[0]!)[0]!

structure ElabResult where
  term : Expr
  allElaborated : Array String
  groups : Array (Array String)

def ElabResult.view (er: ElabResult) : MetaM String :=
  er.term.view

structure TranslateResult extends ElabResult where
  view : String

def ElabResult.withView (er: ElabResult) : MetaM TranslateResult := do
  return {
    term := er.term,
    allElaborated := er.allElaborated,
    groups := er.groups,
    view := (← er.view)
  }


/-- Given an array of outputs, tries to elaborate them with translation and autocorrection and optionally returns the best choice as well as all elaborated terms (used for batch processing, interactive code uses `bestElab` instead)  -/
def bestElab? (output: Array String)(maxVoting: Nat := 5) : TranslateM (Except Json ElabResult) := do
  -- IO.println s!"arrayToExpr? called with {output.size} outputs"
  let mut elabStrs : Array String := Array.empty
  let mut elaborated : Array Expr := Array.empty
  let mut fullElaborated : Array Expr := Array.empty
  let mut cache : HashMap String (Except String Expr) :=
    HashMap.empty
  logTimed "elaborating outputs"
  for out in output do
    -- IO.println s!"elaboration called: {out}"
    let elab? ←
      match cache.find? out with
      | some elab? => pure elab?
      | none =>
        let res ← elabThm4 out
        cache := cache.insert out res
        pure res

    match elab? with
      | Except.error _ => pure ()
      | Except.ok expr =>
          elaborated := elaborated.push expr
          elabStrs := elabStrs.push out
          if !(← whnf expr).hasExprMVar then
            fullElaborated := fullElaborated.push expr
  if elaborated.isEmpty then
    let mut errors : Array Json := #[]
    for out in output do
      let stx ← parseThm4 out
      match stx with
      | Except.error err =>
          errors := errors.push <|
            Json.mkObj [("parsed", false),
              ("error", Json.str err), ("output", Json.str out)]
          pure ()
      | Except.ok stx => do
        errors := errors.push <|
            Json.mkObj [("parsed", true),
              ("syntax", stx.reprint.get!), ("output", Json.str out)]
    let errorJson := Json.arr errors
    return Except.error errorJson
  else
    logTimed "elaborated outputs, starting majority voting"
    -- let priority :=
    --     if fullElaborated.isEmpty then elaborated else fullElaborated
    -- IO.eprintln s!"grouping priority: {priority.size}"
    let groupSorted ← groupThmExprsSorted (elaborated.toList.take maxVoting).toArray -- priority
    let thm := (groupSorted[0]!)[0]!
    let gpView ←  groupSorted.mapM (fun gp => gp.mapM (fun e => e.view))
    logTimed "obtained majority vote"
    return Except.ok ⟨thm, elabStrs, gpView⟩


def greedyBestExpr? (output: Array String) : TranslateM (Option Expr) := do
    output.findSomeM? <| fun out => do
      let el? ← elabThm4 out
      pure el?.toOption

def greedyStrictBestExpr? (output: Array String) :
    TranslateM (Option Expr) := do
  output.findSomeM? <| fun out => do
    let el? ← elabThm4 out
    return el?.toOption.filter (fun e => !e.hasMVar && !e.hasSorry)


def matchElab? (output: Array String)(defs : Array <| Name × String):
  TranslateM (Option Name) := do
  let elabDefs : Array (Name × Expr) ←  defs.filterMapM (fun (nm, s) => do
    let el? ← elabThm4 s
    let el? := el?.toOption
    pure <| el?.map (fun e => (nm, e)))
  output.findSomeM? (fun out => do
    let el? ← elabThm4Aux out
    match el? with
    | Except.error _ => pure none
    | Except.ok e₁ =>
      let pair? ← elabDefs.findM? (fun (_, e₂) => do
        provedEquiv e₁ e₂)
      pure <| pair?.map (fun (nm, _) => nm))

def matchElabs (output: Array String)(defs : Array <| Name × String):
  TranslateM (List Name) := do
  let elabDefs : Array (Name × Expr) ←  defs.filterMapM (fun (nm, s) => do
    let el? ← elabThm4 s
    let el? := el?.toOption
    pure <| el?.map (fun e => (nm, e)))
  output.toList.filterMapM (fun out => do
    let el? ← elabThm4Aux out
    match el? with
    | Except.error _ => pure none
    | Except.ok e₁ =>
      let pair? ← elabDefs.findM? (fun (_, e₂) => do
        provedEquiv e₁ e₂)
      pure <| pair?.map (fun (nm, _) => nm))

def sufficientElab? (output: Array String)(defs : Array <| Name × String):
  TranslateM (Option Name) := do
  let elabDefs : Array (Name × Expr) ←  defs.filterMapM (fun (nm, s) => do
    let el? ← elabThm4 s
    let el? := el?.toOption
    pure <| el?.map (fun e => (nm, e)))
  output.findSomeM? (fun out => do
    let el? ← elabThm4Aux out
    match el? with
    | Except.error _ => pure none
    | Except.ok e₁ =>
      let pair? ← elabDefs.findM? (fun (_, e₂) => do
        provedSufficient e₁ e₂)
      pure <| pair?.map (fun (nm, _) => nm))


/-- reverse translation from `Lean` to natural language -/
def leanToPrompt (thm: String)(numSim : Nat:= 5)
  (numConcise : Nat := 0) (numDesc: Nat := 0)(temp : JsonNumber := 0)
  (textField : String := "text")  : TranslateM String := do
    let pairs? ←
      getNearestDocs thm numSim numConcise numDesc
    let pairs := pairs?.toOption.getD #[]
    let examples := pairs.filterMapM simpleChatExample
    let prompt := makeFlipPrompt thm (← examples)
    let fullJson ← (ChatServer.openAI).query prompt
      {temp := temp, n := 1}
    let outJson :=
      (fullJson.getObjVal? "choices").toOption.getD (Json.arr #[])
    let out? := (outJson.getArrVal? 0) >>= fun js => js.getObjVal? textField
    let outJson :=
        match (out?) with
        | Except.error s => Json.str s!"query for translation failed: {s}"
        | Except.ok js => js
    return outJson.getStr!

def egThm := "theorem eg_thm : ∀ n: Nat, ∃ m : Nat, m > n ∧ m % 2 = 0"


-- #eval egPrompt

-- #eval statementToDoc egThm 5 0

-- #eval leanToPrompt "∀ {p : ℕ} [inst : Fact (Nat.Prime p)], p = 2 ∨ p % 2 = 1"

-- #eval leanToPrompt "∀ {α : Type u} {x : FreeGroup α}, x ≠ 1 → ¬IsOfFinOrder x"

-- #eval leanToPrompt "{  n :  ℕ } ->  Even   (    (   n +  1  ) * n  )"

/-- array of outputs extracted from OpenAI Json -/
def exprStrsFromJson (json: Json) : TranslateM (Array String) := do
  let outArr : Array String ←
    match json.getArr? with
    | Except.ok arr =>
        let parsedArr : Array String ←
          arr.filterMapM <| fun js =>
            match js.getObjVal? "text" with
              | Except.ok jsstr =>
                match jsstr.getStr? with
                | Except.ok str => pure (some str)
                | Except.error e =>
                  throwError m!"json string expected but got {js}, error: {e}"
              | Except.error _ =>
                throwError m!"no text field"
        pure parsedArr
    | Except.error e => throwError m!"json parsing error: {e}"
  return outArr

/-- array of outputs extracted from Json Array -/
def exprStrsFromJsonStr (jsString: String) : TranslateM (Array String) := do
  try
  let json := Lean.Json.parse  jsString |>.toOption.get!
  let outArr : Array String ←
    match json.getArr? with
    | Except.ok arr =>
        let parsedArr : Array String ←
          arr.filterMapM <| fun js =>
            match js.getStr? with
            | Except.ok str => pure (some str)
            | Except.error e =>
              throwError m!"json string expected but got {js}, error: {e}"
        pure parsedArr
    | Except.error _ => pure #[jsString]
  return outArr
  catch _ =>
    pure #[jsString]

-- #eval jsonStringToExprStrArray "simple"
-- #eval jsonStringToExprStrArray "[\"simple\", \"simple2\"]"


/-- given json returned by open-ai obtain the best translation -/
def jsonToExpr' (json: Json)(greedy: Bool)(splitOutput := false) : TranslateM Expr := do
  let output ← getMessageContents json
  let output := if splitOutput
    then
      splitColEqSegments output
    else output
  if greedy then
    match ← greedyBestExpr? output with
    | some e => return e
    | none => throwError "no elaboration found"
  else
    bestElab output

/-- translation from a comment-like syntax to a theorem statement -/
elab "//-" cb:commentBody  : term => do
  let s := cb.raw.getAtomVal
  let s := (s.dropRight 2).trim
  -- querying codex
  let (js, _) ←
    getLeanCodeJson  s
      (pb := PromptExampleBuilder.embedBuilder 8 0 0) |>.run' {}
  -- filtering, autocorrection and selection
  let e ←
    jsonToExpr' js true !(← chatParams).stopColEq |>.run' {}
  trace[Translate.info] m!"{e}"
  return e

/--
Write a theorem in the form `(a : A) ... : type` instead of `(a : A) → ... → type`
-/
def uncurriedView(numArgs: Nat)(e: Expr) : MetaM String :=
  match numArgs with
  | 0 => do return " : " ++ (← e.view)
  | k +1 =>
    match e with
    | Expr.forallE n t _ bi => do
      let core := s!"{n.eraseMacroScopes} : {← t.view}"
      let typeString :=s!"{← t.view}"
      let argString := match bi with
      | BinderInfo.implicit => "{"++ core ++ "}"
      | BinderInfo.strictImplicit => "{{ "++ core ++ "}}"
      | BinderInfo.instImplicit =>
        if (`inst).isPrefixOf n then s!"[{typeString}]"
          else s!"[{core}]"
      | BinderInfo.default => s!"({core})"
      let tail : String ←
        withLocalDecl `func BinderInfo.default e fun func =>
          withLocalDecl n bi t fun arg => do
            let fx := mkAppN func #[arg]
            let newType ← inferType fx
            uncurriedView k newType
      return " " ++ argString ++ tail
    | _ => do return " : " ++ (← e.view)

/--
Write a theorem in the form `(a : A) ... : type` instead of `(a : A) → ... → type`
-/
elab "uncurry2" e:term : term => do
  let e ← Term.elabTerm e none
  let e ← uncurriedView 2 e
  return mkStrLit e

universe u

/--
Translate a string and output as a string.
-/
def translateViewM (s: String)
  (server: ChatServer := ChatServer.openAI)(params : ChatParams := {}) (numSim: Nat := 8)(numConcise numDesc : ℕ := 0)(toChat : ToChatExample := simpleChatExample)(useDefs : String → TranslateM (Array String) := fun _ => pure #[])
  : TranslateM String := do
  logTimed "starting translation"
  let (js, _) ← getLeanCodeJson  s server params
        (pb := PromptExampleBuilder.embedBuilder numSim numConcise numDesc) (toChat := toChat) (useDefs := useDefs)
  let output ← getMessageContents js
  trace[Translate.info] m!"{output}"
  -- let output := params.splitOutputs output
  let e? ← bestElab? output
  match e? with
  | Except.ok res => do
    res.view
  | Except.error _ => do
    let view? ← output.findSomeM? <| fun s => do
      let elab? ← elabThm4 s
      match elab? with
      | Except.ok expr =>
        trace[Translate.info] m!"elaborated: {expr}"
        pure <| some (← expr.view)
      | Except.error e =>
        trace[Translate.warning] m!"elaboration failed: {e} for {s}"
        pure none
    return view?.getD "False"

def translateToProp? (s: String)
  (server: ChatServer := ChatServer.openAI)(params : ChatParams := {}) (pb := PromptExampleBuilder.embedBuilder 8 0 0)(toChat : ToChatExample := simpleChatExample) (useDefs : String → TranslateM (Array String) := fun _ => pure #[])
   : TranslateM (Option Expr) := do
  logTimed "starting translation"
  let (js, _) ← getLeanCodeJson  s server params
        pb  (toChat := toChat) (useDefs := useDefs)
  let output ← getMessageContents js
  trace[Translate.info] m!"{output}"
  -- let output := params.splitOutputs output
  let e? ← greedyStrictBestExpr? output
  return e?

/--
Translating a definition greedily by parsing as a command
-/
def translateDefCmdM? (s: String)
  (server: ChatServer := ChatServer.openAI)(params : ChatParams := {}) (pb := PromptExampleBuilder.embedBuilder 8 0 0)
  (toChat : ToChatExample := docChatExample) (useDefs : String → TranslateM (Array String) := fun _ => pure #[]): TranslateM <| Option Syntax.Command := do
  logTimed "starting translation"
  let (js, _) ← getLeanCodeJson  s server params
        (pb := pb)  (toChat := toChat) (header := "Definition") (useDefs := useDefs)
  let output ← getMessageContents js
  trace[Translate.info] m!"{output}"
  let cmd? :  Option Syntax ← output.findSomeM? fun s =>
    do
      let cmd? := runParserCategory (← getEnv) `command s |>.toOption
      let check ← checkElabFrontM s
      if check.isEmpty then pure cmd? else
        trace[Translate.info] s!"Not a valid command:\n{s}"
        for chk in check do
          trace[Translate.info] chk
        pure none
  return cmd?.map (fun cmd => ⟨cmd⟩)

def translateDefViewM? (s: String)
  (server: ChatServer := ChatServer.openAI)(params : ChatParams := {}) (pb := PromptExampleBuilder.embedBuilder 8 8 0)(toChat : ToChatExample := docChatExample)
   : TranslateM <| Option String := do
  let cmd? ← translateDefCmdM? s server params pb toChat
  let fmt? ← cmd?.mapM fun cmd =>
    PrettyPrinter.ppCommand cmd
  return fmt?.map (·.pretty)


syntax (name := ltrans) "l!" str : term

open PrettyPrinter Tactic

@[term_elab ltrans] def ltransImpl : Term.TermElab :=
  fun stx _ => do
  match stx with
  | `(l! $s:str) =>
  let s := s.getString
  let (js, _) ←
    getLeanCodeJson  s (← chatServer) (← chatParams)
      (pb := PromptExampleBuilder.embedBuilder  (← promptSize) (← conciseDescSize) 0)|>.run' {}
  let e ← jsonToExpr' js (← greedy) !(← chatParams).stopColEq |>.run' {}
  logTimed "obtained expression"
  let stx' ← delab e
  logTimed "obtained syntax"
  TryThis.addSuggestion stx stx'
  logTimed "added suggestion"
  return e
  | _ => throwUnsupportedSyntax

def findTheorem? (s: String)(numSim : ℕ := 8)
  (numConcise numDesc : ℕ := 0) : TranslateM (Option Name) := do
  let (js, _, prompts) ← getLeanCodeJson s (pb := PromptExampleBuilder.embedBuilder numSim numConcise numDesc)
  let output ← getMessageContents js
  trace[Translate.info] m!"thmPairs: {prompts}"
  let thmPairs := prompts.reverse.map (fun (_, js) =>
    (js.getObjValAs? String "name" |>.toOption.get! |>.toName,
    js.getObjValAs? String "type" |>.toOption.get!))
  matchElab? output thmPairs

def findTheorems (s: String)(numLeanSearch : ℕ := 8)
  (numMoogle : ℕ := 0) : TranslateM (List Name) := do
  let (js, _, prompts) ← getLeanCodeJson s (pb := PromptExampleBuilder.searchBuilder numLeanSearch numMoogle)
  let output ← getMessageContents js
  trace[Translate.info] m!"thmPairs: {prompts}"
  let thmPairs := prompts.reverse.map (fun (_, js) =>
    (js.getObjValAs? String "name" |>.toOption.get! |>.toName,
    js.getObjValAs? String "type" |>.toOption.get!))
  matchElabs output thmPairs

def nearbyTheoremsChunk (s: String)
  (numLeanSearch : Nat := 8) (numMoogle: Nat := 0)  : TranslateM String := do
    let pb : PromptExampleBuilder :=
      PromptExampleBuilder.searchBuilder numLeanSearch numMoogle
    let pairs ← pb.getPromptPairs s
    let statements : Array String ← pairs.filterMapM (fun (doc, js) => do
      let name? := js.getObjValAs? String "name" |>.toOption
      let thm? := js.getObjValAs? String "type" |>.toOption
      let prop? := js.getObjValAs? Bool "isProp" |>.toOption
      match name?, thm?, prop? with
      | some name, some thm, some true =>
        mkTheoremWithDoc name.toName thm doc
      | _, _,_ => pure <| none
    )
    return statements.foldl (fun acc s => acc ++ s ++ "\n\n") ""

def nearbyDefs (numLeanSearch : Nat := 8) (numMoogle: Nat := 0)
    (numClosure: Nat := 4)  : String → TranslateM (Array Name) :=
    fun s => do
    let pb : PromptExampleBuilder :=
      PromptExampleBuilder.searchBuilder numLeanSearch numMoogle
    let pairs ← pb.getPromptPairsOrdered s
    let searchNames : Array Name := pairs.filterMap (fun (_, js) => do
      js.getObjValAs? Name "name" |>.toOption
    )
    let defNames : Array Name := pairs.filterMap (fun (_, js) => do
      let prop := js.getObjValAs? Bool "isProp" |>.toOption |>.getD true
      if prop then none else js.getObjValAs? Name "name" |>.toOption
    )
    let closureNames ←  bestDefsInConsts numClosure searchNames.toList 1
    return defNames ++ closureNames

def matchingTheoremsAI (server: ChatServer := ChatServer.openAI)(params: ChatParams := {})(s: String)(n: ℕ := 3)(numLeanSearch : ℕ := 8)
  (numMoogle : ℕ := 0)  : TranslateM (List Name) := do
    let chunk ← nearbyTheoremsChunk s numLeanSearch numMoogle
    let prompt := s!"The following are some theorems in Lean with informal statements as documentation strings\n\n{chunk}\n\n---\n¬List the names of theorems that are equivalent to the following informal statement:\n\n{s}.\n\nOutput ONLY a (possibly empty) list of names."
    let completions ← server.completions prompt (← sysPrompt) n params
    let entries : Array (Array String) := completions.filterMap fun s =>
      let js? := Json.parse s |>.toOption
      match js? with
      | some js =>
        fromJson? js |>.toOption
      | none => none
    return entries.join.toList.map (·.toName)

def matchingTheorems (server: ChatServer := ChatServer.openAI)
    (params: ChatParams := {})(s: String)(n: ℕ := 3)(numLeanSearch : ℕ := 8)
    (numMoogle : ℕ := 4)  : TranslateM (List Name) := do
  let elabMatch ← findTheorems s numLeanSearch numMoogle
  if elabMatch.isEmpty then
    matchingTheoremsAI server params s n numLeanSearch numMoogle
  else
    pure elabMatch

/--
Translate a string to a Lean expression using the GPT model, returning three componenst:
* The expression, all elaborated expressions, grouped expressions
* All outputs from the LLM
* The prompt used for the LLM.
-/
def translateViewVerboseM (s: String)(server: ChatServer)
  (params: ChatParams)(pb: PromptExampleBuilder := .embedBuilder 10 0 0)
  (toChat : ToChatExample := simpleChatExample) (useDefs : String → TranslateM (Array String) := fun _ => pure #[]) :
  TranslateM ((Option TranslateResult) × Array String × Json) := do
  let dataMap ← getEmbedMap
  IO.println s!"dataMap keys: {dataMap.toList.map Prod.fst}"
  let (js,prompt, _) ←
    getLeanCodeJson s server params pb false toChat (useDefs := useDefs)
  let output ← getMessageContents js
  if output.isEmpty then
    IO.eprintln "no output"
    return (none, output, prompt)
  else
    -- let output := params.splitOutputs output
    let res? ← bestElab? output
    match res? with
    | Except.error jsErr =>
      let js := Json.mkObj [
        ("input", Json.str s),
        ("error", jsErr)]
      appendLog "translate_fail" js
      pure ()
    | Except.ok _ =>
      pure ()
    let view? ←  res?.toOption.mapM fun res => res.withView
    return (view?, output, prompt)
