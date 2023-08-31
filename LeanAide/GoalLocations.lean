import Lean.Meta.ExprLens
import Mathlib.Tactic
import Std

open Lean Meta Expr 

-- TODO Check whether this function already exists
def Lean.Expr.getName! : Expr → Name
  | .lam n _ _ _ => n
  | .letE n _ _ _ _ => n
  | .forallE n _ _ _ => n
  | _               => panic! "Unable to get name for expression."

partial def Lean.Expr.getConvEnters (expr : Expr) (explicit? : Bool) : MetaM (Array (List String × Expr)) :=
  match expr with
  | .app _ _ => do
    let fn := expr.getAppFn 
    let args := expr.getAppArgs
    let fnInfo ← getFunInfo fn
    let argsWithBinderInfo := Array.zip args (fnInfo.paramInfo.map (·.isExplicit))
    let args' :=
      argsWithBinderInfo.filterMap <| fun (arg, bi) ↦
        if explicit? || (!explicit? && bi) then
          some arg
        else none
    let enterArgs ← args'.mapIdxM fun idx arg ↦ do
      let argConvEnters ← arg.getConvEnters explicit?
      let enterArg := (if explicit? then "@" else "") ++ s!"{idx.val + 1}"
      return argConvEnters.map <| fun (path, subexpr) ↦
        (enterArg :: path, subexpr)
    (enterArgs.push #[([], expr)]).concatMapM pure  
  | .forallE _ _ _ _ => do
    let binders := expr.getForallBinderNames |>.map (·.getRoot.toString)
    let body := expr.getForallBody
    let bodyConvEnters ← body.getConvEnters explicit?
    return (bodyConvEnters.map  fun (path, subexpr) ↦ 
              (binders ++ path, subexpr)) |>.push ([], expr)  
  | .lam _ _ _ _ 
  | .letE _ _ _ _ _ =>
    lambdaLetTelescope expr <| fun args body ↦ do
      let binders := args |>.map (·.getName!.toString) |>.toList
      let bodyConvEnters ← body.getConvEnters explicit?
      return (bodyConvEnters.map  fun (path, subexpr) ↦
                (binders ++ path, subexpr)) |>.push ([], expr)
  | .mdata _ expr => getConvEnters expr explicit?
  | .proj _ _ struct => do
    let structConvEnters ← struct.getConvEnters explicit?
    return (structConvEnters.map fun (path, subexpr) ↦
                  ("1" :: path, subexpr)) |>.push ([], expr)
  | _ => return #[([], expr)]

open Meta Elab Term in
#eval show TermElabM _ from do
  let stx ← `(term| ∀ x, Nat.succ x = 1) 
  let t ← Term.elabTerm stx none
  let enters ← t.getConvEnters (explicit? := false)
  for (path, expr) in enters do
    IO.println path
    let stx ← PrettyPrinter.delab expr
    IO.println stx.raw.reprint.get!