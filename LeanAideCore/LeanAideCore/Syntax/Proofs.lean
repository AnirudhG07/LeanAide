import Lean
import LeanAideCore.Kernel
import LeanAideCore.Discussion
import LeanAideCore.KernelGenerators
import LeanAideCore.Syntax.Basic

open Lean Meta Elab Term PrettyPrinter Tactic Command Parser

namespace LeanAide

macro doc:docComment "#document" ppSpace n:ident : command =>
  let text := doc.raw.reprint.get!
  let text := text.drop 4 |>.dropRight 4
  let textStx := Syntax.mkStrLit text
  let name := n.getId ++ "doc".toName
  let nameStx := mkIdent name
  `(command| def $nameStx : Document := { name := $(quote n.getId), content := $(textStx) } )

instance documentCommand : DefinitionCommand Document where
  cmd d  := do
    let nameStx := Lean.mkIdent d.name
    let docs := mkNode ``Lean.Parser.Command.docComment #[mkAtom "/--", mkAtom ( d.content ++ " -/")]

    `(command| $docs:docComment #document $nameStx)

#consider ({name := `hello, content := "world" }: Document)

#check Name.components

instance structuredDocumentCommand : DefinitionCommand StructuredDocument where
  cmd s := do
    let nameStx := Lean.mkIdent (s.name ++ "struct_doc".toName)
    let jsStx ← getJsonSyntax s.json
    let typeId := Lean.mkIdent ``StructuredDocument
    `(command| def $nameStx : $typeId := ⟨ $(quote s.name),  json% $jsStx ⟩  )

#consider ({name := `hello, json := json% {a : {b : 1}} }: StructuredDocument)

macro doc:docComment "#conjecture" ppSpace n:ident ppSpace ":" ppSpace t:term : command => do
  let name := n.getId ++ "conj".toName
  let nameStx := mkIdent name
  `(command| $doc:docComment def $nameStx : Prop := $t )

/--
Just a test
-/
#conjecture easy : 2 + 2 = 4

#check easy.conj

instance : DefinitionCommand TheoremCode where
  cmd c := do
    let nameStx := Lean.mkIdent (c.name ++ "conj".toName)
    let docs := mkNode ``Lean.Parser.Command.docComment #[mkAtom "/--", mkAtom ( c.text ++ " -/")]
    let typeStx ← delab c.type
    `(command| $docs:docComment #conjecture $nameStx : $typeStx)

instance : DefinitionCommand DefinitionCode where
  cmd d := return d.statement

instance : DefinitionCommand TheoremText where
  cmd t := do
    mkQuoteCmd t.text t.name?

instance : ReplaceCommand DocumentCode where
  replace stx dc := do
    let codeText ← printCommands dc.code
    let text := s!"section {dc.name}\n\n{codeText}\n\nend {dc.name}"
    TryThis.addSuggestion stx text

syntax (name:= proofGenCmd) "#prove" ppSpace term (">>" ppSpace term)? : command

@[command_elab proofGenCmd] def elabProofGenCmd : CommandElab
  | stx@`(command| #prove $t:term >> $out:term) =>
    Command.liftTermElabM do
    let type ← elabType out
    let init ← Term.elabTerm t none
    let result ← mkAppM ``generateM #[type, init]
    let SideEffect' ← mkAppM ``TermElabM #[mkConst ``Unit]
    let SideEffect ← mkArrow (mkConst ``Syntax) SideEffect'
    let resultEffectExpr ← mkAppM ``replaceCommandM #[result]
    let resultEffect ← unsafe evalExpr (Syntax → (TermElabM Unit)) SideEffect resultEffectExpr
    resultEffect stx
  | `(command| #prove $_:term ) =>
    return
  | _ => throwUnsupportedSyntax

end LeanAide
