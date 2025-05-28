import LeanAide.Codegen
import LeanAide.StructToLean
/-!
##Code generation for LeanAide "PaperStructure" schema

Need at top level generators for:

* Section
* Theorem
* Definition
* LogicalStepSequence
* Proof
* let_statement
* some_statement
* assume_statement
* assert_statement
* calculate_statement
* calculation_step
* cases_statement
* case
* induction_statement
* contradiction_statement
* conclude_statement
* Paragraph

We may need some more specific generators for:
* Figure
* Table


-/
open Lean Meta Qq Elab Term

namespace LeanAide

open Codegen Translate

@[codegen "assumption_statement"]
def assumptionCode (_ : Translator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, js => do
  let .ok assumption :=
    js.getObjValAs? String "assumption" | throwError
    s!"codegen: no assumption found in {js}"
  addPrelude assumption
  return none

@[codegen "let_statement"]
def letCode (_ : Translator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
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

@[codegen "some_statement"]
def someCode (_ : Translator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
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

open Lean.Parser.Tactic
-- Very basic version; should add references to `auto?` as well as other modifications as in `StructToLean`
@[codegen "assertion_statement"]
def assertionCode (translator : Translator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `command, js => do
  let stx ← typeStx js
  `(command| example : $stx := by sorry)
| _, `commandSeq, js => do
  let stx ← typeStx js
  `(commandSeq| example : $stx := by sorry)
| _, ``tacticSeq, js => do
  let stx ← typeStx js
  `(tacticSeq| have : $stx := bysorry)
| _, `tactic, js => do
  let stx ← typeStx js
  `(tactic| have : $stx := bysorry)
| _, _, _ => throwError
    s!"codegen: test does not work"
where typeStx (js: Json) : TranslateM Syntax.Term := do
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
    -- IO.eprintln s!"Type: {← PrettyPrinter.ppExpr type}"
    PrettyPrinter.delab type
  else
    IO.eprintln s!"Not a type: {type}"
    throwError s!"codegen: no translation found for {js}"

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
def sectionCode (translator : Translator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `commandSeq, js => do
  let .ok content := js.getArr? | throwError "section must have content"
  getCodeCommands translator none  content.toList
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

/- Remark
{
  "type": "object",
  "description": "A remark or note.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Remark",
      "description": "The type of this document element."
    },
    "remark": {
      "type": "string",
      "description": "Remark content."
    },
    "label": {
      "type": "string",
      "description": "Remark identifier."
    },
    "header": {
      "type": "string",
      "description": "Remark type.",
      "enum": [
        "Remark",
        "Example",
        "Note",
        "Observation",
        "Warning"
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
    "remark"
  ],
  "additionalProperties": false
}
-/

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
      "$ref": "#/$defs/calculate_choice",
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

/- calculate_choice
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

/- calculation_step
{
  "type": "string",
  "description": "A step, typically an equality or inequality, in a calculation or computation."
}
-/

/- cases_statement
{
  "type": "object",
  "description": "A proof by cases or proof by induction, with a list of cases.",
  "properties": {
    "type": {
      "type": "string",
      "const": "cases_statement",
      "description": "The type of this logical step."
    },
    "split_kind": {
      "type": "string",
      "description": "one of 'implication_direction' (for two sides of an 'iff' implication), 'match' (for pattern matching), 'condition' (if based on a condition being true or false) and 'groups' (for more complex cases).",
      "enum": [
        "implication_direction",
        "match",
        "condition",
        "groups"
      ]
    },
    "on": {
      "type": "string",
      "description": "The variable or expression on which the cases are being done. Write 'implication direction' for an 'iff' statement."
    },
    "proof_cases": {
      "type": "array",
      "description": "A list of elements of type `case`.",
      "items": {
        "$ref": "#/$defs/case"
      }
    },
    "exhaustiveness": {
      "$ref": "#/$defs/Proof",
      "description": "(OPTIONAL) Proof that the cases are exhaustive."
    }
  },
  "required": [
    "type",
    "split_kind",
    "on",
    "proof_cases"
  ],
  "additionalProperties": false
}
-/

/- case
{
  "type": "object",
  "description": "A case in a proof by cases or proof by induction.",
  "properties": {
    "type": {
      "type": "string",
      "const": "case",
      "description": "The type of this logical step."
    },
    "condition": {
      "type": "string",
      "description": "The case condition or pattern; for induction one of 'base' or 'induction-step'; for a side of an 'iff' statement write the claim being proved (i.e., the statement `P => Q` or `Q => P`)."
    },
    "proof": {
      "type": "array",
      "description": "Steps proving this case.",
      "items": {
        "anyOf": [
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
          },
          {
            "$ref": "#/$defs/Remark"
          }
        ]
      }
    }
  },
  "required": [
    "type",
    "condition",
    "proof"
  ],
  "additionalProperties": false
}
-/

/- induction_statement
{
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
    "proof_cases": {
      "type": "array",
      "description": "A list of elements of type `case`.",
      "items": {
        "$ref": "#/$defs/case"
      }
    }
  },
  "required": [
    "type",
    "on",
    "proof_cases"
  ],
  "additionalProperties": false
}
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
      "$ref": "#/$defs/calculate_choice",
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

/- Metadata
{
  "type": "object",
  "description": "Metadata about the document, such as authors, keywords, and classification.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Metadata",
      "description": "The type of this document element."
    },
    "authors": {
      "type": "array",
      "description": "List of authors.",
      "items": {
        "$ref": "#/$defs/Author"
      }
    },
    "keywords": {
      "type": "array",
      "description": "List of keywords describing the document.",
      "items": {
        "type": "string"
      }
    },
    "msc_codes": {
      "type": "array",
      "description": "Mathematics Subject Classification codes.",
      "items": {
        "type": "string"
      }
    },
    "publication_date": {
      "type": "string",
      "description": "Date of publication or creation (ISO 8601 format recommended).",
      "format": "date"
    },
    "source": {
      "type": "string",
      "description": "Publication source, e.g., Journal label, volume, pages, conference proceedings."
    }
  },
  "required": [
    "type",
    "authors"
  ],
  "additionalProperties": false
}
-/

/- Author
{
  "type": "object",
  "description": "An author of the document.",
  "properties": {
    "name": {
      "type": "string",
      "description": "Full name of the author."
    },
    "affiliation": {
      "type": "string",
      "description": "(OPTIONAL) Author's affiliation."
    }
  },
  "required": [
    "name"
  ],
  "additionalProperties": false
}
-/

/- Paragraph
{
  "type": "object",
  "description": "A block of plain text, potentially containing inline references.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Paragraph",
      "description": "The type of this document element."
    },
    "text": {
      "type": "string",
      "description": "The main text content of the paragraph. Inline citations (e.g., [1], [Knuth74]) and internal references (e.g., see Section 2, Theorem 3) might be embedded within this string or explicitly listed in 'citations'/'internal_references'."
    },
    "citations": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of citations mentioned in this paragraph.",
      "items": {
        "$ref": "#/$defs/Citation"
      }
    },
    "internal_references": {
      "type": "array",
      "description": "(OPTIONAL) Explicit list of internal references mentioned in this paragraph.",
      "items": {
        "$ref": "#/$defs/InternalReference"
      }
    }
  },
  "required": [
    "type",
    "text"
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

/- Bibliography
{
  "type": "object",
  "description": "The bibliography or list of references section.",
  "properties": {
    "type": {
      "type": "string",
      "const": "Bibliography",
      "description": "The type of this document element."
    },
    "header": {
      "type": "string",
      "description": "The section header (e.g., 'References', 'Bibliography')."
    },
    "entries": {
      "type": "array",
      "description": "List of bibliography entries.",
      "items": {
        "$ref": "#/$defs/BibliographyEntry"
      }
    }
  },
  "required": [
    "type",
    "header",
    "entries"
  ],
  "additionalProperties": false
}
-/

/- BibliographyEntry
{
  "type": "object",
  "description": "A single entry in the bibliography.",
  "properties": {
    "key": {
      "type": "string",
      "description": "Unique key used for citations (e.g., 'Knuth1974', '[1]')."
    },
    "formatted_entry": {
      "type": "string",
      "description": "The full bibliographic reference, formatted as text (e.g., APA, BibTeX style)."
    }
  },
  "required": [
    "key",
    "formatted_entry"
  ],
  "additionalProperties": false
}
-/

/- Citation
{
  "type": "object",
  "description": "An inline citation pointing to one or more bibliography entries.",
  "properties": {
    "cite_keys": {
      "type": "array",
      "description": "An array of bibliography keys being cited.",
      "items": {
        "type": "string"
      },
      "minItems": 1
    }
  },
  "required": [
    "cite_keys"
  ],
  "additionalProperties": false
}
-/

/- InternalReference
{
  "type": "object",
  "description": "An inline reference to another labeled part of the document (e.g., Section, Theorem, Figure).",
  "properties": {
    "target_identifier": {
      "type": "string",
      "description": "The unique 'label' of the document element being referenced (e.g., 'sec:intro', 'thm:main', 'fig:diagram')."
    }
  },
  "required": [
    "target_identifier"
  ],
  "additionalProperties": false
}
-/





-- older code, should not be used
def metaDataFields := ["author", "date", "title", "abstract", "keywords", "authors", "affiliations", "acknowledgements", "msc_codes", "publication_date", "doi", "arxiv_id", "url", "source", "header", "entries"]

@[codegen]
def metaNoCode (_ : Translator := {})(_ : Option (MVarId)) : (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, js => do
  match js.getObj? with
  | .ok obj =>
    let keys := obj.toArray.map (fun ⟨ k, _⟩  => k)
    let nonMetaKeys := keys.filter (fun k => !metaDataFields.contains k)
    if nonMetaKeys.isEmpty then
      return none
    else
      throwError s!"codegen: no metadata found in {js}, extra keys: {nonMetaKeys}"
  | .error _ => do
  throwError s!"codegen: no metadata found in {js}"



-- Copied code

open Lean.Parser.Tactic
@[codegen "thm_test"]
def thmTest (translator : Translator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `command, js => do
  let stx ← typeStx js
  `(command| example : $stx := by sorry)
| _, `commandSeq, js => do
  let stx ← typeStx js
  `(commandSeq| example : $stx := by sorry)
| _, ``tacticSeq, js => do
  let stx ← typeStx js
  `(tacticSeq| have : $stx := bysorry)
| _, `tactic, js => do
  let stx ← typeStx js
  `(tactic| have : $stx := bysorry)
| _, _, _ => throwError
    s!"codegen: test does not work"
where typeStx (js: Json) : TranslateM Syntax.Term :=
  match js.getStr? with
  | .ok str => do
    let .ok t ← translator.translateToProp? str | throwError
      s!"codegen: no translation found for {str}"
    PrettyPrinter.delab t
  | .error _ => do
    throwError
      s!"codegen: no translation found for {js}"

@[codegen]
def thmStringTest (translator : Translator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| _, `command, js => do
  let stx ← typeStx js
  `(command| example : $stx := by sorry)
| _, `commandSeq, js => do
  let stx ← typeStx js
  `(commandSeq| example : $stx := by sorry)
| _, ``tacticSeq, js => do
  let stx ← typeStx js
  `(tacticSeq| have : $stx := bysorry)
| _, `tactic, js => do
  let stx ← typeStx js
  `(tactic| have : $stx := bysorry)
| _, _, _ => throwError
    s!"codegen: test does not work"
where typeStx (js: Json) : TranslateM Syntax.Term :=
  match js.getStr? with
  | .ok str => do
    let .ok t ← translator.translateToProp? str | throwError
      s!"codegen: no translation found for {str}"
    PrettyPrinter.delab t
  | .error _ => do
    throwError
      s!"codegen: no translation found for {js}"

@[codegen "doc_test"]
def docTest  (translator : Translator := {}) : Option MVarId →  (kind: SyntaxNodeKinds) → Json → TranslateM (Option (TSyntax kind))
| goal?, `commandSeq, js => withoutModifyingState do
  let .ok statements := js.getArr? | throwError "document must be an array"
  let mut stxs : Array (TSyntax `commandSeq) := #[]
  for statement in statements do
    let stx ← getCode translator goal? `commandSeq statement
    match stx with
    | some stx => stxs := stxs.push stx
    | none => pure ()
  flattenCommands stxs
| goal?, ``tacticSeq, js => withoutModifyingState do
  let .ok statements := js.getArr? | throwError "document must be an array"
  let mut stxs : Array (TSyntax `tactic) := #[]
  for statement in statements do
    let stx ← getCode translator goal? `tactic statement
    match stx with
    | some stx => stxs := stxs.push stx
    | none => pure ()
  `(tacticSeq| $stxs*)


| _, _, _ => throwError
    s!"codegen: test does not work"

def thmJson : Json :=
  Json.mkObj [ ("thm_test" , Json.str "There are infinitely many odd numbers.") ]

def thmJson' : Json :=
  Json.mkObj [ ("thm_test" , Json.str "There are infinitely many prime numbers.") ]

def docJson : Json :=
  Json.mkObj [ ("doc_test" , Json.arr #[thmJson, thmJson', Json.str "There are infinitely many odd numbers."])]

open PrettyPrinter
def showCommand (translator: Translator)
  (source: Json) :
    TranslateM (Format) := do
    let some cmd ← getCode translator none `command source | throwError
      s!"codegen: no command"
    ppCommand cmd

def showStx  (translator: Translator)(goal? : Option (MVarId))
  (source: Json) (cat: Name) :
    TranslateM (Format) := do
    let some stx ← getCode translator  goal? cat source | throwError
      s!"codegen: no command"
    ppCategory cat stx


#eval showCommand {} thmJson -- example : {n | Odd n}.Infinite := by sorry

/-
  example : {n | Odd n}.Infinite := by sorry
  example : {p | Nat.Prime p}.Infinite := by sorry
-/
#eval showStx {} none docJson `commandSeq
