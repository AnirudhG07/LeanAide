import Lean
open Lean Meta

def initFiles : List System.FilePath := [".lake/build/lib", ".lake/packages/mathlib/.lake/build/lib",  ".lake/packages/Qq/.lake/build/lib", ".lake/packages/aesop/.lake/build/lib", ".lake/packages/proofwidgets/.lake/build/lib", ".lake/packages/importGraph/.lake/build/lib", ".lake/packages/batteries/.lake/build/lib", ".lake/packages/plausible/.lake/build/lib", ".lake/packages/batteries/.lake/CLi/lib", ".lake/packages/LeanSearchClient/.lake/build/lib" ]

initialize
  registerTraceClass `Translate.info
  registerTraceClass `Translate.debug
  registerTraceClass `Translate.warning
  registerTraceClass `leanaide.proof.info
  registerTraceClass `leanaide.codegen.info

register_option leanaide.logging : Bool :=
  { defValue := false
    descr := "Enable LeanAide logging"
    group := "LeanAide" }

initialize delab_bound : IO.Ref UInt32 ← IO.mkRef 50

def leanAideLogging? : CoreM (Option String) := do
  let loggingEnabled : Bool := leanaide.logging.get (← getOptions)
  if loggingEnabled then return some "1"
  else IO.getEnv "LEANAIDE_LOGGING"

def leanAideLoggingIO? : IO (Option String) := do
  IO.getEnv "LEANAIDE_LOGGING"

def logHandle : IO IO.FS.Handle := do
  let logPath : System.FilePath :=
    ".lake/build/lib/leanaide.log"
  IO.FS.Handle.mk logPath IO.FS.Mode.append

def logTimed (message: String) : IO Unit := do
  match (← leanAideLoggingIO?) with
  | some "0" =>
    return ()
  | some _   => let handle ← logHandle
                let time ← IO.monoMsNow
                let message := s!"[{time}]  {message}"
                IO.FS.Handle.putStrLn handle message
                IO.FS.Handle.flush handle
  | _ =>
    return ()

def baseDir : IO System.FilePath := do
  let pathLeanAidePackages := System.mkFilePath [".lake","packages","leanaide"]
  let leanAide := System.mkFilePath ["LeanAide"]
  let resources := System.mkFilePath ["resources"]
  if (← (((← IO.currentDir).join leanAide).pathExists)) &&
  (← (((← IO.currentDir).join resources).pathExists)) then
    return (← IO.currentDir)
  else if (← ((pathLeanAidePackages.join leanAide).pathExists)) && (← ((pathLeanAidePackages.join resources).pathExists)) then
    return pathLeanAidePackages
  else
    throw (IO.userError "LeanAide not found.")

def resourcesDir : IO System.FilePath := do
  let base ← baseDir
  return base / "resources"

-- #eval resourcesDir
