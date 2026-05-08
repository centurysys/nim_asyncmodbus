import std/options
import unittest

import nim_asyncmodbuspkg/core

proc bytes(vals: varargs[int]): string =
  result = newStringOfCap(vals.len)
  for v in vals:
    result.add(char(v and 0xff))

suite "Modbus response validation":
  test "maps TCP exception responses":
    let exc = checkExceptionResponse(bytes(0x01, 0x83, 0x02))
    check exc.isSome
    check exc.get() == meInvalidAddress

  test "rejects malformed TCP exception length":
    let exc = checkExceptionResponse(bytes(0x01, 0x83))
    check exc.isSome
    check exc.get() == meLengthError

  test "accepts short TCP bit read response":
    let frame = bytes(0x01, 0x01, 0x01, 0x15)
    check checkReadResponse(frame, 0x01, fcReadCoilStatus, 8) == meSuccess

  test "validates expected bit byte count":
    let frame = bytes(0x01, 0x01, 0x02, 0x15, 0x00)
    check checkReadResponse(frame, 0x01, fcReadCoilStatus, 8) == meLengthError

  test "validates expected register byte count":
    let frame = bytes(0x02, 0x03, 0x04, 0x00, 0x0a, 0x00, 0x14)
    check checkReadResponse(frame, 0x02, fcReadHoldingRegister, 2) == meSuccess

  test "rejects mismatched slave address":
    let frame = bytes(0x02, 0x03, 0x02, 0x00, 0x0a)
    check checkReadResponse(frame, 0x01, fcReadHoldingRegister, 1) == meUnknownError

  test "rejects mismatched function code":
    let frame = bytes(0x01, 0x04, 0x02, 0x00, 0x0a)
    check checkReadResponse(frame, 0x01, fcReadHoldingRegister, 1) == meUnknownError

  test "rejects trailing data in read response":
    let frame = bytes(0x01, 0x03, 0x02, 0x00, 0x0a, 0x00)
    check checkReadResponse(frame, 0x01, fcReadHoldingRegister, 1) == meLengthError

  test "validates read count limits":
    check checkReadCount(fcReadCoilStatus, 0) == meInvalidData
    check checkReadCount(fcReadCoilStatus, MaxReadBits) == meSuccess
    check checkReadCount(fcReadCoilStatus, MaxReadBits + 1) == meInvalidData
    check checkReadCount(fcReadHoldingRegister, MaxReadRegisters) == meSuccess
    check checkReadCount(fcReadHoldingRegister, MaxReadRegisters + 1) == meInvalidData

  test "rejects zero normalized addresses":
    check checkRegAddr(0) == meInvalidAddress
    check checkRegAddr(10000) == meInvalidAddress
    check checkRegAddr(40001) == meSuccess
