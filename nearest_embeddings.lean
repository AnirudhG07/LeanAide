import LeanCodePrompts.NearestEmbeddings
import LeanCodePrompts.EpsilonClusters
import LeanAide.Aides
import Lean.Data.Json
import Batteries.Util.Pickle
open Lean

unsafe def checkAndFetch (descField: String) : IO Unit := do
  let picklePath ← picklePath descField
  let picklePresent ←
    if ← picklePath.pathExists then
    IO.eprintln s!"Pickle file already present at {picklePath}"
    try
      withUnpickle  picklePath <|
        fun (_ : EmbedData) => do
        pure true
    catch e =>
        IO.eprintln s!"Error unpickling {picklePath}: {e}"
        pure false
     else pure false
  unless picklePresent do
    IO.eprintln s!"Fetching embeddings ... ({picklePath})"
    let out ← IO.Process.output {cmd:= "curl", args := #["--output", picklePath.toString,   "https://storage.googleapis.com/leanaide_data/{picklePath.fileName.get!}"]}
    IO.eprintln "Fetched embeddings"
    IO.eprintln out.stdout

unsafe def main (args: List String) : IO Unit := do
  let inp := args[0]!
  let (descField, doc, num, penalty) :=
    match Json.parse inp with
    | Except.error _ => ("docString", inp, 10, 2.0)
    | Except.ok j =>
      (j.getObjValAs? String "descField" |>.toOption.getD "docString",
        j.getObjValAs? String "docString" |>.toOption.orElse
        (fun _ => j.getObjValAs? String "doc_string" |>.toOption)
        |>.getD inp,
      j.getObjValAs? Nat "n" |>.toOption.getD 10,
      j.getObjValAs? Float "penalty" |>.toOption.getD 2.0)
  checkAndFetch descField
  logTimed s!"finding nearest to `{doc}`"
  let picklePath ← picklePath descField
  withUnpickle  picklePath <|
    fun (data : EmbedData) => do
    let embs ← nearestDocsToDocFull data doc num (penalty := penalty)
    logTimed "found nearest"
    let out :=
      Lean.Json.arr <|
        embs.toArray.map fun (doc, thm, isProp, name, d) =>
          Json.mkObj <| [
            ("docString", Json.str doc),
            ("type", Json.str thm),
            ("isProp", Json.bool isProp),
            ("name", Json.str name),
            ("distance", toJson d)
          ]
    IO.print out.compress
