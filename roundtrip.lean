import Lean.Meta
import LeanCodePrompts
import LeanCodePrompts.BatchTranslate
import LeanAide.Config
import LeanAide.Descriptions
import Cli
open Lean Cli LeanAide.Meta

set_option maxHeartbeats 10000000
set_option maxRecDepth 1000
set_option compiler.extract_closed false

unsafe def runTranslate (p : Parsed) : IO UInt32 := do
  searchPathRef.set compile_time_search_path%
  let name :=
    p.positionalArg? "input" |>.map (fun s => s.as! String)
    |>.getD "Nat.add_comm"
  let numSim := p.flag? "prompts" |>.map (fun s => s.as! Nat)
    |>.getD 20
  let numConcise := p.flag? "concise_descriptions" |>.map (fun s => s.as! Nat)
    |>.getD 2
  let numDesc := p.flag? "descriptions" |>.map (fun s => s.as! Nat)
    |>.getD 2

  let queryNum := p.flag? "responses" |>.map (fun s => s.as! Nat)
    |>.getD 10
  let temp10 := p.flag? "temperature" |>.map (fun s => s.as! Nat)
    |>.getD 8
  let temp : JsonNumber := ⟨temp10, 1⟩
  let model := p.flag? "model" |>.map (fun s => s.as! String)
    |>.getD "gpt-4o"
  let azure := p.hasFlag "azure"
  let tag := p.hasFlag "tag"
  let maxTokens := p.flag? "max_tokens" |>.map (fun s => s.as! Nat)
    |>.getD 1600
  let sysLess := p.hasFlag "no_sysprompt"
  let url? := p.flag? "url" |>.map (fun s => s.as! String)
  let showPrompt := p.hasFlag "show_prompt"
  let chatServer :=
    if azure then ChatServer.azure else
        match url? with
        | some url => ChatServer.generic model url !sysLess
        | none => ChatServer.openAI model
  let chatParams : ChatParams :=
    {temp := temp, n := queryNum, maxTokens := maxTokens}
  let gitHash ← gitHash
  let dir :=
    if tag then System.mkFilePath <| ["results", model, gitHash]
    else System.mkFilePath <| ["results", model]
  if !(← dir.pathExists) then
        IO.FS.createDirAll dir
  let env ←
    importModules #[{module := `Mathlib},
    {module:= `LeanAide.TheoremElab},
    {module:= `LeanCodePrompts.Translate},
    {module:= `LeanAide.Descriptions}] {}
  withUnpickle (← picklePath "docString")
    <|fun (docStringData : Array <| (String × String × Bool × String) ×  FloatArray) => do
  withUnpickle (← picklePath "description")
    <|fun (descData : Array <| (String × String × Bool × String) ×  FloatArray) =>  do
  withUnpickle (← picklePath "concise-description")
    <|fun (concDescData : Array <| (String × String × Bool × String) ×  FloatArray) => do
  let dataMap :
    HashMap String (Array ((String × String × Bool × String) × FloatArray)) := HashMap.ofList [("docString", docStringData), ("description", descData), ("concise-description", concDescData)]
  let coreDesc := getDescriptionCore name.toName chatServer {chatParams with n := 1}
  let io? :=
    coreDesc.run' {fileName := "", fileMap := {source:= "", positions := #[]}, maxHeartbeats := 0, maxRecDepth := 1000000}
    {env := env}
  let io?' ← io?.toIO'
  match io?' with
  | .error e => do
    let msg ← e.toMessageData.toString
    IO.eprintln "Could not get description"
    IO.eprintln msg
    return 1
  | .ok none => do
    IO.eprintln "No description"
    return 1
  | Except.ok <| some (statement, desc) =>
    IO.eprintln "Got description"
    IO.eprintln statement
    IO.eprintln desc
    let coreTranslate :=
      translateViewVerboseCore desc chatServer chatParams numSim
        numConcise numDesc (dataMap := dataMap)
    let io? :=
      coreTranslate.run' {fileName := "", fileMap := {source:= "", positions := #[]}, maxHeartbeats := 0, maxRecDepth := 1000000}
      {env := env}
    let io?' ← io?.toIO'
    match io?' with
    | Except.ok (translation?, output, prompt) =>
      IO.eprintln "Ran successfully"
      if showPrompt then
        IO.eprintln "Prompt:"
        IO.eprintln prompt.pretty
        IO.eprintln "---"
      match translation? with
      | some (s, elabs, gps) =>
        if p.hasFlag "show_elaborated" then
          IO.eprintln "Elaborated terms:"
          for out in elabs do
            IO.eprintln out
          IO.eprintln "---"
          IO.eprintln "Groups:"
          for gp in gps do
            for out in gp do
              IO.eprintln out
            IO.eprintln "---"
        IO.eprintln "Translation:"
        IO.println s
        return 0
      | none =>
        IO.eprintln "No translation"
        IO.eprintln "All outputs:"
        for out in output do
          IO.eprintln <| "* " ++ out
        return 2
    | Except.error e =>
      do
        IO.eprintln "Ran with error"
        let msg ← e.toMessageData.toString
        IO.eprintln msg
        return 1

unsafe def translate : Cmd := `[Cli|
  translate VIA runTranslate;
  "Elaborate a set of inputs and report whether successful and the result if successful."

  FLAGS:
    include_fixed;         "Include the 'Lean Chat' fixed prompts."
    p, prompts : Nat;      "Number of example prompts (default 20)."
    descriptions : Nat; "Number of example descriptions (default 2)."
    concise_descriptions : Nat; "Number of example concise descriptions (default 2)."
    r, responses : Nat;    "Number of responses to ask for (default 10)."
    t, temperature : Nat;  "Scaled temperature `t*10` for temperature `t` (default 8)."
    m, model : String ; "Model to be used (default `gpt-3.5-turbo`)"
    azure; "Use Azure instead of OpenAI."
    url : String; "URL to query (for a local server)."
    show_prompt; "Output the prompt to the LLM."
    show_elaborated; "Output the elaborated terms"
    max_tokens : Nat; "Maximum tokens to use in the translation."
    no_sysprompt; "The model has no system prompt (not relevant for GPT models)."

  ARGS:
    input : String;      "The name of the theorem to translate with a roundtrip."

]

unsafe def main (args: List String) : IO UInt32 :=
  translate.validate args
