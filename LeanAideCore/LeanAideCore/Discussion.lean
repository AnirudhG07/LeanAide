import Lean
import LeanAideCore.Aides
import LeanAideCore.ChatClient
import LeanAideCore.Prompts

/-!
Types for a discussion thread involving chatbots, humans and leanaide. Wrapper types for messages and an indexed inductive type for a discussion thread.

* The main line for the present code is
`TheoremText` → `TheoremCode` → `Document` → `StructuredDocument` → `TheoremCode`
* We may also upload a document or treat a response as a document (if the query is appropriate). But these will be *informal documents*.
-/

namespace LeanAide

open Lean Meta Elab Term

/-- A query message in a discussion thread. -/
structure Query where
  message : String
  queryParams : Json := Json.mkObj []
deriving Inhabited, Repr, ToJson, FromJson

/-- A response message in a discussion thread. -/
structure Response where
  message : String
  responseParams : Json := Json.mkObj []
deriving Inhabited, Repr, ToJson, FromJson

structure TheoremText where
  statement : String
deriving Inhabited, Repr, ToJson, FromJson

structure TheoremCode where
  text : String
  name: Name
  type : Expr
  statement : Syntax.Command
deriving Inhabited, Repr

structure DefinitionText where
  statement : String
deriving Inhabited, Repr, ToJson, FromJson

structure DefinitionCode where
  code : TSyntax ``commandSeq
deriving Inhabited, Repr

structure Document where
  content : String
deriving Inhabited, Repr, ToJson, FromJson

structure StructuredDocument where
  json: Json
deriving Inhabited, Repr, ToJson, FromJson

structure DocumentCode where
  code : TSyntax ``commandSeq
deriving Inhabited, Repr

structure Comment where
  message : String
  user : String
deriving Inhabited, Repr, ToJson, FromJson

class Content (α : Type) where
  content : α → String

instance : Content Query where
  content q := q.message

instance : Content Response where
  content r := r.message

instance : Content Document where
  content d := d.content

instance : Content Comment where
  content c := c.message

inductive ResponseType where
  | start | query | response | document | structuredDocument | code | comment | theoremText | theoremCode | definitionText | definitionCode | documentCode
deriving Repr, Inhabited

def ResponseType.toType : ResponseType → Type
| .start => Unit
| .query => Query
| .response => Response
| .document => Document
| .structuredDocument => StructuredDocument
| .code => DocumentCode
| .comment => Comment
| .theoremText => TheoremText
| .theoremCode => TheoremCode
| .definitionText => DefinitionText
| .definitionCode => DefinitionCode
| .documentCode => DocumentCode

instance (rt: ResponseType) : Repr rt.toType where
  reprPrec := by
    cases rt <;> simp [ResponseType.toType] <;> apply reprPrec

#check Repr Query

class ResponseType.OfType (α : Type)  where
  rt : ResponseType
  ofType : α → rt.toType := by exact fun x ↦ x
  eqn : rt.toType = α := by rfl

instance unitOfType : ResponseType.OfType Unit where
  rt := .start

instance queryOfType : ResponseType.OfType Query where
  rt := .query

instance responseOfType : ResponseType.OfType Response where
  rt := .response

instance documentOfType : ResponseType.OfType Document where
  rt := .document

instance structuredDocumentOfType : ResponseType.OfType StructuredDocument where
  rt := .structuredDocument

instance codeOfType : ResponseType.OfType DocumentCode where
  rt := .code

instance commentOfType : ResponseType.OfType Comment where
  rt := .comment

instance theoremTextOfType : ResponseType.OfType TheoremText where
  rt := .theoremText

instance theoremCodeOfType : ResponseType.OfType TheoremCode where
  rt := .theoremCode

instance definitionTextOfType : ResponseType.OfType DefinitionText where
  rt := .definitionText

instance definitionCodeOfType : ResponseType.OfType DefinitionCode where
  rt := .definitionCode

instance documentCodeOfType : ResponseType.OfType DocumentCode where
  rt := .documentCode



inductive Discussion : Type → Type where
  | start  (sysPrompt? : Option String)  : Discussion Unit
  | query {rt: ResponseType} (init: Discussion rt.toType) (q : Query) : Discussion Query
  | response (init: Discussion Query) (r : Response) : Discussion Response
  | digress {a b : ResponseType}  (init: Discussion a.toType) (elem : b.toType): Discussion b.toType
  | translateTheoremQuery (init : Discussion Unit) (tt : TheoremText) : Discussion TheoremText
  | theoremTranslation (init : Discussion TheoremText) (tc : TheoremCode) :Discussion TheoremCode
  | translateDefinitionQuery (init : Discussion Unit) (dt : DefinitionText) : Discussion DefinitionText
  | definitionTranslation (init : Discussion DefinitionText) (dc : DefinitionCode) : Discussion DefinitionCode
  | comment {rt : ResponseType} (init: Discussion rt.toType) (c : Comment) : Discussion Comment
  | proveTheoremQuery (init: Discussion Unit) (tt : TheoremText) : Discussion TheoremText
  | proofDocument (init: Discussion TheoremCode) (doc : Document) (prompt? : Option String := none) :  Discussion Document
  | proofStructuredDocument (init: Discussion Document) (sdoc : StructuredDocument) (prompt? : Option String := none) (schema : Option Json := none) :  Discussion StructuredDocument
  | proofCode (init: Discussion StructuredDocument) (tc : DocumentCode) : Discussion DocumentCode
  | rewrittenDocument (init: Discussion Document ) (doc : Document) (prompt? : Option String := none) :  Discussion Document
  | edit {rt : ResponseType} (userName? : Option String := none) : Discussion rt.toType  → Discussion rt.toType
deriving Repr

namespace Discussion

def last {α} : Discussion α → α
| start _  => ()
| query _ q => q
| response _ r => r
| digress _ d => d
| translateTheoremQuery _ tt => tt
| theoremTranslation _ tc => tc
| translateDefinitionQuery _ d =>  d
| definitionTranslation _ d =>  d
| comment _ d => d
| proveTheoremQuery _ tt => tt
| proofDocument _ doc _  => doc
| proofStructuredDocument _ sdoc _ _ => sdoc
| proofCode _ tc => tc
| rewrittenDocument _ doc _ => doc
| edit _ d => d.last

def lastM {α} : TermElabM (Discussion α) → TermElabM α
| d => do return (← d).last


def mkQuery {α} [inst : ResponseType.OfType α ] (prev : Discussion α) (q : Query) : Discussion Query := by
  apply Discussion.query (rt := inst.rt)  _ q
  rw [inst.eqn]
  exact prev

def initQuery (q: Query) : Discussion Query :=
  Discussion.start none |>.mkQuery q

class GeneratorM (α β : Type) where
  generateM : (Discussion α) → TermElabM (Discussion β)

def generateM {α} (β : Type) [r : GeneratorM α β] (d : Discussion α) : TermElabM (Discussion β) :=
  r.generateM d

set_option synthInstance.checkSynthOrder false in
instance composition (α γ : Type) (β : outParam Type) [r1 : GeneratorM α β] [r2 : GeneratorM β γ] : GeneratorM α γ where
  generateM d := do
    let d' ← r1.generateM d
    r2.generateM d'

def historyM {α : Type } (d : Discussion α ) :
  MetaM ((List ChatPair) × Option String) := do
  match d with
  | start sysPrompt? => return ([], sysPrompt?)
  | query init q => do
    let (h, sp?) ← init.historyM
    return addQuery h sp? q.message
  | response init r => do
    let (h, sp?) ← init.historyM
    return addResponse h sp? r.message
  | comment init c => do
    let (h, sp?) ← init.historyM
    return addQuery h sp? c.message
  | digress _ _ => return ([], none) -- reset history on digression
  | translateTheoremQuery _ _ => return ([], none)
  | theoremTranslation _ _ => return ([], none)
  | translateDefinitionQuery _ _ => return ([], none)
  | definitionTranslation _ _ => return ([], none)
  | proveTheoremQuery _ _ => return ([], none)
  | proofDocument init doc prompt? =>
    let prompt := prompt?.getD
      (← Prompts.proveForFormalization init.last.text init.last.type init.last.statement)
    return ([{user := prompt, assistant := doc.content}], none)
  | proofStructuredDocument init sdoc prompt? schema? => do
    let doc := init.last
    let prompt := prompt?.getD
      (← Prompts.jsonStructured doc.content schema?)
    return ([{user := prompt, assistant := sdoc.json.pretty}], none)
  | proofCode init _ => init.historyM
  | rewrittenDocument init _ _ => init.historyM
  | edit _ d => d.historyM
where
  addQuery (h: List ChatPair) (sp? : Option String) (q: String) : (List ChatPair) × Option String :=
    let sp? := sp?.map (fun s => s.trim ++ "\n")
    let sp := sp?.getD ""
    (h, some (sp ++ q))
  addResponse (h: List ChatPair) (sp? : Option String) (r: String) : (List ChatPair) × Option String :=
    match sp? with
    | some sp =>
      let newPair : ChatPair := {user := sp, assistant := r}
      (h ++ [newPair], none)
    | none =>
      match h.getLast? with
      | some lastPair => (h.dropLast ++ [{lastPair with assistant := lastPair.assistant ++ "\n" ++ r}], none) -- response appended to last
      | none => (h, none) -- response to nothing is discarded

-- dummies for testing
section
local instance queryResponse : GeneratorM Query Response where
  generateM d := do
    let q := d.last
    let res := { message := s!"This is a response to {q.message}", responseParams := Json.null }
    return Discussion.response d res

local instance responseComment : GeneratorM Response Comment where
  generateM d := do
    let r := d.last
    let c := { message := s!"This is a comment on {r.message}", user := "user" }
    return Discussion.comment (rt := .response) d c

-- #synth GeneratorM Query Comment

def q : Discussion Query :=
  initQuery { message := "What is 2+2?"}

-- #eval q.generateM Comment

end
end Discussion

end LeanAide
