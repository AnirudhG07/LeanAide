import LeanCodePrompts.Premises
open Lean Meta Elab Term Syntax PrettyPrinter Parser

namespace LeanAide.Meta

class Reprint(a : Type) where
    reprSyn : a → String

instance reprintString : Reprint String where
    reprSyn := id

instance reprintName : Reprint Name where
    reprSyn := toString

instance reprintNat : Reprint Nat where
    reprSyn := toString

instance reprintBool : Reprint Bool where
    reprSyn := toString

instance reprintArray {a : Type} [Reprint a] : Reprint (Array a) where
    reprSyn := fun xs => xs.toList.map Reprint.reprSyn |>.toString

instance reprintList {a : Type} [Reprint a] : Reprint (List a) where
    reprSyn := fun xs => xs.map Reprint.reprSyn |>.toString

instance reprintOption {a : Type} [Reprint a] : Reprint (Option a) where
    reprSyn := fun xs => xs.map Reprint.reprSyn |>.getD ""

instance reprintSyntax : Reprint Syntax where
    reprSyn := fun xs => xs.reprint.get!

def reprint {a : Type}[Reprint a] (x : a) : String := Reprint.reprSyn x

instance reprintTermData : Reprint TermData where
    reprSyn := fun x => s!"context: {Reprint.reprSyn x.context}; term: {Reprint.reprSyn x.value}"

instance reprintProofData : Reprint PropProofData where
    reprSyn := fun x => s!"context: {Reprint.reprSyn x.context}; prop: {Reprint.reprSyn x.prop}; proof : {Reprint.reprSyn x.proof}"


def viewSyntax (s: String) : MetaM <| Syntax × String := do
    let c := runParserCategory (← getEnv) `term s
    match c with
    | Except.error e => throwError e
    | Except.ok s => pure (s, s.reprint.get!)


def nameDefTypeSyntax (name: Name) : MetaM <| Syntax × Syntax := do
    let info? := ((← getEnv).find? name)
    let info := info?.get!
    let exp := info.value?.get!
    let type := info.type
    let (stx, _) ←  delabCore exp {} (delabVerbose)
    let (tstx, _) ←  delabCore type {} (delabVerbose)
    return (stx, tstx)

def nameDefSyntax (name: Name) : MetaM <| Option Syntax := do
    let exp? ← nameExpr? name
    match exp? with
    | none => pure none
    | some exp => do
        let stx ←  delab exp
        pure (some stx)

def premisesFromName (name : Name) : MetaM (List PremiseData) := do
    let (pf, prop) ← nameDefTypeSyntax name
    Lean.Syntax.premiseDataM #[] pf prop true name name

def _root_.PremiseData.view : PremiseData → MetaM String := fun data => do
    return s!"context: {reprint data.context}; name?: {data.name?}; defnName: {data.defnName}; type: {reprint data.type}; type-group: {reprint data.typeGroup}; sub-terms: {reprint data.terms}; sub-proofs : {reprint data.propProofs}  identifiers: {data.ids}"


def premisesViewFromName (name: Name) : MetaM <| List String := do
    let premises ← premisesFromName name
    premises.mapM (fun p => p.view)


def premisesJsonFromName (name: Name) : MetaM <| Json := do
    let premises ← premisesFromName name
    return toJson premises


#eval premisesViewFromName ``Nat.pred_le_pred

-- #eval premisesJsonFromName ``Nat.pred_le_pred

-- #eval premisesViewFromName ``Nat.le_of_succ_le_succ


def boundedDef (bound: Nat)(name: Name) : MetaM Bool := do
    let exp? ← nameExpr? name
    match exp? with
    | none => pure false
    | some exp => do
        pure (exp.approxDepth.toNat < bound)

def nameDefView (name: Name) : MetaM String := do
    let stx? ← nameDefSyntax name
    return (stx?.get!.reprint.get!)

def nameDefCleanView (name: Name) : MetaM String := do
    let stx? ← nameDefSyntax name
    return ((stx?.get!.purge).reprint.get!)

def nameDefSyntaxVerbose (name: Name) : MetaM <| Option Syntax := do
    let exp? ← nameExpr? name
    match exp? with
    | none => pure none
    | some exp => do
        let (stx, _) ←  delabCore exp {} (delabVerbose)
        pure (some stx)

def nameDefViewVerbose (name: Name) : MetaM String := do
    let stx? ← nameDefSyntaxVerbose name
    return (stx?.get!.reprint.get!)

-- #eval nameDefSyntax ``List.join

-- #eval nameDefSyntax ``Nat.le_of_succ_le_succ



-- #eval nameDefView ``Nat.gcd_eq_zero_iff

-- #eval nameDefCleanView ``Nat.gcd_eq_zero_iff

-- def egSplit : MetaM <| Option (Syntax × Array Syntax) := do
--     let stx? ← nameDefSyntax ``Nat.gcd_eq_zero_iff
--     lambdaStx? stx?.get!

-- #eval egSplit

-- def egSplitView : MetaM <| Option (String × Array String) := do
--     let stx? ← nameDefSyntax ``Nat.gcd_eq_zero_iff
--     let pair? ← lambdaStx? stx?.get!
--     let (stx, args) := pair?.get!
--     pure (stx.reprint.get!, args.map (fun s => s.reprint.get!))

-- #eval egSplitView

-- set_option pp.proofs false in 
-- #eval nameDefView ``Nat.gcd_eq_zero_iff

-- set_option pp.proofs.withType true in 
-- #eval nameDefView ``Nat.gcd_eq_zero_iff

-- #eval nameDefViewVerbose ``Nat.gcd_eq_zero_iff

-- #eval nameDefSyntaxVerbose ``Nat.gcd_eq_zero_iff

-- #eval nameDefViewVerbose ``Nat.gcd_eq_gcd_ab

-- set_option pp.proofs false in
-- #eval nameDefView ``Nat.gcd_eq_gcd_ab

-- #eval setDelabBound 200

-- #eval nameDefViewVerbose ``Nat.xgcd_aux_P

-- set_option pp.proofs false in
-- #eval nameDefView ``Nat.xgcd_aux_P

-- theorem oddExample : ∀ (n : Nat), ∃ m, m > n ∧ m % 2 = 1 := by
--   intro n -- introduce a variable n
--   use 2 * n + 1 -- use `m = 2 * n + 1`
--   apply And.intro -- apply the constructor of `∧` to split goals
--   · linarith -- solve the first goal using `linarith` 
--   · simp [Nat.add_mod] -- solve the second goal using `simp` with the lemma `Nat.add_mod`

-- -- #eval premisesViewFromName ``oddExample

end LeanAide.Meta

open LeanAide.Meta


structure ConstsData where
    definitions : HashMap Name  Syntax
    theorems : HashMap Name  Syntax

def constsData : MetaM ConstsData := do
    let consts ← constantNameTypes
    let mut definitions := HashMap.empty
    let mut theorems := HashMap.empty
    for (c, type) in consts do
        let tstx ← delab type
        let tstx := tstx.raw.purge
        if ← Meta.isProp type then
            theorems := theorems.insert c tstx
        else
            definitions := definitions.insert c tstx
    return { definitions := definitions, theorems := theorems }

partial def Lean.Syntax.identsM (stx: Syntax)(context: Array Syntax)(maxDepth? : Option Nat := none) : MetaM <| List <| Name × Nat  := do
    if maxDepth? = some 0 then
        pure []
    else
    match ← namedArgument? stx with
    | some (arg, _) =>
        -- IO.println s!"Named: {arg}"
        let prev ←  identsM  arg context (maxDepth?.map (· -1))
        return prev.map (fun (s, m) => (s, m + 1))
    | none =>
    match ← proofWithProp? stx with
    | some (proof, _) =>
        -- IO.println s!"Proof: {proof}"
        let prev ←  identsM  proof context (maxDepth?.map (· -1))
        return prev.map (fun (s, m) => (s, m + 1))
    | none =>
    match ← lambdaStx? stx with
    | some (body, args) =>
        -- IO.println s!"Lambda: {args}"
        let prev ←  identsM  body (context ++ args) (maxDepth?.map (· -1))
        return prev.map (fun (s, m) => (s, m + args.size))
    | none =>
        match stx with
        | Syntax.node _ _ args => 
            let prev ← args.mapM (identsM · context (maxDepth?.map (· -1))) 
            return prev.toList.join.map (fun (s, m) => (s, m + 1))
        | Syntax.ident _ _ name .. => 
            let contextVars := context.filterMap getVar
            -- IO.println s!"Context: {contextVars} from {context}"
            if  !(contextVars.contains name) &&
                !(excludePrefixes.any (fun pfx => pfx.isPrefixOf name)) && !(excludeSuffixes.any (fun pfx => pfx.isSuffixOf name)) then 
                pure [(name, 0)]
            else pure []
        | _ => pure []


-- -- #eval termKindList


partial def Lean.Syntax.termsM (context : Array Syntax)(stx: Syntax)(maxDepth? : Option Nat := none) : MetaM <| List <| TermData   := do
    let tks ← termKindList
    let tks := tks.map (·.1)
    if maxDepth? = some 0 then
        pure []
    else
    match ← namedArgument? stx with
    | some (arg, _) =>
        -- IO.println s!"Named: {arg}"
        let prev ←  termsM  context arg (maxDepth?.map (· -1))
        return prev.map (fun s => s.increaseDepth 1 )
    | none =>
    match ← proofWithProp? stx with
    | some (proof, _) =>
        -- IO.println s!"Proof: {proof}"
        let prev ←  termsM context  proof (maxDepth?.map (· -1))
        return prev.map (fun s => s.increaseDepth 1)
    | none =>
    match ← lambdaStx? stx with
    | some (body, args) =>
        -- IO.println s!"Lambda: {args}"
        let prev ←  termsM (context ++ args) body (maxDepth?.map (· -1))
        return prev.map (fun s => s.increaseDepth args.size)
    | none =>
        match stx with
        | Syntax.node _ k args => 
            -- IO.println s!"Node: {k}"
            let prev ← args.mapM (termsM context · (maxDepth?.map (· -1)))
            let head : TermData := ⟨context, stx.purge, stx.purge.size, 0⟩
            if tks.contains k then 
                return (head) :: prev.toList.join.map (fun s => s.increaseDepth 1)
            else  
            return prev.toList.join.map (fun s => s.increaseDepth 1)
        | Syntax.ident .. => 
             pure []
        | _ => pure []



partial def Lean.Syntax.proofsM (context : Array Syntax)(stx: Syntax)(maxDepth? : Option Nat := none) : MetaM <| List <| PropProofData   := do
    if maxDepth? = some 0 then
        pure []
    else
    match ← namedArgument? stx with
    | some (arg, _) =>
        -- IO.println s!"Named: {arg}"
        let prev ←  proofsM  context arg (maxDepth?.map (· -1))
        return prev.map (fun s => s.increaseDepth 1)
    | none =>
    match ← proofWithProp? stx with
    | some (proof, prop) =>
        -- IO.println s!"Proof: {proof}"
        let prev ←  proofsM context  proof (maxDepth?.map (· -1))
        let head : PropProofData := 
            ⟨context, prop, proof, prop.size, proof.size, 0⟩
        return  (head) :: prev.map (fun s => s.increaseDepth 1)
    | none =>
    match ← lambdaStx? stx with
    | some (body, args) =>
        -- IO.println s!"Lambda: {args}"
        let prev ←  proofsM (context ++ args) body (maxDepth?.map (· -1))
        return prev.map (fun s => s.increaseDepth args.size)
    | none =>
        match stx with
        | Syntax.node _ _ args => 
            -- IO.println s!"Node: {k}"
            let prev ← args.mapM (proofsM context · (maxDepth?.map (· -1)))
            return prev.toList.join.map (fun s => s.increaseDepth 1)
        | Syntax.ident .. => 
             pure []
        | _ => pure []


def PremiseData.get(ctx : Array Syntax)(name: Name)(prop pf : Syntax) : MetaM PremiseData := do
    let subProofs: List (PropProofData) ←  pf.proofsM ctx
    let subTerms : List (TermData)  ← Syntax.termsM ctx pf
    let ids : List (Name  × Nat) ← pf.identsM ctx 
    return ⟨ctx, some name, name, prop.purge, prop.purge, pf.purge, prop.purge.size, pf.purge.size, subTerms.toArray, subProofs.toArray, ids.toArray⟩

def viewData (name: Name) : MetaM <| String := do
    let (stx, tstx) ← nameDefTypeSyntax name
    -- IO.println s!"{stx.reprint.get!}"
    -- IO.println s!"{← proofWithProp? stx}"
    let data ←  PremiseData.get  #[] name tstx stx 
    data.view

-- #eval viewData ``Nat.succ_le_succ

partial def Lean.Syntax.kinds (stx: Syntax)(maxDepth?: Option Nat := none) : List String :=
    if maxDepth? = some 0 then
        []
    else
    match stx with
    | Syntax.node _ k args => 
        let head? : Option String := 
            k.components.head?.map (· |>.toString)
        match head? with
        | some head => head :: (args.map (kinds · (maxDepth?.map (· -1))) |>.toList.join)
        | none => args.map (kinds · (maxDepth?.map (· -1))) |>.toList.join
    | _ => []

partial def Lean.Syntax.idents (stx: Syntax)(maxDepth? : Option Nat := none) : List <| Name × Nat  :=
    if maxDepth? = some 0 then
        []
    else
    match stx with
    | Syntax.node _ _ args => 
         args.map (idents · (maxDepth?.map (· -1))) 
            |>.toList.join.map (fun (s, m) => (s, m + 1))
    | Syntax.ident _ _ name .. => 
        if !(excludePrefixes.any (fun pfx => pfx.isPrefixOf name)) && !(excludeSuffixes.any (fun pfx => pfx.isSuffixOf name)) then 
            [(name, 0)]
        else []
    | _ => []


partial def Lean.Syntax.terms (stx: Syntax)(maxDepth?: Option Nat := none) : 
     MetaM <|  List <| String × Nat × List Name := do
    let tks ← termKindList
    let tks := tks.map (·.1)
    if maxDepth? = some 0 then
        pure []
    else
    match stx with
    | Syntax.node _ k args => 
        match stx with 
        | `(proved_prop| ($pf:term =: $_:term )) =>  
           pf.raw.terms
        | _ =>
        let head? : Option String := do 
            if 
                k ∈ tks 
            then
                ← stx.reprint
            else
                none
        let argTerms ← args.mapM (terms · (maxDepth?.map (· -1))) 
        let argTerms := argTerms.toList.join
        match head? with
        | some head =>             
            return (head.trim, 0, stx.idents.map (·.1)) ::
                 (argTerms.map (fun (s, m, l) => (s, m + 1, l)))
        | none => 
            return (argTerms.map (fun (s, m, l) => (s, m + 1, l)))
    
    | _ => pure []

structure Premises where
    type : String
    defTerms : List <| String × Nat × List Name
    defIdents : List <| Name × Nat
    typeTerms : List <| String × Nat × List Name
    typeIdents : List <| Name × Nat 
deriving Repr, Inhabited

def Premises.defMainTerms (p: Premises) : List <| String × Nat × List Name  :=
    p.defTerms.filter (
            fun (s, _) => s.1.length < 20)

def Premises.typeMainTerms (p: Premises) : List <| String × Nat × List Name :=
    p.typeTerms.filter (fun (s, _) => (s.splitOn "=>").length == 1  
                && (s.splitOn "↦").length == 1)



def getPremises (name: Name)(maxDepth? : Option Nat := none ) : MetaM <| Premises := do
    let termStx? ← nameDefSyntaxVerbose name
    let term ←  mkConstWithLevelParams name
    let type ← inferType term
    let typeView ← Meta.ppExpr type
    let typeStx ← delab type
    let defTerms ←  match termStx? with
        | none => pure []
        | some stx => stx.terms maxDepth?
    let defTerms := defTerms.filter (fun (s, _) => s.1.length < 10000
        && !s.contains '\n')
    let defIdents := match termStx? with
        | none => []
        | some stx => stx.idents maxDepth?
    pure {type := typeView.pretty 10000, defTerms := defTerms, defIdents := defIdents, typeTerms := ←  typeStx.raw |>.terms maxDepth?, typeIdents := typeStx.raw |>.idents maxDepth?}


-- Testing



def showTerms (s: String) : MetaM <| List <| String × Nat × List Name  := do
    let c := runParserCategory (← getEnv) `term s
    match c with
    | Except.error e => throwError e
    | Except.ok s => (s.terms)

def showIdents (s: String) : MetaM <| List <| Name × Nat := do
    let c := runParserCategory (← getEnv) `term s
    match c with
    | Except.error e => throwError e
    | Except.ok s => pure (s.idents)

def showKinds (s: String) : MetaM <| List String := do
    let c := runParserCategory (← getEnv) `term s
    match c with
    | Except.error e => throwError e
    | Except.ok s => pure (s.kinds)

def nameDefTerms (name: Name)(maxDepth? : Option Nat := none ) : MetaM <| 
    List <| String × Nat × List Name  := do
    let stx? ← nameDefSyntax name
    match stx? with
    | none => pure []
    | some stx => (stx.terms maxDepth?)

def nameDefIdents (name: Name)(maxDepth? : Option Nat := none ) : MetaM <| List <| Name × Nat := do
    let stx? ← nameDefSyntax name
    match stx? with
    | none => pure []
    | some stx => pure (stx.idents maxDepth?)

#check List.join

-- #eval showTerms "fun n ↦ Nat.succ n"

-- #eval showIdents "fun n ↦ Nat.succ n"

-- #eval showTerms "fun n ↦ Nat.succ n = n + 1"

#eval viewSyntax "match n + 2 with | 0 => 0 | _ => 1"

-- #eval viewSyntax "f (n := m)"

def zeroOrOne : Nat → Nat
| 0 => 0
| _ => 1

#eval nameDefSyntax ``zeroOrOne

-- #eval nameDefSyntax ``Nat.succ_le_succ

#check Lean.Parser.Term.namedArgument
#check Lean.Parser.Term.matchAlt


-- #eval showKinds "n = n + 1"

-- def egTerms : MetaM <| List <| String × Nat × List Name := do
--     let p ←  getPremises ``oddExample (some 30) 
--     return p.defMainTerms

-- #eval egTerms

-- def egIdents : MetaM <| List <| Name × Nat:= do
--     let p ←  getPremises ``oddExample (some 50) 
--     return p.defIdents

-- #eval egIdents

-- def egGpIdents : MetaM NameGroups := do
--     let nd ← egIdents
--     return groupedNames nd.toArray

-- #eval egGpIdents

-- #check Linarith.lt_irrefl

-- -- #eval nameDefSyntax ``oddExample

def dataSize : MetaM Nat := do
    let names ← constantNames
    return names.size 

-- #eval dataSize

def boundedDataSize (n: Nat) : MetaM Nat := do
    let names ← constantNames
    let names ← names.filterM (boundedDef n)
    return names.size

-- #eval boundedDataSize 50

def sampleExtract (n: Nat := 100) : MetaM <|
        List (Name × (List <| String × Nat × List Name) ×
        (List <| Name × Nat)) := do
    let names ← constantNames
    let names := names.toList.take n
    names.mapM (fun n => do 
        let p ← nameDefTerms n
        let q ← nameDefIdents n
        pure (n, p, q)
        )

def batchPremiseExtractM (start stop: Nat) : MetaM Nat  := do
    let names ← constantNames
    let premisesFile := System.mkFilePath ["rawdata",
    s!"outer-premises.jsonl"]
    let h ← IO.FS.Handle.mk premisesFile IO.FS.Mode.append Bool.false
    let names := names.toList.drop start |>.take (stop - start)
    let mut cursor := start
    IO.println s!"start: {start}, stop: {stop}"
    for name in names do
        IO.println <| s!"starting: {cursor} {name}"
        let premises ← getPremises name (some 30)
        let p := premises.defMainTerms
        let pJson := p.map 
            (fun (s, n, l) => 
                Json.mkObj [
                    ("term", s),
                    ("depth", n),
                    ("local-idents", Json.arr  (
                        l.toArray
                        |>.filter (fun name => !names.contains name)
                        |>.map (fun name : Name =>
                            name.toString)))
                ]
            )
        let q:= premises.defIdents
        let q := q.filter (fun (name, _) => names.contains name)
        let qJson := q.map 
            (fun (name, n) => 
                Json.mkObj [
                    ("name", name.toString),
                    ("depth", n)
                ]
            )
        let js := Json.mkObj [
            ("name", name.toString),
            ("type", premises.type),
            ("terms", Json.arr 
                pJson.toArray),
            ("idents", Json.arr 
                qJson.toArray)
        ]
        let out := js.pretty 10000
        if out.length < 9000 then 
            h.putStrLn <| out
        IO.println <| s!"{cursor}. {name} : {premises.type} ({p.length}, {q.length}, {out.length})"
        cursor := cursor + 1
    return cursor

def batchPremiseExtractCore (start stop: Nat) : CoreM Nat := 
    (batchPremiseExtractM start stop).run'

-- -- #eval sampleExtract

-- theorem imo_1964_q1b : ∀ (n : Nat), (2 ^ n + 1) % 7 ≠ 0
--     | 0 | 1 | 2 => by decide
--     | n + 3 => by
--       rw [pow_add, Nat.add_mod, Nat.mul_mod, show 2 ^ 3 % 7 = 1 from by rfl]
--       simp [imo_1964_q1b n]


-- set_option pp.proofs.withType true in
-- -- #eval nameDefView ``imo_1964_q1b

-- #eval nameDefView ``imo_1964_q1b

-- -- #eval nameDefViewVerbose ``imo_1964_q1b