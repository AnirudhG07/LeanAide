import scala.util.matching.Regex
def wordMatch(w: String) = new Regex("(?<![a-zA-z]+)" + w + "(?![a-zA-Z]+)")
def capSegments(s: String) = {
  val pieces = "[A-Z][a-z0-9]+".r.findAllIn(s).toVector
  if (pieces.mkString("") == s) pieces else Vector(s)
}
def segmentsNoIs(s: String) = s
  .split("_")
  .toVector
  .flatMap(capSegments)
  .map(_.toLowerCase)
  .filterNot(_ == "is")

def equalSegments(s1: String, s2: String) = {
  val s1s = segmentsNoIs(s1)
  val s2s = segmentsNoIs(s2)
  s1s == s2s
}

def equalTokens(s1: String, s2: String) = {
  val s1s = s1.split("\\.").toVector
  val s2s = s2.split("\\.").toVector
  s1s.zip(s2s).forall{case (a, b) => equalSegments(a, b)}
}

def piecesSegments(s: String) = s.split("\\.").toVector.map(segmentsNoIs(_))

def segmentMap(ss: Vector[String]) = ss.map(s => piecesSegments(s) -> s).toMap 

def piecesMap(ss: Vector[String]) = ss.map(s => segmentsNoIs(s) -> s).toMap 

def lastPiecesMap(ss: Vector[String]) = ss.filter(_.contains(".")).map(s => piecesSegments(s.split("\\.").last) -> s).toMap

val binNames = os.read.lines(os.pwd / "data" / "binport_names.txt")
val allNames = os.read.lines(os.pwd/"data"/"all_names.txt")
val allNamesPieces = allNames.flatMap(_.split("\\.")).distinct
val allNamePieceSegs = piecesMap(allNamesPieces.toVector)
val binNamesPieces = binNames.flatMap(_.split("\\.")).distinct
val binSegs = segmentMap(binNames.toVector)
val nameMatch = allNames.flatMap(s1 => binSegs.get(piecesSegments(s1)).map(s2 => s1 -> s2 ))
val binPieces = binNames.flatMap(_.split("\\.")).distinct
val binPieceSegs = piecesMap(binPieces.toVector)
val namePieceMatch = allNamesPieces.flatMap(s1 => binPieceSegs.get(segmentsNoIs(s1)).map(s2 => s1 -> s2 )) 
val nameMatchAll = (nameMatch ++ namePieceMatch).distinct

import $ivy.`com.lihaoyi::upickle:1.6.0`
val reps = nameMatchAll.filter{case (a, b) => a != b}.map{case (a, b) => ujson.Obj("snakecase" -> a, "camelcase" -> b)}
val jsreps = ujson.write(reps, 2)
