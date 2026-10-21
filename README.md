# Moon TraceLens

Offline log investigation, implemented in MoonBit with a JSON CLI and reusable library API.

- Repository: [https://github.com/btlqql/moon-tracelens](https://github.com/btlqql/moon-tracelens)
- Package: `btlqql/moon_tracelens@0.4.1`
- License: Apache-2.0
- Release scope: **0.4.0 byte ingestion and committed recovery kernel**; see [recovery contract and limits](docs/recovery.md).

## Implemented

JSONL and five-column pipe log ingestion; multiline stack continuations; epoch/RFC3339 timestamps; severity normalisation; source/line diagnostics; filters; request/service grouping; sorted timelines; error fractions and nearest-rank duration p95. scripts/files.mjs reads real selected log files.

## Build and run

Use MoonBit and Node.js 24. The core library supports JS, wasm, wasm-gc and native; the filesystem/HTTP/process CLI is JS only.

```sh
moon update
moon build --target js
moon run cmd/main --target js -- examples/scenario-1.json
node _build/js/debug/build/cmd/main/main.js examples/scenario-1.json
```

Pass `-` to read a UTF-8 JSON request from stdin. A single request must be at most 16 MiB. Successful requests print one JSON result; invalid requests exit nonzero. The host runner is a separate process and does not edit the input request file.

## Library use

```sh
moon add btlqql/moon_tracelens@0.4.1
```

In the consumer's `moon.pkg`:

```moonbit
import {
  "btlqql/moon_tracelens" @engine,
  "moonbitlang/core/json",
}
```

```moonbit
fn example(request : Json) -> Json raise {
  @engine.execute(request)
}
```

`execute(Json) -> Json raise` is the standard JSON boundary. `from_json`, `Value::to_json`, and `run(Value) -> Value raise` provide a typed semantic value interface. Object ordering is not significant; numeric values use finite Double. Public domain functions are listed in `pkg.generated.mbti`.

## Tests

```sh
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native  # requires a C compiler
moon build --target js
node scripts/check.mjs
python -B scripts/reference.py
```

There are 16 checked fixture cases in `tests/cases.json`, executed both in MoonBit white-box tests and through the actual Node CLI. Independent reference checks use Python's standard library or separately written algorithms. Fixtures are synthetic and are not presented as production adoption evidence. See [input and output examples](docs/usage.md) and [current boundaries](docs/boundaries.md).

## Current boundaries

Offline batch analysis. Uppercase T/Z RFC3339, years 0001–9999, no leap seconds. Timestamps are seconds and duration_ms is milliseconds. Sources that fail event normalisation produce diagnostics; orphan pipe continuations are quarantined as diagnostics. A bounded journal host supports polling, explicit rename rotation, truncate diagnostics and crash recovery; see docs/recovery.md for exact guarantees. No distributed tracing exporter.

See [source and dependency attribution](THIRD_PARTY.md). This release does not establish competition eligibility or organizer acceptance.


## Version 0.2.0 revision

Baseline/current comparison with aligned groups, metric deltas and preserved ingestion diagnostics. Orphan multiline continuations are quarantined, including after bad records or across separately supplied sources.

旧版的离线分析能力保留；0.4.0 增加有界字节采集、轮转与恢复内核，详细边界见 docs/recovery.md。没有分布式采集器或完整 OpenTelemetry 导出。RFC3339 采用大写 T/Z，不接受闰秒。比较不提供因果推断、统计显著性和自动发布结论；指标均由有效且经过筛选的事件计算，须结合诊断阅读。

Run the additional complete scenario:

```sh
moon run cmd/main --target js -- examples/scenario-4.json
```


## 2026-10-18 follow-up

新增 buckets 操作，按 width_seconds 和 origin 划分左闭右开的时间桶；负时间与小数边界同样按 floor 定义处理。每桶复用事件数、错误数、错误比例和延迟 p95，保留摄入诊断，空桶省略。先应用现有过滤，再生成桶；输出事件总数可以与桶计数之和对照。

不填补空时间桶、不进行观察时长归一化，不把桶统计解释为因果关系或统计显著性。离线内存分析不包含实时 tail 和轮转恢复。

Repository release: 0.3.0; installable MoonCakes module: `btlqql/moon_tracelens@0.4.1`. Earlier repository 1.0.0 labels are retained as history; the module uses the registry-compatible zero-major sequence.

The 0.3.0 snapshot contained 18 MoonBit test declarations and 16 CLI fixtures (generated fixture tests included). The current 0.4.1 core has 27 tests; host checks are counted separately below. Run `python -B scripts/followup_reference.py` for the earlier analytical oracles and `examples/followup-20261018.json` for that scenario.

## Version 0.4.0

New MoonBit recovery subpackage: byte offsets and pending UTF-8/CRLF framing, bounded quarantine with raw bytes, explicit generation transitions, immutable SHA-256 journal batches, deterministic committed replay and host commit plans. Node JournalSource reads real files and preserves old descriptors across rename. Node Journal performs ordered file/directory synchronization on Linux and reports weaker process-crash-only durability on Windows. [Architecture, API, tests and exact limits](docs/recovery.md).

```sh
node scripts/journal-test.mjs
```

## Review 2026-10-21 / 0.4.1

Before writing a new batch the host verifies that the resulting committed chain fits its recovery JSON envelope. `new Journal(directory, {maxEnvelopeBytes})` accepts 1024..16000000 bytes, default16000000. Reader restarts validate explicitly supplied source/format/line limit; sealed or stale readers fail. Temporary manifests use random names. Replay rejects unknown top-level fields and joins collected text fragments once per source. Core27 tests plus17 new host regression checks; the67 original journal assertions remain separate. See [current boundaries](docs/boundaries.md), [ecological scope](docs/ecosystem.md) and [recovery contract](docs/recovery.md).
