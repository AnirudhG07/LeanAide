import Lean
import Mathlib.Tactic.Simps.Basic

open Lean Elab Parser Term Meta Tactic Meta

def inputFile : System.FilePath := 
"LeanCodePrompts"/"TacticExtractionTest.lean"

#eval inputFile.pathExists

-- Leonardo de Moura's code for generating trace data
def getTactics : TSyntax ``tacticSeq → TSyntaxArray `tactic
  | `(tacticSeq| { $[$t]* }) => t
  | `(tacticSeq| $[$t]*) => t
  | _ => #[]

#check rwRuleSeq

partial def resolveTactic : TSyntax `tactic → TacticM (TSyntaxArray `tactic)
  | `(tactic| · $[$t]* ) => t.concatMapM resolveTactic
  | `(tactic| { $[$t]* } ) => t.concatMapM resolveTactic
  | `(tactic| ( $[$t]* ) ) => t.concatMapM resolveTactic
  | `(tactic| focus $[$t]* ) => t.concatMapM resolveTactic
  | `(tactic| $t) => pure #[t]

section Source
  -- modified from `Lean.Elab.Tactic.Simp`
  def traceSimpCall' (stx : Syntax) (usedSimps : Simp.UsedSimps) : MetaM Syntax := do
    let mut stx := stx
    if stx[3].isNone then
      stx := stx.setArg 3 (mkNullNode #[mkAtom "only"])
    let mut args := #[]
    let mut localsOrStar := some #[]
    let lctx ← getLCtx
    let env ← getEnv
    for (thm, _) in usedSimps.toArray.qsort (·.2 < ·.2) do
      match thm with
      | .decl declName => -- global definitions in the environment
        if env.contains declName && !simpOnlyBuiltins.contains declName then
          args := args.push (← `(Parser.Tactic.simpLemma| $(mkIdent (← unresolveNameGlobal declName)):ident))
      | .fvar fvarId => -- local hypotheses in the context
        if let some ldecl := lctx.find? fvarId then
          localsOrStar := localsOrStar.bind fun locals =>
            if !ldecl.userName.isInaccessibleUserName &&
                (lctx.findFromUserName? ldecl.userName).get!.fvarId == ldecl.fvarId then
              some (locals.push ldecl.userName)
            else
              none
        -- Note: the `if let` can fail for `simp (config := {contextual := true})` when
        -- rewriting with a variable that was introduced in a scope. In that case we just ignore.
      | .stx _ thmStx => -- simp theorems provided in the local invocation
        args := args.push ⟨thmStx⟩ 
      | .other _ => -- Ignore "special" simp lemmas such as constructed by `simp_all`.
        pure ()     -- We can't display them anyway.
    if let some locals := localsOrStar then
      args := args ++ (← locals.mapM fun id => `(Parser.Tactic.simpLemma| $(mkIdent id):ident))
    else
      args := args.push ⟨(← `(Parser.Tactic.simpStar| *))⟩ 
    let argsStx := if args.isEmpty then #[] else #[mkAtom "[", (mkAtom ",").mkSep args, mkAtom "]"]
    stx := stx.setArg 4 (mkNullNode argsStx)
    return stx

  def dsimpLocation' (ctx : Simp.Context) (loc : Location) : TacticM Syntax := do
    match loc with
    | Location.targets hyps simplifyTarget =>
      withMainContext do
        let fvarIds ← getFVarIds hyps
        go fvarIds simplifyTarget
    | Location.wildcard =>
      withMainContext do
        go (← (← getMainGoal).getNondepPropHyps) (simplifyTarget := true)
  where
    go (fvarIdsToSimp : Array FVarId) (simplifyTarget : Bool) : TacticM Syntax := do
      let mvarId ← getMainGoal
      let (result?, usedSimps) ← dsimpGoal mvarId ctx (simplifyTarget := simplifyTarget) (fvarIdsToSimp := fvarIdsToSimp)
      match result? with
      | none => replaceMainGoal []
      | some mvarId => replaceMainGoal [mvarId]
      traceSimpCall' (← getRef) usedSimps

end Source

def traceGoalsAt (stx : TSyntax `tactic) : TacticM Unit := do
  let gs ← getUnsolvedGoals
  withRef stx <| addRawTrace (goalsToMessageData gs)

def traceTacticCallAt (stx : TSyntax `tactic) (tac : TSyntax `tactic) : TacticM Unit := do
  withRef stx <| addRawTrace m!"[TACTIC] {tac}"

def evalTacticWithTrace : TSyntax `tactic → TacticM Unit
  | stx@`(tactic| simp%$tk $(config)? $(discharger)? $[only%$o]? $[[$args,*]]? $(loc)?) => do
    traceGoalsAt stx
    let { ctx, dischargeWrapper } ← withMainContext <| mkSimpContext stx (eraseLocal := false)
    let usedSimps ← dischargeWrapper.with fun discharge? =>
      simpLocation ctx discharge? (expandOptLocation stx.raw[5])
    traceTacticCallAt stx ⟨← traceSimpCall' stx usedSimps⟩
    traceGoalsAt stx
  | stx@`(tactic| simp_all%$tk $(config)? $(discharger)? $[only%$o]? $[[$args,*]]?) => do
    traceGoalsAt stx
    let { ctx, .. } ← mkSimpContext stx (eraseLocal := true) (kind := .simpAll) (ignoreStarArg := true)
    let (result?, usedSimps) ← simpAll (← getMainGoal) ctx
    match result? with
    | none => replaceMainGoal []
    | some mvarId => replaceMainGoal [mvarId]
    traceTacticCallAt stx ⟨← traceSimpCall' stx usedSimps⟩
    traceGoalsAt stx
  | stx@`(tactic| dsimp%$tk $(config)? $[only%$o]? $[[$args,*]]? $(loc)?) => do
    traceGoalsAt stx
    let { ctx, .. } ← withMainContext <| mkSimpContext stx (eraseLocal := false) (kind := .dsimp)
    traceTacticCallAt stx ⟨← dsimpLocation' ctx (expandOptLocation stx.raw[5])⟩
    traceGoalsAt stx
  | `(tactic| rw $[$cfg]? [$rs,*] $[$loc]?) => do
    for r in (rs : TSyntaxArray `Lean.Parser.Tactic.rwRule) do
      traceGoalsAt ⟨r.raw⟩
      let rtac ← `(tactic| rw $[$cfg]? [$r] $[$loc]?) 
      evalTactic rtac
      traceTacticCallAt ⟨r.raw⟩ rtac
      traceGoalsAt ⟨r.raw⟩ 
  | stx@`(tactic| have $[$x:ident]? := $prf) => do
    traceGoalsAt stx
    evalTactic stx
    let trm ← Tactic.elabTerm prf none
    let typ ← inferType trm
    let typStx ← PrettyPrinter.delab typ
    `(tactic| have $[$x:ident]? : $typStx := $prf) >>= traceTacticCallAt stx
    traceGoalsAt stx
  | stx@`(tactic| let $x:ident := $val) => do
    traceGoalsAt stx
    evalTactic stx
    let trm ← Tactic.elabTerm val none
    let typ ← inferType trm
    let typStx ← PrettyPrinter.delab typ
    `(tactic| let $x:ident : $typStx := $val) >>= traceTacticCallAt stx 
    traceGoalsAt stx 
  | stx@`(tactic| $tac) => do
    traceGoalsAt stx
    evalTactic tac
    traceTacticCallAt stx tac
    traceGoalsAt stx

elab "seq" s:tacticSeq : tactic => do
  -- dbg_trace s.raw.getArgs
  let tacs ← (getTactics s).concatMapM resolveTactic -- .raw.recFilter (fun stx => stx.isOfKind `tactic)
  -- dbg_trace tacs
  for tac in tacs do
    evalTacticWithTrace tac

-- an example of the `seq` tactic
example (h : x = y) : 0 + x = y ∧ 1 = 1 := by
  seq 
    rw [Nat.zero_add, (h : x = y)]
  refine' ⟨_, _⟩
  focus
    rw [←h, h]
  · rfl

-- a deep copy of Lean's `by` tactic, called `by'`
syntax (name := byTactic') "by' " tacticSeq : term

@[term_elab byTactic'] def elabByTactic' : TermElab := fun stx expectedType? => do
  match expectedType? with
  | some expectedType =>
    let mvar ← mkFreshExprMVar expectedType MetavarKind.syntheticOpaque
    let mvarId := mvar.mvarId!
    let ref ← getRef
    registerSyntheticMVar ref mvarId <| SyntheticMVarKind.tactic stx (← saveContext)
    return mvar
  | none =>
    tryPostpone
    throwError ("invalid 'by\'' tactic, expected type has not been provided")

example : 1 + 1 = 2 := by' -- the new `by'` syntax can be used to replace `by`
  focus
  rfl

-- intercepting the `by` tactic to output intermediate trace data
-- the `by'` clone is needed here to avoid infinite recursion
macro_rules
  | `(by $ts) => `(by' seq $ts) 

set_option linter.unreachableTactic false

-- the `by` tactic now generates trace data by default
example (h : x = y) : x + 0 + x = x + y ∧ 1 = 1 := by
  have := (rfl : 1 = 1)
  let a := 5
  simp at this
  refine' ⟨_, _⟩
  · apply Eq.symm
    apply Eq.symm
    rw [h, ← h]
    simp_all
  · apply Eq.symm
    apply Eq.symm
    subst h
    rfl
  done

example : ∀ n : Nat, n = n := by
  intro n
  let x : ∀ m : ℕ, m = m := by
    intro a
    rfl
  match n with
  | .zero => rfl
  | .succ _ => rfl