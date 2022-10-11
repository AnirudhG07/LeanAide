import Lean
import LeanCodePrompts.TexToUnicode
open Lean

def egTeX := "A formula is $\\alpha \\to \\beta := \\unknown$"

#eval teXToUnicode egTeX

def egTeX' := "A formula is $a = b$ and $c = d$, also $$X = Y$$ and $b$ = $c$ in $$1 = 2$$."

#eval translateTeX egTeX'