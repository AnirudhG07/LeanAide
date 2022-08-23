import Lean
import Lean.Meta
import Lean.Parser
import Std
import LeanCodePrompts.CheckParse
import LeanCodePrompts.ParseJson
import LeanCodePrompts.Autocorrect
open Lean Meta Std

open Lean Elab Parser Command

def egJsonSentenceSim : String := "[{'theorem': '{p : ℕ} [fact (nat.prime p)] : p % 2 = 1 ↔ p ≠ 2', 'doc_string': 'A prime `p` satisfies `p % 2 = 1` if and only if `p ≠ 2`.'}, {'theorem': '{n : ℕ} : n % 2 = 1 ↔ n % 4 = 1 ∨ n % 4 = 3', 'doc_string': 'A natural number is odd iff it has residue `1` or `3` mod `4`'}, {'theorem': '{p : ℕ} (hp : nat.prime p) : p.factorization = finsupp.single p 1', 'doc_string': 'The only prime factor of prime `p` is `p` itself, with multiplicity `1`'}, {'theorem': '{m n : ℕ} : even (m ^ n) ↔ even m ∧ n ≠ 0', 'doc_string': ' If `m` and `n` are natural numbers, then the natural number `m^n` is even if and only if `m` is even and `n` is positive.'}]"

def sentenceSimPairs(s: String) : MetaM  <| Except String (Array (String × String)) := do
  let json ← readJson (s.replace "'" "\"") 
  match json.getArr? with
  | Except.ok jsonArr => do
    let pairs ←  jsonArr.mapM fun json => do
      let docstring := (json.getObjVal? "doc_string").toOption.get!.getStr?.toOption.get!
      let thm := (json.getObjVal? "theorem").toOption.get!.getStr?.toOption.get!
      return (docstring, thm)
    return Except.ok pairs
  | Except.error e => return Except.error e

#eval sentenceSimPairs egJsonSentenceSim

def makePrompt(pairs: Array (String × String))(prompt : String) : String := 
      pairs.foldr (fun  (ds, thm) acc => 
        -- acc ++ "/-- " ++ ds ++" -/\ntheorem" ++ thm ++ "\n" ++ "\n"
s!"/-- {ds} -/
theorem {thm} :=

{acc}"
          ) s!"/-- {prompt} -/
theorem "

def egPrompt' : MetaM String := do
    let pairs? ← sentenceSimPairs egJsonSentenceSim
    let pairs := pairs?.toOption.get!
    return makePrompt pairs "Every prime number is either `2` or odd"

#eval egPrompt'


def openAIKey : IO (Option String) := IO.getEnv "OPENAI_API_KEY"

def openAIQuery(prompt: String)(n: Nat := 1)(temp : JsonNumber := ⟨2, 1⟩) : MetaM Json := do
  let key? ← openAIKey
  let key := key?.get!
  let dataJs := Json.mkObj [("model", "code-davinci-002"), ("prompt", prompt), ("temperature", Json.num temp), ("n", n), ("max_tokens", 150), ("stop", Json.arr #[":=", "-/"])]
  let data := dataJs.pretty
  let out ←  IO.Process.output {
        cmd:= "curl", 
        args:= #["https://api.openai.com/v1/completions",
        "-X", "POST",
        "-H", "Authorization: Bearer " ++ key,
        "-H", "Content-Type: application/json",
        "--data", data]}
  readJson out.stdout

def egQuery : MetaM Json := do
  let prompt ← egPrompt'
  openAIQuery prompt 5

-- #eval egQuery


def egBlob' := "[{ \"text\" : \"{p : ℕ} (hp : Nat.Prime p) :  p = 2 ∨ p % 2 = 1 \"},
   { \"text\" : \"(p : ℕ) :  Nat.Prime p ↔ p = 2 ∨ p % 2 = 1 \"},
   { \"text\" : \"{p : ℕ} (hp : Nat.Prime p) : p = 2 ∨ p % 2 = 1 \"},
   { \"text\" : \"(n : ℕ) (hp : Nat.Prime n) : n = 2 ∨ n % 2 = 1 \"},
   { \"text\" : \"{p : ℕ} (hp : Nat.Prime p) : p = 2 ∨ p % 2 = 1 \"},
   { \"text\" : \"Nonsense output to test filtering\"}]"

def caseMapProc (s: String) : IO String := do
  let tmpFile := System.mkFilePath ["web_serv/tmp.json"]
  IO.FS.writeFile tmpFile s
  let out ← 
    IO.Process.output {cmd:= "./amm", args := #["scripts/simplemap.sc"]}
  return out.stdout

initialize webCache : IO.Ref (HashMap String String) ← IO.mkRef (HashMap.empty)

initialize pendingQueries : IO.Ref (HashSet String) 
    ← IO.mkRef (HashSet.empty)

def getCached? (s: String) : IO (Option String) := do
  let cache ← webCache.get
  return cache.find? s

def cache (s jsBlob: String)  : IO Unit := do
  let cache ← webCache.get
  webCache.set (cache.insert s jsBlob)
  return ()

partial def pollCache (s : String) : IO String := do
  let cache ← webCache.get
  match cache.find? s with
  | some jsBlob => return jsBlob
  | none => do
    IO.sleep 200
    pollCache s

def getCodeJson (s: String) : TermElabM String := do
  match ← getCached? s with
  | some s => return s
  | none =>    
    let pending ←  pendingQueries.get
    if pending.contains s then pollCache s
    else 
      let pending ←  pendingQueries.get
      pendingQueries.set (pending.insert s)
      let out ←  
        IO.Process.output {cmd:= "curl", args:= 
          #["-X", "POST", "-H", "Content-type: application/json", "-d", s, "localhost:5000/post_json"]}
      let pending ←  pendingQueries.get
      pendingQueries.set (pending.erase s)
      let res := out.stdout  
          -- ← caseMapProc out.stdout
      if out.exitCode = 0 then cache s res 
        else throwError m!"Web query error: {out.stderr}"
      return res
  -- return out.stdout


def arrayToExpr (output: Array String) : TermElabM Expr := do
  let mut elaborated : Array String := Array.empty
  -- let mut failed: Nat := 0
  for out in output do
    let ployElab? ← polyElabThmTrans out
    match ployElab? with
      | Except.error _ => pure ()
      | Except.ok es =>
        for (_, s) in es do
          elaborated := elaborated.push s 
  -- let elaborated ← output.filterMapM (
  --   fun s => do 
  --     return (← elabThmTrans s).toOption.map (fun (_, s) => s))
  -- logInfo m!"elaborated: {elaborated.size} out of {output.size}, failed {failed}"
  if elaborated.isEmpty then do
    logWarning m!"No valid output from Codex; outputs below"
    for out in output do
      let polyOut ←  polyStrThmTrans out
      for str in polyOut do
        logWarning m!"{str}"
    mkSyntheticSorry (mkSort levelZero)
  else    
    let groupSorted ← groupFuncStrs elaborated
    let topStr := groupSorted[0]![0]!
    let thmExc ← elabFuncTyp topStr
    match thmExc with
    | Except.ok thm => return thm
    | Except.error s => throwError s

def textToExpr (s: String) : TermElabM Expr := do
  let json ← readJson s
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
    | Except.error e => throwError m!"json parsing error: {e}"
  let output := outArr
  arrayToExpr output

def textToExpr' (s: String) : TermElabM Expr := do
  let json ← readJson s
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
  let output := outArr
  arrayToExpr output

def textToExprStx' (s : String) : TermElabM (Expr × TSyntax `term) := do
  let e ← textToExpr' s
  let (stx : Term) ← (PrettyPrinter.delab e)
  return (e, stx)

elab "//-" cb:commentBody  : term => do
  let s := cb.raw.getAtomVal!
  let s := (s.dropRight 2).trim  
  let jsBlob ← getCodeJson  s
  let e ← textToExpr' jsBlob
  logInfo m!"{e}"
  return e

elab "#theorem" name:ident " : " stmt:str ":=" prf:term : command => do
  let (fmlstmt, fmlstx) ← liftTermElabM none $ textToExprStx' egBlob' -- stmt.getString
  logInfoAt stmt m!"{fmlstmt}"
  elabCommand $ ← `(theorem $name:ident : $fmlstx:term := $prf:term)

elab "#example" stmt:str ":=" prf:term : command => do
  let (fmlstmt, fmlstx) ← liftTermElabM none $ textToExprStx' egBlob' -- stmt.getString
  logInfoAt stmt m!"{fmlstmt}"
  elabCommand $ ← `(example : $fmlstx:term := $prf:term)

-- #eval getCodeJson egPrompt