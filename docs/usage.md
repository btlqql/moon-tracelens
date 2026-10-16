# Request and result guide

Every example below is an executable fixture. Assertions cover the listed result fields; additional output fields are documented by the API and other fixtures. Error cases intentionally reject the request.

## request metrics timeline

```json
{
  "events": [
    {
      "timestamp": "2026-10-01T00:00:00Z",
      "level": "info",
      "message": "start",
      "request_id": "r",
      "duration_ms": 10
    },
    {
      "timestamp": "2026-10-01T00:00:01+00:00",
      "level": "error",
      "message": "failed",
      "request_id": "r",
      "duration_ms": 20
    }
  ]
}
```

Expected result fields:

```json
{
  "metrics/count": 2,
  "metrics/errors": 1,
  "metrics/duration_p95_ms": 20,
  "groups/0/elapsed_seconds": 1
}
```

## time filter

```json
{
  "events": [
    {
      "timestamp": "2026-10-01T00:00:00Z",
      "level": "info",
      "message": "start",
      "request_id": "r",
      "duration_ms": 10
    },
    {
      "timestamp": "2026-10-01T00:00:01+00:00",
      "level": "error",
      "message": "failed",
      "request_id": "r",
      "duration_ms": 20
    }
  ],
  "since": "2026-10-01T00:00:01Z"
}
```

Expected result fields:

```json
{
  "metrics/count": 1,
  "metrics/errors": 1
}
```

## offset equivalence

```json
{
  "events": [
    {
      "timestamp": "1970-01-01T01:00:00+01:00",
      "level": "info",
      "message": "x"
    }
  ]
}
```

Expected result fields:

```json
{
  "events/0/timestamp": 0
}
```

## empty metrics

```json
{
  "events": []
}
```

Expected result fields:

```json
{
  "metrics/count": 0,
  "metrics/error_fraction": null
}
```

## bad date diagnostic

```json
{
  "events": [
    {
      "timestamp": "2025-02-29T00:00:00Z",
      "level": "info",
      "message": "x"
    }
  ]
}
```

Expected result fields:

```json
{
  "metrics/count": 0
}
```

## level normalisation

```json
{
  "events": [
    {
      "timestamp": 1,
      "level": "warning",
      "message": "x"
    }
  ]
}
```

Expected result fields:

```json
{
  "events/0/level": "warn"
}
```

## Host adapter

```sh
node scripts/files.mjs MANIFEST.json
```

Read the current boundaries before using this adapter.


# 0.2.0 additional executable scenarios

## baseline group alignment

```json
{
  "operation": "compare",
  "before": {
    "events": [
      {
        "timestamp": 1,
        "level": "info",
        "message": "sample",
        "service": "a",
        "duration_ms": 10
      },
      {
        "timestamp": 2,
        "level": "error",
        "message": "sample",
        "service": "b",
        "duration_ms": 20
      }
    ],
    "group_by": "service"
  },
  "after": {
    "events": [
      {
        "timestamp": 3,
        "level": "error",
        "message": "sample",
        "service": "a",
        "duration_ms": 30
      },
      {
        "timestamp": 4,
        "level": "info",
        "message": "sample",
        "service": "c",
        "duration_ms": 5
      }
    ],
    "group_by": "service"
  }
}
```

Expected result fields:

```json
{
  "complete": true,
  "metrics/delta/count": 0,
  "metrics/delta/errors": 0,
  "metrics/delta/duration_p95_ms": 10,
  "groups/0/key": "a",
  "groups/0/status": "retained",
  "groups/0/metrics/delta/errors": 1,
  "groups/1/status": "removed",
  "groups/1/metrics/after/count": 0,
  "groups/1/metrics/delta/error_fraction": null,
  "groups/2/status": "added"
}
```

## empty baseline rate is unknown

```json
{
  "operation": "compare",
  "before": {
    "events": []
  },
  "after": {
    "events": [
      {
        "timestamp": 1,
        "level": "error",
        "message": "sample",
        "service": "api",
        "duration_ms": 5
      }
    ]
  }
}
```

Expected result fields:

```json
{
  "metrics/delta/count": 1,
  "metrics/before/error_fraction": null,
  "metrics/delta/error_fraction": null
}
```

## comparison preserves parse failures

```json
{
  "operation": "compare",
  "before": {
    "events": []
  },
  "after": {
    "sources": [
      {
        "name": "bad",
        "text": "invalid json"
      }
    ]
  }
}
```

Expected result fields:

```json
{
  "complete": false,
  "after_diagnostics/0/line": 1,
  "metrics/after/count": 0
}
```

## group dimension mismatch

```json
{
  "operation": "compare",
  "before": {
    "events": [
      {
        "timestamp": 1,
        "level": "info",
        "message": "sample",
        "service": "a",
        "duration_ms": 10
      },
      {
        "timestamp": 2,
        "level": "error",
        "message": "sample",
        "service": "b",
        "duration_ms": 20
      }
    ],
    "group_by": "service"
  },
  "after": {
    "events": [],
    "group_by": "request_id"
  }
}
```

Expected: an input error.

## backwards time window

```json
{
  "events": [],
  "since": 10,
  "until": 5
}
```

Expected: an input error.

## half open time window

```json
{
  "events": [
    {
      "timestamp": 1,
      "level": "info",
      "message": "sample",
      "service": "a",
      "duration_ms": 1
    },
    {
      "timestamp": 2,
      "level": "error",
      "message": "sample",
      "service": "a",
      "duration_ms": 2
    }
  ],
  "since": 1,
  "until": 2
}
```

Expected result fields:

```json
{
  "metrics/count": 1,
  "metrics/errors": 0
}
```
