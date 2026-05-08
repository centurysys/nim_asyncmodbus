# nim_asyncmodbus

`nim_asyncmodbus` is an asynchronous Modbus client library for Nim.

It provides a small common API for Modbus/RTU and Modbus/TCP clients using
`asyncdispatch`, with `Result`-based error handling instead of exceptions for
normal Modbus failures.

The project is currently focused on simple client-side data acquisition and
single-coil control. It is intentionally small and does not try to implement the
entire Modbus protocol surface.

## Features

- Asynchronous Modbus/RTU client
- Asynchronous Modbus/TCP client
- Common `ModbusCtx` API for RTU and TCP
- `Result[T, ModbusError]` return values for read operations
- CRC-16 validation for RTU frames
- MBAP header validation for TCP frames
- Modbus exception response handling
- Request parameter validation
- Per-context request serialization
- Default response timeouts
- Unit tests for response validation and request frame builders

## Supported operations

The public API currently covers:

- Read coils: function code `0x01`
- Read discrete inputs: function code `0x02`
- Read holding registers: function code `0x03`
- Read input registers: function code `0x04`
- Write single coil: function code `0x05`

Other Modbus function codes may appear in internal enums or helper code, but they
should not be treated as fully supported unless a public API and tests exist for
them.

## Requirements

The package currently requires:

- Nim `>= 2.2.4`
- `serial >= 1.2.0`
- `results >= 0.5.1`

See `nim_asyncmodbus.nimble` for the authoritative dependency list.

## Basic usage

### Modbus/TCP

```nim
import std/asyncdispatch
import nim_asyncmodbus

proc main() {.async.} =
  let ctx = newModbusTcp("192.168.1.10", 502)

  let coils = await ctx.readBits(target = 1'u8, regAddr = 1'u16, nb = 8'u16)
  if coils.isErr:
    echo "read coils failed: ", coils.error.toString()
    return

  echo coils.get()

waitFor main()
```

### Modbus/RTU

```nim
import std/asyncdispatch
import serial
import nim_asyncmodbus

proc main() {.async.} =
  let ctx = newModbusRtu("/dev/ttyUSB0", baud = 19200, parity = Parity.None)
  discard ctx.setSlave(1)
  discard ctx.connect()

  let regs = await ctx.readInputRegisters(regAddr = 30001'u16, nb = 4'u16)
  if regs.isErr:
    echo "read input registers failed: ", regs.error.toString()
    return

  echo regs.get()

waitFor main()
```

### Write a single coil

```nim
import std/asyncdispatch
import nim_asyncmodbus

proc main() {.async.} =
  let ctx = newModbusTcp("192.168.1.10", 502)

  let err = await ctx.writeBit(target = 1'u8, regAddr = 1'u16, onoff = true)
  if err != meSuccess:
    echo "write failed: ", err.toString()
    return

  echo "write succeeded"

waitFor main()
```

## Address handling

The library accepts common Modbus-style register addresses and normalizes them by
using `regAddr mod 10000` internally.

Examples:

- `1` and `40001` normalize to address `1`
- `30001` normalizes to address `1`
- `0`, `10000`, `30000`, and `40000` normalize to `0` and are rejected

The wire-level Modbus address is zero-based, so normalized address `1` is sent as
wire address `0`.

## Request limits

The library validates read quantities before building request frames:

- Coils / discrete inputs: `1..2000`
- Holding / input registers: `1..125`

Invalid quantities return `meInvalidData`.

## Error handling

Read APIs return `Result[T, ModbusError]`.

```nim
let res = await ctx.readRegisters(40001, 2)
if res.isErr:
  echo res.error.toString()
else:
  echo res.get()
```

`writeBit()` returns `ModbusError` directly.

Common errors include:

- `meInvalidFunction`
- `meInvalidAddress`
- `meInvalidData`
- `meLengthError`
- `meCrcError`
- `meTimeouted`
- `meUnknownError`

Normal protocol-level failures should be reported through these error values.
I/O errors such as TCP reset or serial read/write failure are also converted to
`ModbusError` where possible.

## Transport behavior

### Modbus/TCP

The TCP transport validates:

- MBAP transaction id
- MBAP protocol id
- MBAP payload length
- Modbus exception responses
- Expected slave/unit id
- Expected function code
- Expected read byte count
- Exact response frame length
- Write single coil echo response

The transport reads TCP frames with exact-length reads. This avoids assuming that
a single TCP `recv()` returns a complete Modbus frame.

### Modbus/RTU

The RTU transport validates:

- CRC-16
- Modbus exception responses
- Expected slave address
- Expected function code
- Expected read byte count
- Exact response frame length
- Write single coil echo response

For requests whose normal response length is known, the RTU reader can stop once
the expected number of bytes has been received.

## Concurrency model

A single `ModbusTcp` or `ModbusRtu` context allows only one outstanding request at
a time. Requests issued concurrently through the same context are serialized
internally.

This is intentional:

- Modbus/RTU is naturally request/response and half-duplex.
- Modbus/TCP could theoretically pipeline requests by transaction id, but this
  library currently keeps one outstanding request per context for simplicity and
  safety.

Create separate contexts if independent connections are required.

## Tests

Run the test suite with:

```sh
nimble test
```

Current tests cover:

- CRC-16 calculation
- Modbus response validation helpers
- Modbus exception response mapping
- Short bit-read responses
- Read byte-count validation
- Invalid request parameters
- Modbus/TCP request frame generation
- Modbus/RTU request frame generation and CRC

These tests are designed to catch frame parser and frame builder regressions
without requiring real Modbus devices.

## Current limitations

- The library is client-side only.
- Only a small set of Modbus functions has public API coverage.
- Multi-register writes and multi-coil writes are not currently exposed as stable
  public APIs.
- Modbus/TCP request pipelining is not supported.
- Timeout behavior is intentionally simple and may need tuning for slow devices
  or noisy serial lines.
- `meTimeouted` is kept as the current enum name for compatibility, even though
  `meTimedOut` would be more idiomatic English.

## License

MIT
