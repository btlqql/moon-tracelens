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
