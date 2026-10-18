# Changelog

## 0.3.0 — 2026-10-18

Registry version: 0.3.0.

新增 buckets 操作，按 width_seconds 和 origin 划分左闭右开的时间桶；负时间与小数边界同样按 floor 定义处理。每桶复用事件数、错误数、错误比例和延迟 p95，保留摄入诊断，空桶省略。先应用现有过滤，再生成桶；输出事件总数可以与桶计数之和对照。

## 0.2.0 — 2026-10-16

Baseline/current comparison with aligned groups, metric deltas and preserved ingestion diagnostics. Orphan multiline continuations are quarantined, including after bad records or across separately supplied sources.

Added regression fixtures and independent randomized checks for the revised behavior.

## 0.1.0 — 2026-10-05

Initial library, JSON CLI, fixtures and independent reference checks.
