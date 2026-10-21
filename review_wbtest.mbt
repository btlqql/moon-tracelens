///|
test "replay rejects an unrecognized top-level option" {
  let mut rejected = false
  ignore(
    run(
      parse_value(
        "{\"operation\":\"stream_replay\",\"manifest\":null,\"batches\":[],\"typo\":true}",
      ),
    ),
  ) catch {
    _ => rejected = true
  }
  assert_true(rejected)
}

///|
test "replay refuses an alternate uncommitted event source" {
  let mut rejected = false
  ignore(
    run(
      parse_value(
        "{\"operation\":\"stream_replay\",\"manifest\":null,\"batches\":[],\"analysis\":{\"events\":[]}}",
      ),
    ),
  ) catch {
    _ => rejected = true
  }
  assert_true(rejected)
}
