import Mathbin.All
import Lean.Meta
import LeanCodePrompts.Translate
import LeanCodePrompts.CodeActions
-- import LeanCodePrompts.Autocorrect
open Lean Meta Elab Term

/- 
set_option trace.Translate.info true
example : //- Every prime number is either `2` or odd -/ := by
            sorry
example : //- There are infinitely many odd numbers -/ := by
            sorry


-/
set_option trace.Translate.info true
example : //- Every prime number is either `2` or odd -/ := by
            sorry
example : //- There are infinitely many odd numbers -/ := by
            sorry

/-! 
```
example : //- There are infinitely many odd numbers -/ := by
            sorry

#eval showLogs 2


example : //- Every field is a ring -/ := by 
            sorry

example : //- Every ring is a field -/ := by
                sorry

example : //- If a vector space has dimension `2` then it is finite dimensional. -/ := by 
        sorry
```

## Features

* Integrated interface using elaboration; caching, polling.
* Input-dependent prompting:
    - database of doc-strings from Mathlib
    - selected using: sentence similarity, keywords,(proximity)
* Post-processing:
    - Lean 3 to Lean 4 translation, auto-correction.
        - based on case-transformations, adding/dropping "is" and "has"
    - filtering by elaboration
    - selection by detected equality groups

## Possible improvements

* Interface: code actions, elaborate on removing focus
* Prompting:
    - better selection of prompts
    - better/larger database of prompts
    - use proximate prompts
* Post-processing
    - expand auto-correction
    - suggest imports
    - expand equality detection for selection
    - improve selections: round-trips
* Codex improvements:
    - hyper-parameters
    - fine-tuning
* May be able to repurpose to looking up theorem names from descriptions.
-/
