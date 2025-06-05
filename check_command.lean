import Mathlib
import Lean
import LeanAide.SimpleFrontend

open Lean LeanAide

unsafe def main (args : List String) : IO Unit := do
  initSearchPath (← findSysroot)
  withImportModules  #[{module := `Mathlib}] {} 1 fun env => do
    let text := "example : ∀ (G : Type) [Group G], ∀ a b : G, a * b = b * a := by sorry"
    let text := args[0]? |>.getD text
    let (_, logs) ← simpleRunFrontend text env
    IO.eprintln "Ran dummy example to load Mathlib"
    for log in logs.toList do
      IO.eprintln s!"{←  log.toString}"
