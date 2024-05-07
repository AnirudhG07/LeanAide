import LeanCodePrompts.NearestEmbeddings
import LeanCodePrompts.EpsilonClusters
import Cache.IO
import LeanAide.Aides
import Lean.Data.Json
import Std.Util.Pickle
open Lean Cache.IO

unsafe def checkAndFetch (descField: String) : IO Unit := do
  let picklePath ← picklePath descField
  let picklePresent ←
    if ← picklePath.pathExists then
    try
      withUnpickle  picklePath <|
        fun (_ : Array <| (String × String × Bool × String) ×  FloatArray) => do
        pure true
    catch _ => pure false
     else pure false
  unless picklePresent do
    IO.eprintln "Fetching embeddings ..."
    let out ← runCurl #["--output", picklePath.toString, "-s",  "https://math.iisc.ac.in/~gadgil/data/{picklePath.fileName.get!}"]
    IO.eprintln "Fetched embeddings"
    IO.eprintln out

unsafe def main (args: List String) : IO Unit := do
  for descField in ["docString", "description", "concise-description"] do
    checkAndFetch descField
  let inp := args.get! 0
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
  logTimed s!"finding nearest to `{doc}`"
  let picklePath ← picklePath descField
  withUnpickle  picklePath <|
    fun (data : Array <| (String × String × Bool × String) ×  FloatArray) => do
    let embs ← nearestDocsToDocFull data doc num (penalty := penalty)
    logTimed "found nearest"
    let out :=
      Lean.Json.arr <|
        embs.toArray.map fun (doc, thm, isProp, name, d) =>
          Json.mkObj <| [
            ("docString", Json.str doc),
            ("theorem", Json.str thm),
            ("isProp", Json.bool isProp),
            ("name", Json.str name),
            ("distance", toJson d)
          ]
    IO.print out.compress
