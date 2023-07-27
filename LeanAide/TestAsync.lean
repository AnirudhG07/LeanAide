import LeanAide.RunAsync
import Aesop
import Mathlib.Tactic
import Std.Tactic.TryThis

opaque sillyN : Nat

axiom silly : sillyN = 2

example : sillyN ≤ 3 := by#
  sorry

example : 3 ≤ 4 := by#
  sorry

example : sillyN ≤ 4 := by#
  rw [silly]
  sorry
  
example : 2 ≤ 2 := by#
  sorry

example : 2 ≤ 2 := by
  aided_by aesop? do
  sorry

example : 2 ≤ 2 := by#
   skip
   sorry

macro "by!" tacs:tacticSeq : term =>
  `(by 
  aided_by from_by apply? do $tacs)

macro "by!"  : term =>
  `(by 
  aided_by from_by apply? do)


example : 2 ≤ 3 := by apply?  

set_option aided_by.delay 200

example : 2 ≤ 4 := by!
  sorry


def prop := 2 ≤ 3

example : prop := by
  rw [prop]
  exact Nat.AtLeastTwo.prop

example : 1 = 1 := by!
  sorry


example : sillyN ≤ 4 := by#
  rw [silly]
  sorry

example : 1 = 1 := by#
  skip
  sorry
  
example : 1 = 1 := by
  simp?

def sum : ℕ → ℕ
| 0 => 0
| n + 1 => n + 1 + sum n

set_option aided_by.delay 600

theorem sum_formula (n: ℕ) :  sum n = (n * (n + 1) : ℚ) / 2  := by 
  induction n with
  | zero => rfl
  | succ n ih => 
    aided_by linarith do
    simp [sum]
    sorry


  


  

  


  


  


  

  


  


  


  
