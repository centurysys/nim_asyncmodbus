# nim_asyncmodbus

`nim_asyncmodbus` は Nim 向けの非同期 Modbus クライアントライブラリです。

`asyncdispatch` を使い、Modbus/RTU と Modbus/TCP をなるべく同じ API で扱えるようにしています。通常の Modbus エラーは例外ではなく、`Result[T, ModbusError]` または `ModbusError` として返します。

現時点では、計測機器からのデータ取得と single coil の制御を主目的にした小さなライブラリです。Modbus プロトコル全体を網羅することは狙っていません。

## 特徴

- 非同期 Modbus/RTU クライアント
- 非同期 Modbus/TCP クライアント
- RTU/TCP 共通の `ModbusCtx` API
- read 系 API は `Result[T, ModbusError]` を返す
- RTU frame の CRC-16 検査
- TCP frame の MBAP header 検査
- Modbus exception response の処理
- request parameter の検査
- context 単位の request 直列化
- default response timeout
- response validation / request frame builder の単体テスト

## 対応している操作

public API として主に対応しているのは以下です。

- Read coils: function code `0x01`
- Read discrete inputs: function code `0x02`
- Read holding registers: function code `0x03`
- Read input registers: function code `0x04`
- Write single coil: function code `0x05`

内部の enum や helper には他の function code も含まれていますが、public API とテストが揃っていないものは、現時点では正式対応とは見なさないでください。

## 必要環境

現在の依存関係は以下です。

- Nim `>= 2.2.4`
- `serial >= 1.2.0`
- `results >= 0.5.1`

正確な依存関係は `nim_asyncmodbus.nimble` を確認してください。

## 基本的な使い方

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

### single coil の書き込み

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

## アドレスの扱い

このライブラリは、よく使われる Modbus 風の register address を受け取り、内部では `regAddr mod 10000` で正規化します。

例:

- `1` と `40001` は address `1` として扱う
- `30001` は address `1` として扱う
- `0`, `10000`, `30000`, `40000` は `0` に正規化されるため拒否する

Modbus の wire 上の address は zero-based なので、正規化後の address `1` は wire address `0` として送信します。

## request の上限

read request では、frame を作る前に個数を検査します。

- Coils / discrete inputs: `1..2000`
- Holding / input registers: `1..125`

範囲外の場合は `meInvalidData` を返します。

## エラー処理

read 系 API は `Result[T, ModbusError]` を返します。

```nim
let res = await ctx.readRegisters(40001, 2)
if res.isErr:
  echo res.error.toString()
else:
  echo res.get()
```

`writeBit()` は `ModbusError` を直接返します。

主なエラーは以下です。

- `meInvalidFunction`
- `meInvalidAddress`
- `meInvalidData`
- `meLengthError`
- `meCrcError`
- `meTimeouted`
- `meUnknownError`

通常の Modbus protocol level の失敗は、これらの値として返します。TCP reset や serial read/write failure のような I/O エラーも、可能な範囲で `ModbusError` に変換します。

## transport の動作

### Modbus/TCP

TCP transport では以下を検査します。

- MBAP transaction id
- MBAP protocol id
- MBAP payload length
- Modbus exception response
- 期待する slave/unit id
- 期待する function code
- 期待する read byte count
- response frame の exact length
- write single coil の echo response

TCP は stream なので、1回の `recv()` で Modbus frame 全体が返るとは限りません。このライブラリでは MBAP header と payload を、それぞれ必要な長さまで読み切ります。

### Modbus/RTU

RTU transport では以下を検査します。

- CRC-16
- Modbus exception response
- 期待する slave address
- 期待する function code
- 期待する read byte count
- response frame の exact length
- write single coil の echo response

正常応答の長さが request から分かる場合は、期待する byte 数を受信した時点で RTU frame の受信を完了できます。

## 並列 request の扱い

1つの `ModbusTcp` または `ModbusRtu` context では、同時に1つの request だけを処理します。同じ context に対して複数の async task から同時に request しても、内部で直列化します。

これは意図した制約です。

- Modbus/RTU はもともと request/response 型で、半二重通信が前提
- Modbus/TCP は transaction id を使えば多重化も可能だが、このライブラリでは安全のため 1 context = 1 outstanding request とする

独立した接続が必要な場合は、context を分けてください。

## テスト

テストは以下で実行できます。

```sh
nimble test
```

現在のテストでは以下を確認しています。

- CRC-16 計算
- Modbus response validation helper
- Modbus exception response の変換
- 短い bit-read response
- read byte-count validation
- invalid request parameter
- Modbus/TCP request frame 生成
- Modbus/RTU request frame 生成と CRC

実機がなくても、frame parser / frame builder の退行を検出できるようにしています。

## 現在の制約

- client-side のみ
- public API として対応している Modbus function は少数
- multiple registers / multiple coils の write は、現時点では安定 public API として公開していない
- Modbus/TCP の request pipelining は未対応
- timeout 処理は単純な実装なので、遅い機器やノイズの多い serial line では調整が必要になる可能性がある
- `meTimeouted` は英語としては `meTimedOut` の方が自然だが、互換性のため現状の enum 名を維持している

## ライセンス

MIT
