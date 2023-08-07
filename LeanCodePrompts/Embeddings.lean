import Lean
import Lean.Meta
import Lean.Parser
import LeanAide.Aides
import LeanAide.IP
import Mathlib

open Std Lean

def readEmbeddings : IO <| Std.HashMap String FloatArray :=  do
  let mut count := 0
  let blob ← IO.FS.readFile "rawdata/mathlib4-thms-embeddings.json"
  let json := Json.parse blob |>.toOption.get!
  let jsonArr := json.getArr? |>.toOption.get!
  let mut accum := Std.HashMap.empty
  for jsLine in jsonArr do
    let doc := 
      match jsLine.getObjValAs? String "docString" with
      | Except.ok doc => doc
      | Except.error err => panic! s!"error reading docString: {err}" 
    let embedding':= 
      match jsLine.getObjValAs? (List Float) "embedding" with
      | Except.ok embedding => embedding
      | Except.error err => panic! s!"error reading embedding: {err}" 
    let embedding := embedding'.toFloatArray
    accum := accum.insert doc embedding
    count := count + 1
    if count % 1000 == 0 then    
      IO.println s!"read {count} embeddings"
  return accum

def readEmbeddingsArray : IO <| Array <| String ×  FloatArray :=  do
  let mut count := 0
  let blob ← IO.FS.readFile "rawdata/mathlib4-thms-embeddings.json"
  let json := Json.parse blob |>.toOption.get!
  let jsonArr := json.getArr? |>.toOption.get!
  let mut accum := #[]
  let mut docs : Array String := #[]
  for jsLine in jsonArr do
    let doc := 
      match jsLine.getObjValAs? String "docString" with
      | Except.ok doc => doc
      | Except.error err => panic! s!"error reading docString: {err}" 
    let embedding':= 
      match jsLine.getObjValAs? (List Float) "embedding" with
      | Except.ok embedding => embedding
      | Except.error err => panic! s!"error reading embedding: {err}" 
    let embedding := embedding'.toFloatArray
    unless docs.contains doc do
      docs := docs.push doc
      accum := accum.push (doc, embedding)
    count := count + 1
    if count % 1000 == 0 then    
      IO.println s!"read {count} embeddings"
  return accum

unsafe def loadEmbeddings : IO Nat := 
  withUnpickle  "rawdata/mathlib4-thms-embeddings.json.olean" <| fun (data: Array <| String ×  FloatArray) => pure data.size

-- #eval loadEmbeddings

-- #check readEmbeddings
-- #eval embeddingSize