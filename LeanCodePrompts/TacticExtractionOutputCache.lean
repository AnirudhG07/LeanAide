import Lean

open Lean Elab Parser Term Meta Tactic

structure TacticSnapshot where
  depth : Nat
  goalsBefore : String
  tactic : TSyntax `tactic
  goalsAfter : String
  ref : Option Syntax
deriving Inhabited

initialize tacticSnapRef : IO.Ref (Array TacticSnapshot) ← IO.mkRef #[] 

def tacticSnapRef.push (snap : TacticSnapshot) : IO Unit := do
  let snaps ← tacticSnapRef.get
  tacticSnapRef.set <| snaps.push snap