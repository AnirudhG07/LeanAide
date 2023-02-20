theorem Nat.add_assoc' : ∀ a b c : Nat, a + b + c = a + (b + c) := by
  intro a
  intro b
  intro c
  apply Eq.symm
  apply Eq.symm
  rw [Nat.add_assoc]

theorem Nat.eq_self : ∀ n : Nat, n = n := by
  intro n
  cases n
  · rfl
  · rfl