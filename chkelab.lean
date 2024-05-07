import Lean.Meta
import LeanCodePrompts
import LeanCodePrompts.BatchTranslate
import LeanAide.Config
open Lean

set_option maxHeartbeats 10000000
set_option maxRecDepth 1000
set_option compiler.extract_closed false

def main (args: List String) : IO Unit := do
  searchPathRef.set compile_time_search_path%
  let completions := (args.getD 0 "thm")
  let env ←
    importModules #[{module := `Mathlib},
    {module:= `LeanAide.TheoremElab},

    {module:= `LeanCodePrompts.Translate},
    {module := `Mathlib}] {}
  let core :=
    outputFromCompletionsCore completions
  let io? :=
    core.run' {fileName := "", fileMap := {source:= "", positions := #[]}, maxHeartbeats := 100000000000, maxRecDepth := 1000000}
    {env := env}
  match ← io?.toIO' with
  | Except.ok js =>
    IO.println js
  | Except.error e =>
    do
      let msg ← e.toMessageData.toString
      let js := Json.mkObj [("error", Json.str msg)]
      IO.println <| js.pretty 100000
  return ()
