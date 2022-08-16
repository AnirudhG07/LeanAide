import Mathbin.All
import LeanCodePrompts.Translate
import LeanCodePrompts.Autocorrect

example : //- Every prime number is either `2` or odd -/ := by
      sorry

/-!
## Codex responses

* We obtain 5 best responses from Codex.
* We post-process and choose.

## Interface

* Based on an elaborator.
* In the longer run, we would like to edit the source code (using widgets).
* Caching of results and polling for pending queries is done to reduce server calls.

## Input dependent prompting

* The prompt has examples of docstrings and translation to lean.
* The examples are from a database extracted from `mathlib` using `docgen`.
* We choose prompts based on __sentence similarity__.

## Post-processing and Lean 4

* The examples and codex output are in Lean 3.
* Some macros are used to bridge syntactic differences.
* Identifiers are mapped using a database of correspondence between `mathlib` and `binport`:
    - names were extracted from mathlib and binport (the latter as constants in the environment).
    - the nearest match was taken, with __case transformations__ and prefixing or not with __is__ and __has__ and adding `ₓ` or `ₓₓ`.

## Filtering and Selection

* We filter only valid responses.
* If there are no valid answers, we return a sorry `Prop` and also give translations in the infoview.
* We attempt to group by equality (a little more than definitional equality) and choose the largest group.
-/


example : //- Every field is a ring -/ := by 
      sorry

/-!
## Auto-correction

* We attempt to map unknown identifiers to known ones.
* For now, this is by case transformations, and adding/removing "is" and "has"
* These are the most common errors we see. The other common error is using shorter or longer forms (e.g. `adj` vs `adjacency`).
* This and the Lean 3  -> Lean 4 name mapping (here) are done in Lean.
-/

example : //- Every ring is a boojum -/ := by sorry