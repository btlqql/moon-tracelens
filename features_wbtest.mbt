///|
test "baseline group alignment" {
  let result = run(parse_value("{\"operation\":\"compare\",\"before\":{\"events\":[{\"timestamp\":1,\"level\":\"info\",\"message\":\"sample\",\"service\":\"a\",\"duration_ms\":10},{\"timestamp\":2,\"level\":\"error\",\"message\":\"sample\",\"service\":\"b\",\"duration_ms\":20}],\"group_by\":\"service\"},\"after\":{\"events\":[{\"timestamp\":3,\"level\":\"error\",\"message\":\"sample\",\"service\":\"a\",\"duration_ms\":30},{\"timestamp\":4,\"level\":\"info\",\"message\":\"sample\",\"service\":\"c\",\"duration_ms\":5}],\"group_by\":\"service\"}}"))
  assert_eq(test_at(result, ["complete"]), parse_value("true"))
  assert_eq(test_at(result, ["metrics","delta","count"]), parse_value("0"))
  assert_eq(test_at(result, ["metrics","delta","errors"]), parse_value("0"))
  assert_eq(test_at(result, ["metrics","delta","duration_p95_ms"]), parse_value("10"))
  assert_eq(test_at(result, ["groups","0","key"]), parse_value("\"a\""))
  assert_eq(test_at(result, ["groups","0","status"]), parse_value("\"retained\""))
  assert_eq(test_at(result, ["groups","0","metrics","delta","errors"]), parse_value("1"))
  assert_eq(test_at(result, ["groups","1","status"]), parse_value("\"removed\""))
  assert_eq(test_at(result, ["groups","1","metrics","after","count"]), parse_value("0"))
  assert_eq(test_at(result, ["groups","1","metrics","delta","error_fraction"]), parse_value("null"))
  assert_eq(test_at(result, ["groups","2","status"]), parse_value("\"added\""))
}

///|
test "empty baseline rate is unknown" {
  let result = run(parse_value("{\"operation\":\"compare\",\"before\":{\"events\":[]},\"after\":{\"events\":[{\"timestamp\":1,\"level\":\"error\",\"message\":\"sample\",\"service\":\"api\",\"duration_ms\":5}]}}"))
  assert_eq(test_at(result, ["metrics","delta","count"]), parse_value("1"))
  assert_eq(test_at(result, ["metrics","before","error_fraction"]), parse_value("null"))
  assert_eq(test_at(result, ["metrics","delta","error_fraction"]), parse_value("null"))
}

///|
test "comparison preserves parse failures" {
  let result = run(parse_value("{\"operation\":\"compare\",\"before\":{\"events\":[]},\"after\":{\"sources\":[{\"name\":\"bad\",\"text\":\"invalid json\"}]}}"))
  assert_eq(test_at(result, ["complete"]), parse_value("false"))
  assert_eq(test_at(result, ["after_diagnostics","0","line"]), parse_value("1"))
  assert_eq(test_at(result, ["metrics","after","count"]), parse_value("0"))
}

///|
test "group dimension mismatch" {
  let failed = try { ignore(run(parse_value("{\"operation\":\"compare\",\"before\":{\"events\":[{\"timestamp\":1,\"level\":\"info\",\"message\":\"sample\",\"service\":\"a\",\"duration_ms\":10},{\"timestamp\":2,\"level\":\"error\",\"message\":\"sample\",\"service\":\"b\",\"duration_ms\":20}],\"group_by\":\"service\"},\"after\":{\"events\":[],\"group_by\":\"request_id\"}}"))); false } catch { _ => true }
  assert_true(failed)
}

///|
test "backwards time window" {
  let failed = try { ignore(run(parse_value("{\"events\":[],\"since\":10,\"until\":5}"))); false } catch { _ => true }
  assert_true(failed)
}

///|
test "half open time window" {
  let result = run(parse_value("{\"events\":[{\"timestamp\":1,\"level\":\"info\",\"message\":\"sample\",\"service\":\"a\",\"duration_ms\":1},{\"timestamp\":2,\"level\":\"error\",\"message\":\"sample\",\"service\":\"a\",\"duration_ms\":2}],\"since\":1,\"until\":2}"))
  assert_eq(test_at(result, ["metrics","count"]), parse_value("1"))
  assert_eq(test_at(result, ["metrics","errors"]), parse_value("0"))
}

