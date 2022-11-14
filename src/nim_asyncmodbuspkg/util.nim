import std/sequtils
import std/strformat
import std/strutils
import ./private/ptrmath

func bswap16*(val: uint16): uint16 =
  result = ((val and 0xff00) shr 8) or ((val and 0xff) shl 8)

func hbyte(val: uint16): uint8 =
  result = ((val and 0xff00) shr 8).uint8

func lbyte(val: uint16): uint8 =
  result = (val and 0xff).uint8

func get_be16(p: ptr uint8): uint16 =
  result = (p[0].uint16 shl 8) or p[1].uint16

func get_le16(p: ptr uint8): uint16 =
  result = (p[1].uint16 shl 8) or p[0].uint16

proc set_be16(p: ptr uint8, val: uint16) =
  p[] = val.hbyte
  (p + 1)[] = val.lbyte

proc set_le16(p: ptr uint8, val: uint16) =
  p[] = val.lbyte
  (p + 1)[] = val.hbyte

func get_be16*(s: openArray[uint8|char], pos: uint): uint16 =
  if pos < s.len.uint:
    result = get_be16(cast[ptr uint8](unsafeAddr s[pos]))

func get_le16*(s: openArray[uint8|char], pos: uint): uint16 =
  if pos < s.len.uint:
    result = get_le16(cast[ptr uint8](unsafeAddr s[pos]))

proc set_be16*(s: openArray[uint8|char], pos: uint, val: uint16) =
  if pos < s.len.uint:
    set_be16((unsafeAddr s[pos]), val)

proc set_le16*(s: openArray[uint8|char], pos: uint, val: uint16) =
  if pos < s.len.uint:
    set_le16((unsafeAddr s[pos]), val)

proc toString*(buf: openArray[uint8|char]): string =
  result = buf.mapIt(it.char).join

proc `$`*(buf: openArray[uint8|char]): string =
  let buf_s = buf.mapIt(&"0x{it.uint8:02x}")
  result = "[" & buf_s.join(", ") & "]"

proc `$`*(buf: seq[uint8|char]): string =
  let buf_s = buf.mapIt(&"0x{it.uint8:02x}")
  result = "[" & buf_s.join(", ") & "]"


when isMainModule:
  var buf = newSeq[uint8](4)
  buf.set_be16(0, 0x1234)
  buf.set_be16(2, 0x5678)
  echo buf.mapIt(&"{it:02x}")
  let val_1 = buf.get_be16(1)
  echo &"0x{val_1:04x}"
  let val_over = buf.get_be16(16)
  echo &"0x{val_over:04x}"
  let payload = buf.toString()
  let hexstr = payload.mapIt(&"{it.int:02x}").join(", ")
  echo &"payload.len: {payload.len}, \"{payload}\", [{hexstr}]"
