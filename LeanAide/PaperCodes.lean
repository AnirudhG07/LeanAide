import LeanAide.Codegen
import LeanAide.StructToLean
/-!
# Code generation for LeanAide "PaperStructure" schema

To Do:

* Complete the various kinds of statements.
-/
open Lean Meta Qq Elab Term

namespace LeanAide

open Codegen Translate

@[codegen "assumption_statement"]
def assumptionCode (_ : CodeGenerator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, js => do
  let .ok assumption :=
    js.getObjValAs? String "assumption" | throwError
    s!"codegen: no assumption found in {js}"
  addPrelude assumption
  return none

open Lean.Parser.Tactic

@[codegen "document"]
def documentCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `commandSeq, js => do
  let .ok content := js.getArr? | throwError "document must be a JSON array"
  getCodeCommands translator none  content.toList
| _, kind, _ => throwError
    s!"codegen: documentCode does not work for kind {kind}"

@[codegen "title","abstract", "remark", "metadata", "author", "bibliography", "citation", "internalreference"]
def noGenCode := noCode

/- Section
{
  "type": "object",
  "description": "A section of the document.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Section",
      "description": "The type of this document element."
    },
    "content": {
      "type": "array",
      "description": "The content of the section.",
      "items": {
        "anyOf": [
          {
            "$ref": "#/$defs/Section"
          },
          {
            "$ref": "#/$defs/Theorem"
          },
          {
            "$ref": "#/$defs/Definition"
          },
          {
            "$ref": "#/$defs/Remark"
          },
          {
            "$ref": "#/$defs/LogicalStepSequence"
          },
          {
            "$ref": "#/$defs/Paragraph"
          },
          {
            "$ref": "#/$defs/Proof"
          },
          {
            "$ref": "#/$defs/Figure"
          },
          {
            "$ref": "#/$defs/Table"
          }
        ]
      }
    },
    "label": {
      "type": "string",
      "description": "Section identifier."
    },
    "level": {
      "type": "integer",
      "description": "The section level such as `1` for a section, `2` for a subsection."
    },
    "header": {
      "type": "string",
      "description": "The section header."
    }
  },
  "required": [
    "type",
    "label",
    "header",
    "content"
  ],
  "additionalProperties": false
}
-/
@[codegen "section"]
def sectionCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `commandSeq, js => do
  let .ok content := js.getObjValAs? (List Json) "content" | throwError "section must have content"
  getCodeCommands translator none  content
| _, kind, _ => throwError
    s!"codegen: sectionCode does not work for kind {kind}"


/- Theorem
{
  "type": "object",
  "description": "A mathematical theorem, lemma, proposition, corollary, or claim.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Theorem",
      "description": "The type of this document element."
    },
    "hypothesis": {
      "type": "array",
      "description": "(OPTIONAL) The hypothesis or assumptions of the theorem, consisting of statements like 'let', 'assume', etc.",
      "items": {
        "anyOf": [
          {
            "$ref": "#/$defs/let_statement"
          },
          {
            "$ref": "#/$defs/assume_statement"
          },
          {
            "$ref": "#/$defs/some_statement"
          }
        ]
      }
    },
    "claim": {
      "type": "string",
      "description": "The statement."
    },
    "label": {
      "type": "string",
      "description": "Unique identifier/label for referencing (e.g., 'thm:main', 'lem:pumping')."
    },
    "proof" : {
          "$ref": "#/$defs/Proof",
          "description": "Proof of the theorems, if it is present soon after the statement."
        },
    "header": {
      "type": "string",
      "description": "The type of theorem-like environment. Must be one of the predefined values.",
      "enum": [
        "Theorem",
        "Lemma",
        "Proposition",
        "Corollary",
        "Claim"
      ]
    },
    "citations": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of citations relevant to this statement.",
      "items": {
        "$ref": "#/$defs/Citation"
      }
    },
    "internal_references": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of internal references mentioned in the statement.",
      "items": {
        "$ref": "#/$defs/InternalReference"
      }
    }
  },
  "required": [
    "type",
    "label",
    "header",
    "claim"
  ],
  "additionalProperties": false
}
-/

@[codegen "theorem"]
def theoremCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| some goal, `command, js => do
  let (stx, name, pf?) ← thmStxParts js goal
  match pf? with
  | some pf =>
    let n := mkIdent name
    `(command| theorem $n : $stx := by $pf)
  | none =>
    let n := mkIdent (name ++ `prop)
    let propIdent := mkIdent `Prop
    `(command| abbrev $n : $propIdent := $stx)
| some goal, `commandSeq, js => do
  let (stx, name, pf?) ← thmStxParts js goal
  match pf? with
  | some pf =>
    let n := mkIdent name
    `(commandSeq| theorem $n : $stx := by $pf)
  | none =>
    let n := mkIdent (name ++ `prop)
    let propIdent := mkIdent `Prop
    `(commandSeq| abbrev $n : $propIdent := $stx)

| some goal, ``tacticSeq, js => do
  let (stx, name, pf?) ← thmStxParts js goal
  match pf? with
  | some pf =>
    let n := mkIdent name
    `(tacticSeq| have $n : $stx := by $pf)
  | none =>
    let n := mkIdent (name ++ `prop)
    let propIdent := mkIdent `Prop
    `(tacticSeq| let $n : $propIdent := $stx)
| some goal, `tactic, js => do
  let (stx, name, pf?) ← thmStxParts js goal
  match pf? with
  | some pf =>
    let n := mkIdent name
    `(tactic| have $n : $stx := by $pf)
  | none =>
    let n := mkIdent (name ++ `prop)
    let propIdent := mkIdent `Prop
    `(tactic| let $n : $propIdent := $stx)
| _, _, _ => throwError
    s!"codegen: theorem does not work"
where
  thmStxParts (js: Json) (goal: MVarId) :
    TranslateM <| Syntax.Term × Name × Option (TSyntax ``tacticSeq)  := withoutModifyingState do
    match js.getObjVal?  "hypothesis" with
      | Except.ok h => contextRun translator none ``tacticSeq h
      | Except.error _ => pure ()
    let .ok  claim := js.getObjValAs? String "claim" | throwError
      s!"codegen: no claim found in {js}"
    let proof? :=
      js.getObjVal? "proof" |>.toOption
    let proofStx? ← proof?.bindM fun
      pf => getCode translator (some goal) ``tacticSeq pf
    let thm ← withPreludes claim
    let .ok type ← translator.translateToProp? thm | throwError
        s!"codegen: no translation found for {thm}"
    let type ← instantiateMVars type
    Term.synthesizeSyntheticMVarsNoPostponing
    if type.hasSorry || type.hasExprMVar then
      throwError s!"Failed to infer type {type} has sorry or mvar"
    let univ ← try
      withoutErrToSorry do
      if type.hasSorry then
        throwError "Type has sorry"
      inferType type
    catch e =>
      throwError s!"Failed to infer type {type}, error {← e.toMessageData.format}"
    if univ.isSort then
      let type ←  dropLocalContext type
      -- IO.eprintln s!"Type: {← PrettyPrinter.ppExpr type}"
      let name ← translator.server.theoremName thm
      let typeStx ← delabDetailed type
      let label := js.getObjString? "label" |>.getD name.toString
      Translate.addTheorem <| {name := name, type := type, label := label, isProved := true}
      return (typeStx, name, proofStx?)
    else
      IO.eprintln s!"Not a type: {type}"
      throwError s!"codegen: no translation found for {js}"

#check commandToTactic

/- Definition
{
  "type": "object",
  "description": "A mathematical definition.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Definition",
      "description": "The type of this document element."
    },
    "definition": {
      "type": "string",
      "description": "Definition content."
    },
    "label": {
      "type": "string",
      "description": "Definition identifier."
    },
    "header": {
      "type": "string",
      "description": "The definition type.",
      "enum": [
        "Definition",
        "Notation",
        "Terminology",
        "Convention"
      ]
    },
    "citations": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of citations relevant to this theorem statement.",
      "items": {
        "$ref": "#/$defs/Citation"
      }
    },
    "internal_references": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of internal references mentioned in the theorem statement.",
      "items": {
        "$ref": "#/$defs/InternalReference"
      }
    }
  },
  "required": [
    "type",
    "label",
    "header",
    "definition"
  ],
  "additionalProperties": false
}
-/
@[codegen "definition"]
def defCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `command, js => do
  let stx ← defCmdStx js
  `(command| $stx)
| _, `commandSeq, js => do
  let stx ← defCmdStx js
  let stxs := #[stx]
  `(commandSeq | $stxs*)
| _, ``tacticSeq, js => do
  let stx ← defCmdStx js
  let tac ← commandToTactic stx
  let tacs := #[tac]
  `(tacticSeq| $tacs*)
| _, `tactic, js => do
  let stx ← defCmdStx js
  let tac ← commandToTactic stx
  `(tactic| $tac)
| _, _, _ => throwError
    s!"codegen: theorem does not work"
where
  defCmdStx (js: Json) :
    TranslateM <| Syntax.Command :=
    withoutModifyingState do
    let .ok statement :=
      js.getObjValAs? String "definition" | throwError
        s!"codegen: no definition found in {js}"
    let .ok cmd ←
      translator.translateDefCmdM? statement | throwError
        s!"codegen: no translation found for {statement}"
    return cmd


/- LogicalStepSequence
{
  "type": "array",
  "description": "A sequence of structured logical steps, typically used within a proof or derivation, consisting of statements like 'let', 'assert', 'assume', etc.",
  "items": {
    "anyOf": [
      {
        "$ref": "#/$defs/let_statement"
      },
      {
        "$ref": "#/$defs/assert_statement"
      },
      {
        "$ref": "#/$defs/assume_statement"
      },
      {
        "$ref": "#/$defs/some_statement"
      },
      {
        "$ref": "#/$defs/cases_statement"
      },
      {
        "$ref": "#/$defs/induction_statement"
      },
      {
        "$ref": "#/$defs/calculate_statement"
      },
      {
        "$ref": "#/$defs/contradiction_statement"
      },
      {
        "$ref": "#/$defs/conclude_statement"
      }
    ]
  }
}
-/
@[codegen "section"]
def logicalStepCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `commandSeq, js => do
  let .ok content := js.getArr? | throwError "logicalStepCode must be a JSON array"
  getCodeCommands translator none  content.toList
| some goal, ``tacticSeq, js => do
  let .ok content := js.getArr? | throwError "logicalStepCode must be a JSON array"
  getCodeTactics translator goal  content.toList
| goal?, kind, _ => throwError
    s!"codegen: logicalStepCode does not work for kind {kind}where goal present: {goal?.isSome}"

/- Proof
{
  "type": "object",
  "description": "A proof environment.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Proof",
      "description": "The type of this document element."
    },
    "claim_label": {
      "type": "string",
      "description": "Theorem label being proved."
    },
    "proof_steps": {
      "type": "array",
      "description": "Steps in the proof.",
      "items": {
        "anyOf": [
          {
            "$ref": "#/$defs/Remark"
          },
          {
            "$ref": "#/$defs/LogicalStepSequence"
          },
          {
            "$ref": "#/$defs/Paragraph"
          },
          {
            "$ref": "#/$defs/Figure"
          },
          {
            "$ref": "#/$defs/Table"
          }
        ]
      }
    }
  },
  "required": [
    "type",
    "claim_label",
    "proof_steps"
  ],
  "additionalProperties": false
}
-/
@[codegen "proof"]
def proofCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `commandSeq, js => do
  let .ok content := js.getObjValAs? (List Json) "proof_steps" | throwError "missing or invalid proof_steps"
  let .ok claimLabel := js.getObjValAs? String "claim_label" | throwError
    s!"codegen: no claim_label found in {js}"
  let some labelledTheorem ← findTheorem? claimLabel | throwError
    s!"codegen: no theorem found with label {claimLabel}"
  let goalType := labelledTheorem.type

  let goalExpr ← mkFreshExprMVar goalType
  let goal := goalExpr.mvarId!
  let pfStx ← getCodeTactics translator goal content
  let n := mkIdent labelledTheorem.name
  let typeStx ← delabDetailed goalType
  `(commandSeq| theorem $n : $typeStx := by $pfStx)
| some goal, ``tacticSeq, js => do
  let .ok content := js.getObjValAs? (List Json) "proof_steps" | throwError "missing or invalid proof_steps"
  getCodeTactics translator goal  content
| goal?, kind, _ => throwError
    s!"codegen: proofCode does not (yet) work for kind {kind}where goal present: {goal?.isSome}"


/- let_statement
{
  "type": "object",
  "description": "A statement introducing a new variable with given value, type and/or property.",
  "properties": {
    "type": {
      "type": "string",
      "const": "let_statement",
      "description": "The type of this logical step."
    },
    "variable": {
      "type": "string",
      "description": "The variable being defined (use `<anonymous>` if there is no name such as in `We have a group structure on S`)"
    },
    "value": {
      "type": "string",
      "description": "(OPTIONAL) The value of the variable being defined"
    },
    "kind": {
      "type": "string",
      "description": "(OPTIONAL) The type of the variable, such as `real number`, `function from S to T`, `element of G` etc."
    },
    "properties": {
      "type": "string",
      "description": "(OPTIONAL) Specific properties of the variable beyond the type"
    }
  },
  "required": [
    "type",
    "variable"
  ],
  "additionalProperties": false
}
-/
@[codegen "let_statement"]
def letCode (_ : CodeGenerator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, js => do
  let statement :=
    match js.getObjValAs? String "statement" with
    | Except.ok s => s
    | Except.error _ =>
      let varSegment := match js.getObjString? "variable_name" with
      | some "<anonymous>" => "We have "
      | some v => s!"Let {v} be"
      | _ => "We have "
    let kindSegment := match js.getObjValAs? String "variable_type" with
      | Except.ok k => s!"a {k}"
      | Except.error _ => s!""
    let valueSegment := match js.getObjString? "value" with
      | some v => s!"{v}"
      | _ => ""
    let propertySegment := match js.getObjString? "properties" with
      | some p => s!"(such that) {p}"
      | _ => ""
    s!"{varSegment} {kindSegment} {valueSegment} {propertySegment}".trim ++ "."
  addPrelude statement
  return none


/- some_statement
{
  "type": "object",
  "description": "A statement introducing a new variable and saying that **some** value of this variable is as required (i.e., an existence statement). This is possibly with given type and/or property. This corresponds to statements like 'for some integer `n` ...' or 'There exists an integer `n` ....'",
  "properties": {
    "type": {
      "type": "string",
      "const": "some_statement",
      "description": "The type of this logical step."
    },
    "variable": {
      "type": "string",
      "description": "The variable being defined (use `<anonymous>` if there is no name such as in `We have a group structure on S`)"
    },
    "kind": {
      "type": "string",
      "description": "(OPTIONAL) The type of the variable, such as `real number`, `function from S to T`, `element of G` etc."
    },
    "properties": {
      "type": "string",
      "description": "(OPTIONAL) Specific properties of the variable beyond the type"
    }
  },
  "required": [
    "type",
    "variable"
  ],
  "additionalProperties": false
}
-/
@[codegen "some_statement"]
def someCode (_ : CodeGenerator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, js => do
  let statement :=
    match js.getObjValAs? String "statement" with
    | Except.ok s => s
    | Except.error _ =>
      let varSegment := match js.getObjString? "variable_name" with
      | some "<anonymous>" => "We have "
      | some v => s!"Let {v} be"
      | _ => "We have "
    let kindSegment := match js.getObjValAs? String "variable_kind" with
      | Except.ok k => s!"a {k}"
      | Except.error _ => s!""
    let propertySegment := match js.getObjString? "properties" with
      | some p => s!"(such that) {p}"
      | _ => ""
    s!"{varSegment} {kindSegment} {propertySegment}".trim ++ "."
  addPrelude statement
  return none


/- assume_statement
{
  "type": "object",
  "description": "A mathematical assumption being made. Use 'let_statement' or 'some_statement' if introducing variables.",
  "properties": {
    "type": {
      "type": "string",
      "const": "assume_statement",
      "description": "The type of this logical step."
    },
    "assumption": {
      "type": "string",
      "description": "The assumption text."
    },
    "label": {
      "type": "string",
      "description": "(OPTIONAL) The label of the assumption, if any."
    },
    "citations": {
      "type": "array",
      "description": "(OPTIONAL) Citations supporting or related to the assumption.",
      "items": {
        "$ref": "#/$defs/Citation"
      }
    },
    "internal_references": {
      "type": "array",
      "description": "(OPTIONAL) Internal references related to the assumption.",
      "items": {
        "$ref": "#/$defs/InternalReference"
      }
    }
  },
  "required": [
    "type",
    "assumption"
  ],
  "additionalProperties": false
}
-/
@[codegen "assume_statement"]
def assumeCode (_ : CodeGenerator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, js => do
  let .ok statement :=
      js.getObjValAs? String "assumption" | throwError ""
  addPrelude statement
  return none


/- assert_statement
{
  "type": "object",
  "description": "A mathematical statement whose proof is a straightforward consequence of given and known results following some method.",
  "properties": {
    "type": {
      "type": "string",
      "const": "assert_statement",
      "description": "The type of this logical step."
    },
    "claim": {
      "type": "string",
      "description": "The mathematical claim being asserted, NOT INCLUDING proofs, justifications or results used. The claim should be purely a logical statement which is the *consequence* obtained."
    },
    "proof_method": {
      "type": "string",
      "description": "(OPTIONAL) The method used to prove the claim. This could be a direct proof, proof by contradiction, proof by induction, etc. this should be a single phrase or a fairly simple sentence; if a longer justification is needed break the step into smaller steps. If the method is deduction from a result, use `citations`or `internal_references`."
    },
    "label": {
      "type": "string",
      "description": "The label of the statement, if any. If this statement is used in a proof or as justification for an assertion, it should be labeled so that it can be referenced later."
    },
    "citations": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of citations relevant to this theorem statement.",
      "items": {
        "$ref": "#/$defs/Citation"
      }
    },
    "results_used": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of internal references used in the proof, for example where the assertion says \"using ...\".",
      "items": {
        "$ref": "#/$defs/InternalReference"
      }
    },
    "internal_references": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of internal references mentioned in the theorem statement.",
      "items": {
        "$ref": "#/$defs/InternalReference"
      }
    },
    "calculate": {
      "$ref": "#/$defs/calculate",
      "description": "(OPTIONAL) An equation, inequality, short calculation etc."
    }
  },
  "required": [
    "type",
    "claim"
  ],
  "additionalProperties": false
}
-/
-- Very basic version; should add references to `auto?` as well as other modifications as in `StructToLean`
@[codegen "assertion_statement"]
def assertionCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `command, js => do
  let (stx, tac) ← typeStx js
  `(command| example : $stx := by $tac)
| _, `commandSeq, js => do
  let (stx, tac) ← typeStx js
  `(commandSeq| example : $stx := by $tac)
| _, ``tacticSeq, js => do
  let (stx, tac) ← typeStx js
  let hash₀ := hash stx.raw.reprint
  let name := mkIdent <| Name.mkSimple s!"assert_{hash₀}"
  let headTac ← `(tactic| have $name : $stx := by $tac)
  let resTacs ← CodeGenerator.resolveExistsHave stx
  let tacSeq := #[headTac] ++ resTacs
  `(tacticSeq| $tacSeq*)
| _, `tactic, js => do
  let (stx, tac) ← typeStx js
  `(tactic| have : $stx := by $tac)
| _, _, _ => throwError
    s!"codegen: test does not work"
where typeStx (js: Json) :
    TranslateM <| Syntax.Term × (TSyntax ``tacticSeq) := do
  let .ok  claim := js.getObjValAs? String "claim" | throwError
    s!"codegen: no claim found in {js}"
  let .ok type ← translator.translateToProp? claim | throwError
      s!"codegen: no translation found for {claim}"
  let type ← instantiateMVars type
  Term.synthesizeSyntheticMVarsNoPostponing
  if type.hasSorry || type.hasExprMVar then
    throwError s!"Failed to infer type {type} has sorry or mvar"
  let univ ← try
    withoutErrToSorry do
    if type.hasSorry then
      throwError "Type has sorry"
    inferType type
  catch e =>
    throwError s!"Failed to infer type {type}, error {← e.toMessageData.format}"
  if univ.isSort then
    let type ←  dropLocalContext type
    let resultsUsed :=
      js.getObjValAs? (Array Json) "results_used" |>.toOption |>.getD #[]
    let statementsUsed :=
      resultsUsed.filterMap fun
        res =>
          res.getObjValAs? String "statement" |>.toOption
    let names' ← statementsUsed.mapM fun s =>
                  Translator.matchingTheoremsAI   (s := s) (qp:= translator)
    let names' := names'.toList.flatten
    let targets :=
      resultsUsed.filterMap fun
        res =>
          res.getObjValAs? String "target_identifier" |>.toOption
    let labelledTheorems ←
      targets.filterMapM fun target =>
        findTheorem? target
    let usedNames := labelledTheorems.map (·.name)
    let ids := (usedNames ++ names').map mkIdent
    let tac ← `(tacticSeq| auto? [ $ids,* ])
    return (← delabDetailed type, tac)
  else
    IO.eprintln s!"Not a type: {type}"
    throwError s!"codegen: no translation found for {js}"

/- calculation
{
  "type": "object",
  "description": "An equation, inequality, short calculation etc.",
  "minProperties": 1,
  "maxProperties": 1,
  "properties": {
    "inline_calculation": {
      "type": "string",
      "description": "A simple calculation or computation written as a single line."
    },
    "calculation_sequence": {
      "type": "array",
      "description": "A list of elements of type `calculation_step`.",
      "items": {
        "$ref": "#/$defs/calculation_step"
      }
    }
  }
}
-/

/-     "pattern_cases_statement": {
      "type": "object",
      "description": "A proof by cases, with cases determined by matching a pattern.",
      "properties": {
        "type": {
          "type": "string",
          "const": "pattern_cases_statement",
          "description": "The type of this logical step."
        },
        "on": {
          "type": "string",
          "description": "The variable or expression which is being matched against patterns."
        },
        "proof_cases": {
          "type": "array",
          "description": "A list of elements of type `case`.",
          "items": {
            "$ref": "#/$defs/pattern_case"
          }
        },
      "required": [
        "type",
        "on",
        "proof_cases"
      ],
      "additionalProperties": false
    },
-/
open Lean.Parser.Term CodeGenerator Parser
@[codegen "pattern_cases_statement"]
def patternCasesCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| some goal, ``tacticSeq, js => do
  let .ok discr := js.getObjValAs? String "on" | throwError
    s!"codegen: no on found in {js}"
  let .ok patternCases := js.getObjValAs? (Array Json) "proof_cases" | throwError
    s!"codegen: no proof_cases found in {js}"
  let pats := patternCases.filterMap fun
    case =>
      case.getObjValAs? String "pattern" |>.toOption
  let proofData := patternCases.filterMap fun
    case =>
      case.getObjValAs? Json "proof" |>.toOption
  let mut alts : Array <| TSyntax ``matchAltTac := #[]
  let mut patTerms : Array Syntax.Term := #[]
  for pat in pats do
    let patTerm :=
      runParserCategory (← getEnv) `term pat |>.toOption.getD (← `(_))
    let patTerm' : Syntax.Term := ⟨patTerm⟩
    patTerms := patTerms.push patTerm'
    let m ← `(matchAltTac| | $patTerm' => _)
    alts := alts.push m
  let alts' : Array <| TSyntax ``matchAlt := alts.map fun alt => ⟨alt⟩
  let discrTerm :=
    runParserCategory (← getEnv) `term discr |>.toOption.getD (← `(_))
  let discrTerm' : Syntax.Term := ⟨discrTerm⟩
  let hash := hash discrTerm.reprint
  let c := mkIdent <| ("c" ++ s!"_{hash}").toName
  let tac ← `(tactic| match $c:ident : $discrTerm':term with $alts':matchAlt*)
  let newGoals ←
    runAndGetMVars goal #[tac] proofData.size
  let proofStxs ← proofData.zip newGoals.toArray |>.mapM fun (proof, newGoal) => do
    let some proofStx ← getCode translator (some newGoal) ``tacticSeq proof |
      throwError s!"codegen: no translation found for {proof}"
    return proofStx
  let mut provedAlts : Array <| TSyntax ``matchAltTac := #[]
  for (patTerm, pf) in patTerms.zip proofStxs do
    let m ← `(matchAltTac| | $patTerm => $pf)
    alts := alts.push m
  let alts' : Array <| TSyntax ``matchAlt := provedAlts.map fun alt => ⟨alt⟩
  let c := mkIdent <| ("c" ++ s!"_{hash}").toName
  `(tacticSeq| match $c:ident : $discrTerm':term with $alts':matchAlt*)

| goal?, kind ,_ => throwError
    s!"codegen: biequivalenceCode does not work for kind {kind} with goal present: {goal?.isSome}"


/- bi-implication_cases_statement
    "bi-implication_cases_statement": {
      "type": "object",
      "description": "Proof of a statement `P ↔ Q`.",
      "properties": {
        "type": {
          "type": "string",
          "const": "bi-implication_cases_statement",
          "description": "The type of this logical step."
        },
        "if_proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof that `P` implies `Q`."
        },
        "only_if_proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof that `Q` implies `P`."
        },
      "required": [
        "type",
        "antecedent",
        "consequent",
        "if_proof",
        "only_if_proof"
      ],
      "additionalProperties": false
    }
  },
-/
@[codegen "bi-implication_cases_statement"]
def biequivalenceCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| some goal, ``tacticSeq, js => do
  let .ok ifProof := js.getObjValAs? Json "if_proof" | throwError
    s!"codegen: no if_proof found in {js}"
  let .ok onlyIfProof := js.getObjValAs? Json "only_if_proof" | throwError
    s!"codegen: no only_if_proof found in {js}"
  let tac ← `(tactic|constructor)
  let [ifGoal, onlyIfGoal] ←
    runAndGetMVars goal #[tac] 2 | throwError "codegen: biequivalenceCode failed to get two goals"
  let some ifProofStx ← getCode translator (some ifGoal) ``tacticSeq ifProof | throwError
    s!"codegen: no translation found for if_proof {ifProof}"
  let some onlyIfProofStx ← getCode translator (some onlyIfGoal) ``tacticSeq onlyIfProof | throwError
    s!"codegen: no translation found for only_if_proof {onlyIfProof}"
  let tacs := #[tac, ← `(tactic| · $ifProofStx), ← `(tactic| · $onlyIfProofStx)]
  `(tacticSeq| $tacs*)
| goal?, kind ,_ => throwError
    s!"codegen: biequivalenceCode does not work for kind {kind} with goal present: {goal?.isSome}"

/- condition_cases_statement
    "condition_cases_statement": {
      "type": "object",
      "description": "Proof of a statement based on splitting into cases where a condition is true and false, i.e., an if-then-else proof.",
      "properties": {
        "type": {
          "type": "string",
          "const": "condition_cases_statement",
          "description": "The type of this logical step."
        },
        "condition": {
          "type": "string",
          "description": "The condition based on which the proof is split."
        },
        "true_case_proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof of the case where the condition is true."
        },
        "false_case_proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof of the case where the condition is false."
        },
      "required": [
        "type",
        "condition",
        "true_case_proof",
        "false_case_proof"
      ],
      "additionalProperties": false
    }
  },
-/
@[codegen "condition_cases_statement"]
def conditionCasesCode (translator : CodeGenerator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| some goal, ``tacticSeq, js => do
  let .ok condition := js.getObjValAs? String "condition" | throwError
    s!"codegen: no condition found in {js}"
  let .ok conditionType ← translator.translateToProp? condition | throwError
      s!"codegen: no translation found for {condition}"
  let conditionType ← instantiateMVars conditionType
  Term.synthesizeSyntheticMVarsNoPostponing
  if conditionType.hasSorry || conditionType.hasExprMVar then
    throwError s!"Failed to infer type {conditionType} has sorry or mvar"
  let univ ← try
    withoutErrToSorry do
    if conditionType.hasSorry then
      throwError "Type has sorry"
    inferType conditionType
  catch e =>
    throwError s!"Failed to infer type {conditionType}, error {← e.toMessageData.format}"
  let conditionType ←
    if univ.isSort then
      dropLocalContext conditionType
    else
      IO.eprintln s!"Not a type: {conditionType}"
      throwError s!"codegen: no translation found for {js}"
  let conditionStx ← delabDetailed conditionType
  let tac ← `(tactic|if $conditionStx then _ else _)
  let [thenGoal, elseGoal] ←
    runAndGetMVars goal #[tac] 2 | throwError "codegen: biequivalenceCode failed to get two goals"
  let .ok trueCaseProof := js.getObjValAs? Json "true_case_proof" | throwError
    s!"codegen: no true_case_proof found in {js}"
  let .ok falseCaseProof := js.getObjValAs? Json "false_case_proof" | throwError
    s!"codegen: no false_case_proof found in {js}"
  let some trueCaseProofStx ← getCode translator (some thenGoal) ``tacticSeq trueCaseProof | throwError
    s!"codegen: no translation found for true_case_proof {trueCaseProof}"
  let some falseCaseProofStx ← getCode translator (some elseGoal) ``tacticSeq falseCaseProof | throwError
    s!"codegen: no translation found for false_case_proof {falseCaseProof}"
  let tacs := #[← `(tactic| if $conditionStx then $trueCaseProofStx else $falseCaseProofStx)]
  `(tacticSeq| $tacs*)
| goal?, kind ,_ => throwError
    s!"codegen: biequivalenceCode does not work for kind {kind} with goal present: {goal?.isSome}"

/-
    "multi-condition_cases_statement": {
      "type": "object",
      "description": "A proof by cases given by three or more conditions.",
      "properties": {
        "type": {
          "type": "string",
          "const": "multi-condtion_cases_statement",
          "description": "The type of this logical step."
        },
        "proof_cases": {
          "type": "array",
          "description": "The conditions and proofs in the different cases.",
          "items": {
            "$ref": "#/$defs/condtion_case"
          }
        },
        "exhaustiveness": {
          "$ref": "#/$defs/Proof",
          "description": "(OPTIONAL) Proof that the cases are exhaustive."
        }
      },
      "required": [
        "type",
        "proof_cases"
      ],
      "additionalProperties": false
    },
-/
/- pattern_case

  "pattern_case": {
      "type": "object",
      "description": "A case in a proof by cases with cases determined by matching patterns.",
      "properties": {
        "type": {
          "type": "string",
          "const": "pattern_case",
          "description": "The type of this logical step."
        },
        "pattern": {
          "type": "string",
          "description": "The pattern determining this case."
        },
        "proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof of this case."

        }
      },
      "required": [
        "type",
        "pattern",
        "proof"
      ],
      "additionalProperties": false
    },
-/
/- condition_case
    "condition_case": {
      "type": "object",
      "description": "A case in a proof by cases with cases determined by conditions.",
      "properties": {
        "type": {
          "type": "string",
          "const": "condition_case",
          "description": "The type of this logical step."
        },
        "condition": {
          "type": "string",
          "description": "The pattern determining this case."
        },
        "proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof of this case."

        }
      },
      "required": [
        "type",
        "condition",
        "proof"
      ],
      "additionalProperties": false
    },

-/

example (n: Nat) : n = n := by
  if c:n < 2 then _ else _
  · simp
  · simp

example (n: Nat) : n = n := by
  cases n with
  | zero => _
  | succ n => _
  · simp
  · simp

example (n: Nat) : n = n := by
  match n with
  | 0 => _
  | 1 => _
  | 2 => _
  | n+ 1 => _
  · simp
  · simp
  · simp
  · simp

/- induction_statement
    "induction_statement": {
      "type": "object",
      "description": "A proof by induction, with a base case and an induction step.",
      "properties": {
        "type": {
          "type": "string",
          "const": "induction_statement",
          "description": "The type of this logical step."
        },
        "on": {
          "type": "string",
          "description": "The variable or expression on which induction is being done."
        },
        "base_case_proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof of the base case."
        },
        "induction_step_proof": {
          "$ref": "#/$defs/Proof",
          "description": "Proof of the induction step, which typically shows that if the statement holds for `n`, it holds for `n+1`."
        }},
      "required": [
        "type",
        "on",
        "base_case_proof",
        "induction_step_proof"
      ],
      "additionalProperties": false
    },
-/

/- contradiction_statement
{
  "type": "object",
  "description": "A proof by contradiction, with an assumption and a proof of the contradiction.",
  "properties": {
    "type": {
      "type": "string",
      "const": "contradiction_statement",
      "description": "The type of this logical step."
    },
    "assumption": {
      "type": "string",
      "description": "The assumption being made to be contradicted."
    },
    "proof": {
      "$ref": "#/$defs/Proof",
      "description": "The proof of the contradiction given the assumption."
    }
  },
  "required": [
    "type",
    "assumption",
    "proof"
  ],
  "additionalProperties": false
}
-/

/- calculate_statement
{
  "type": "object",
  "properties": {
    "type": {
      "type": "string",
      "const": "calculate_statement",
      "description": "The type of this logical step."
    },
    "calculation": {
      "$ref": "#/$defs/calculate",
      "description": "An equation, inequality, short calculation etc."
    }
  },
  "required": [
    "type",
    "calculation"
  ],
  "additionalProperties": false
}
-/

/- conclude_statement
{
  "type": "object",
  "description": "Conclude a claim obtained from the steps so far. This is typically the final statement of a proof giving the conclusion of the theorem.",
  "properties": {
    "type": {
      "type": "string",
      "const": "conclude_statement",
      "description": "The type of this logical step."
    },
    "claim": {
      "type": "string",
      "description": "The conclusion of the proof."
    }
  },
  "required": [
    "type",
    "claim"
  ],
  "additionalProperties": false
}
-/


/- Figure
{
  "type": "object",
  "description": "A figure or image.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Figure",
      "description": "The type of this document element."
    },
    "label": {
      "type": "string",
      "description": "Unique identifier/label for referencing (e.g., 'fig:flowchart')."
    },
    "source": {
      "type": "string",
      "description": "URL or path to the image file."
    },
    "caption": {
      "type": "string",
      "description": "(OPTIONAL) Caption describing the figure."
    },
    "alt_text": {
      "type": "string",
      "description": "(OPTIONAL) Alternative text for accessibility."
    }
  },
  "required": [
    "type",
    "label",
    "source"
  ],
  "additionalProperties": false
}
-/

/- Table
{
  "type": "object",
  "description": "A data table.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Table",
      "description": "The type of this document element."
    },
    "label": {
      "type": "string",
      "description": "Unique identifier/label for referencing (e.g., 'tab:results')."
    },
    "caption": {
      "type": "string",
      "description": "(OPTIONAL) Caption describing the table."
    },
    "content": {
      "type": "array",
      "description": "Table data, represented as an array of rows, where each row is an array of cell strings.",
      "items": {
        "type": "array",
        "items": {
          "type": "string"
        }
      }
    },
    "header_row": {
      "type": "boolean",
      "description": "(OPTIONAL) Indicates if the first row in 'content' is a header row. Default: false",
      "default": false
    }
  },
  "required": [
    "type",
    "label",
    "content"
  ],
  "additionalProperties": false
}
-/
