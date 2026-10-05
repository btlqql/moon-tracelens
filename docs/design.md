# Implemented architecture

## Core

JSONL and five-column pipe log ingestion; multiline stack continuations; epoch/RFC3339 timestamps; severity normalisation; source/line diagnostics; filters; request/service grouping; sorted timelines; error fractions and nearest-rank duration p95. scripts/files.mjs reads real selected log files.

## Boundaries

Offline batch analysis. Uppercase T/Z RFC3339, years 0001–9999, no leap seconds. Timestamps are seconds and duration_ms is milliseconds. Sources that fail event normalisation produce diagnostics; orphan pipe continuations are structural errors. No live tailing, rotation recovery or distributed tracing exporter.

## Integration

The core accepts semantic values and returns deterministic JSON-shaped reports. Host adapters handle files, network or processes; they invoke the compiled MoonBit engine. The CLI package declares `supported_targets = "js"`; other backends test the portable core.

## Validation evidence

Fixture cases are hand-checked assertions. Independent reference checks and integration scripts are runnable from a clean checkout. CI executes four core backends and host checks. Historical proposal targets are not release results.
