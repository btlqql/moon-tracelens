///|
fn test_at(value : Value, parts : Array[String]) -> Value raise {
  let mut current = value
  for part in parts {
    current = match current {
      Object(fields) =>
        match fields.get(part) {
          Some(v) => v
          None => raise InputError("test key missing: " + part)
        }
      Array(items) => items[num(parse_value(part)).to_int()]
      _ => raise InputError("invalid test traversal")
    }
  }
  current
}

///|
test "request metrics timeline" {
  let result = run(
    parse_value(
      "{\"events\":[{\"timestamp\":\"2026-10-01T00:00:00Z\",\"level\":\"info\",\"message\":\"start\",\"request_id\":\"r\",\"duration_ms\":10},{\"timestamp\":\"2026-10-01T00:00:01+00:00\",\"level\":\"error\",\"message\":\"failed\",\"request_id\":\"r\",\"duration_ms\":20}]}",
    ),
  )
  assert_eq(test_at(result, ["metrics", "count"]), parse_value("2"))
  assert_eq(test_at(result, ["metrics", "errors"]), parse_value("1"))
  assert_eq(test_at(result, ["metrics", "duration_p95_ms"]), parse_value("20"))
  assert_eq(
    test_at(result, ["groups", "0", "elapsed_seconds"]),
    parse_value("1"),
  )
}

///|
test "time filter" {
  let result = run(
    parse_value(
      "{\"events\":[{\"timestamp\":\"2026-10-01T00:00:00Z\",\"level\":\"info\",\"message\":\"start\",\"request_id\":\"r\",\"duration_ms\":10},{\"timestamp\":\"2026-10-01T00:00:01+00:00\",\"level\":\"error\",\"message\":\"failed\",\"request_id\":\"r\",\"duration_ms\":20}],\"since\":\"2026-10-01T00:00:01Z\"}",
    ),
  )
  assert_eq(test_at(result, ["metrics", "count"]), parse_value("1"))
  assert_eq(test_at(result, ["metrics", "errors"]), parse_value("1"))
}

///|
test "offset equivalence" {
  let result = run(
    parse_value(
      "{\"events\":[{\"timestamp\":\"1970-01-01T01:00:00+01:00\",\"level\":\"info\",\"message\":\"x\"}]}",
    ),
  )
  assert_eq(test_at(result, ["events", "0", "timestamp"]), parse_value("0"))
}

///|
test "empty metrics" {
  let result = run(parse_value("{\"events\":[]}"))
  assert_eq(test_at(result, ["metrics", "count"]), parse_value("0"))
  assert_eq(test_at(result, ["metrics", "error_fraction"]), parse_value("null"))
}

///|
test "bad date diagnostic" {
  let result = run(
    parse_value(
      "{\"events\":[{\"timestamp\":\"2025-02-29T00:00:00Z\",\"level\":\"info\",\"message\":\"x\"}]}",
    ),
  )
  assert_eq(test_at(result, ["metrics", "count"]), parse_value("0"))
}

///|
test "level normalisation" {
  let result = run(
    parse_value(
      "{\"events\":[{\"timestamp\":1,\"level\":\"warning\",\"message\":\"x\"}]}",
    ),
  )
  assert_eq(test_at(result, ["events", "0", "level"]), parse_value("\"warn\""))
}
