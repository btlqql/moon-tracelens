# Version 0.4.1 current boundaries

The library retains offline JSONL/pipe event analysis and adds bounded byte capture, source-generation transitions and committed deterministic recovery. Node Journal/JournalSource perform actual file I/O; pure MoonBit implements framing, checkpoint and journal semantics. Full contract: [recovery.md](recovery.md).

Maximum256 commits /4MiB source per store, core64KiB per append /4096 records, JSON envelope default16000000 bytes configurable down to1024. Both the current chain and projected next committed chain must fit before a write. No compaction, indefinite retention, distributed ingestion or OpenTelemetry exporter. Every recovery validates the full chain.

Linux uses file/directory fsync; Windows only reports process-crash recovery. Tests inject process exits rather than physical power loss. Trusted single-host directory, exclusive-create writer lock, manual stale-lock recovery after verifying the writer exited. Concurrent mutation by untrusted filesystem actors is outside the store model. SHA-256 is integrity checking, not authentication.

Reader restarts reject explicitly conflicting configuration, sealed generations and identity mismatch. Polling rejects a reader whose descriptor identity is no longer current. Rename handover is explicit; old writes after handover are outside its guarantee. Truncate/regrow above the captured offset between polls is not detectable. Captured bytes are preserved, unread overwritten bytes cannot be reconstructed.

Physical byte ranges are the provenance reference. Replay joins per-generation fragments once and reconstructs multiline ownership; it does not persist an incremental open-event object. Timestamp analysis accepts uppercase T/Z RFC3339, years0001–9999, no leap seconds. Metric comparisons do not establish causality or statistical significance.
