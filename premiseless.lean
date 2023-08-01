import LeanAide.PremiseData
import LeanAide.ProofSearch
open Lean Json Data LeanAide.Meta

def environment : IO Environment := do
  importModules [{module := `Mathlib},
    {module:= `LeanAide.TheoremElab},
    {module:= `LeanAide.PremiseData},
    {module:= `LeanAide.ProofSearch},
    {module := `Mathlib}] {}

def coreContext : Core.Context := 
  {fileName := "", fileMap := ⟨"", #[], #[]⟩, maxHeartbeats := 100000000000, maxRecDepth := 1000000, openDecls := [Lean.OpenDecl.simple `LeanAide.Meta []]
    }   

def main (_: List String) : IO Unit := do
  initSearchPath (← Lean.findSysroot) initFiles
  let env ← environment
  let testLines := 
    (← IO.FS.lines (System.mkFilePath ["rawdata", "premises", "core", "test.jsonl"]))
  let mut count := 0
  let mut premiselessCount := 0
  let mut provedCount := 0
  let mut elaboratedCount := 0
  for l in testLines do
    if count % 100 = 0 then
      IO.println s!"{count} processed, {premiselessCount} premiseless, {provedCount} proved, {elaboratedCount} elaborated"
    let js? := Lean.Json.parse l |>.toOption
    let premise? : Option CorePremiseData := 
      js?.bind <| fun js => (fromJson? js).toOption
    match premise? with
    | some corePremise =>
      count := count + 1
      let ids := corePremise.ids.map (·.toName)
      let check := ids.all (
        fun n ↦
          (``Eq).isPrefixOf n || (``Iff).isPrefixOf n)
      if check && corePremise.lemmas.isEmpty &&
        corePremise.terms.isEmpty then
        premiselessCount := premiselessCount + 1
        IO.println s!"{corePremise.thm} has no lemmas, terms, true premises"
        IO.println s!"{corePremise.ids} are the ids"
        IO.println "launching proof search"
        let core := proofSearchCore corePremise.thm
        let (elaborated, proved) ← 
          core.run' coreContext {env := env} |>.runToIO'
        IO.println "finished proof search"
        if elaborated then
          elaboratedCount := elaboratedCount + 1
          IO.println s!"Result elaborated"
        else
          IO.println s!"Result not elaborated"
        if proved then
          provedCount := provedCount + 1
          IO.println s!"Result proved"
        else
          IO.println s!"Result not proved"
        IO.println s!"{count} processed, {premiselessCount} premiseless,
        {provedCount} proved, {elaboratedCount} elaborated"
        IO.println "-------------------"
        
    | none => pure ()
  IO.println s!"{count} processed, {premiselessCount} premiseless, {provedCount} proved, {elaboratedCount} elaborated"

  