# TraceLens 0.4.0 recovery kernel

The independent core is byte ingestion and deterministic recovery, rather than the pre-existing filter/group/p95 operations. `recovery/framer.mbt` retains partial bytes before UTF-8 decoding, physical line ordinal and CRLF boundaries. Checkpoints are JSON data; invalid offsets, schemas and inconsistent tails fail explicitly. Oversized lines are retained as bounded quarantined byte fragments. Unfinished source closure is explicit. Raw bytes and source/generation/start/end identifiers remain available.

`stream_apply` accepts state (null initially) and action. `stream_plan` accepts manifest (null initially), batches and action. `stream_recover` verifies a committed hash chain and replays every action, comparing stored state and records with recomputation. `stream_replay` rebuilds analytical events from committed physical records by source/generation, retaining storage diagnostics. Pipe multiline ownership is reconstructed by full deterministic replay, not stored as a live open-event object. Invalid physical bytes reset ownership; orphan continuations are reported.

Actions: init(source,identity,format?,max_line_bytes?), append(offset,hex,close?), seal, rotate(identity,kind). Rotation kind rename preserves observed old-generation bytes; truncate/ambiguous emits loss_possible because unread overwritten bytes cannot be reconstructed. A complete line's raw hex includes CRLF; its text excludes the delimiter. Event line numbers in analytical replay may differ after fragmented quarantine; use physical byte ranges for provenance.

## Host and commit contract

`scripts/journal.mjs` exports Journal and JournalSource. A Journal store must be under one trusted, previously persisted filesystem directory. A single writer uses exclusive file creation; after a crashed writer, the operator must verify it is gone and remove writer.lock explicitly. This is not an OS-released advisory lock or a distributed lock. Batch paths are fixed SHA-256 hex names; symlink batch directories/files are rejected.

Commit order is write batch → fsync batch → fsync batch directory → write temporary manifest → fsync manifest → atomic rename manifest → fsync store directory. The core returns the plan and expected head; the host rereads the head under the lock and acknowledges only after all steps complete. Crash after manifest rename can expose a valid commit whose acknowledgement was not received; callers recover the offset before retrying. Missing or corrupt committed data is an error, never silent reset. Unreferenced batches are not promoted; an exact immutable orphan may be reused on retry.

Linux uses file and directory fsync. Windows reports process_crash_only and skips directory fsync. The tests kill a process at each of seven commit actions; they do not physically cut power or certify a storage device's flush semantics. See [Linux fsync contract](https://man7.org/linux/man-pages/man2/fsync.2.html).

JournalSource retains an open file descriptor across rename, drains late old-file appends, then adopts a new file only on explicit rotate(). An EOF does not imply the old writer has finished. Restart rejects an inode identity change rather than assuming the old generation was fully read. In-place truncate is detected only when size drops below captured offset: truncate and regrow between polls is not detectable by this adapter. Writes after explicit old-generation close are outside its guarantee. A source name is descriptive; persisted identity uses device/inode.

## Bounded operation

At most 256 committed actions per store, 4 MiB total source bytes, 64 KiB per core append, 4096 physical records per action, line limit 1..65536 bytes (default4096). Host polls chunks of4096 bytes and caps request JSON at16 MiB. The store refuses quota overflow and needs a new store after exhaustion; it has no compaction or indefinite retention. Recovery checks the full chain each time; no constant-time or high-throughput claim. SHA-256 is a checksum, not authentication against someone rewriting the complete store.

## Reproduce

```sh
moon update
moon build --target js
node scripts/journal.mjs /tmp/tracelens-store commit '{"type":"init","source":"demo","identity":"file1"}'
node scripts/journal.mjs /tmp/tracelens-store commit '{"type":"append","offset":0,"hex":"610a"}'
node scripts/journal.mjs /tmp/tracelens-store recover
node scripts/journal-test.mjs
```

67 host assertions include seven separate process crashes, stale-lock handling, exact orphan retry, corrupted/missing committed data, restart with split UTF-8, CRLF, multiline replay, real rename/late writes, truncate, writer exclusion, byte conservation across twelve chunk patterns, oversized and invalid UTF-8 quarantine. Pure recovery tests run with the original analyzer tests on four targets. These are synthetic deterministic checks, not deployment evidence.

## 0.4.1 host validation

Projected recovery envelopes are checked before writing any batch, so quota refusal cannot acknowledge an unreadable next chain. Host regression tests use a4096-byte envelope and verify no head, offset or immutable-batch change on overflow. Explicit restart options must match the checkpoint. Stale readers and sealed generations reject polling. Random temporary names tolerate old PID-based manifest residue without deleting it.17 additional host checks cover these conditions.
