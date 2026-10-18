///|
fn followup_at(value : Value, keys : Array[String]) -> Value raise {
  let mut current = value
  for key in keys {
    current = match current {
      Object(fields) => fields[key]
      Array(items) => {
        let index = match @json.parse(key) {
          Json::Number(n, ..) => n.to_int()
          _ => raise InputError("invalid test index")
        }
        items[index]
      }
      _ => raise InputError("invalid test path")
    }
  }
  current
}

///|
test "followup time bucket boundaries" {
  let result = run(
    from_json(
      @json.parse(
        "{\"operation\":\"buckets\",\"events\":[{\"timestamp\":-1,\"level\":\"info\",\"message\":\"x\"},{\"timestamp\":0,\"level\":\"info\",\"message\":\"x\"},{\"timestamp\":9,\"level\":\"info\",\"message\":\"x\"},{\"timestamp\":10,\"level\":\"error\",\"message\":\"x\"}],\"width_seconds\":10}",
      ),
    ),
  )
  assert_eq(
    followup_at(result, ["events_considered"]),
    from_json(@json.parse("4")),
  )
  assert_eq(
    followup_at(result, ["buckets", "0", "start"]),
    from_json(@json.parse("-10")),
  )
  assert_eq(
    followup_at(result, ["buckets", "0", "metrics", "count"]),
    from_json(@json.parse("1")),
  )
  assert_eq(
    followup_at(result, ["buckets", "1", "start"]),
    from_json(@json.parse("0")),
  )
  assert_eq(
    followup_at(result, ["buckets", "1", "metrics", "count"]),
    from_json(@json.parse("2")),
  )
  assert_eq(
    followup_at(result, ["buckets", "2", "start"]),
    from_json(@json.parse("10")),
  )
  assert_eq(
    followup_at(result, ["buckets", "2", "metrics", "errors"]),
    from_json(@json.parse("1")),
  )
}

///|
test "followup bucket zero width" {
  let bad = try {
    ignore(
      run(
        from_json(
          @json.parse(
            "{\"operation\":\"buckets\",\"events\":[],\"width_seconds\":0}",
          ),
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(bad)
}

///|
test "followup bucket filtered counts" {
  let result = run(
    from_json(
      @json.parse(
        "{\"operation\":\"buckets\",\"events\":[{\"timestamp\":-1,\"level\":\"info\",\"message\":\"x\"},{\"timestamp\":0,\"level\":\"info\",\"message\":\"x\"},{\"timestamp\":9,\"level\":\"info\",\"message\":\"x\"},{\"timestamp\":10,\"level\":\"error\",\"message\":\"x\"}],\"width_seconds\":10,\"since\":0,\"until\":10}",
      ),
    ),
  )
  assert_eq(
    followup_at(result, ["events_considered"]),
    from_json(@json.parse("2")),
  )
  assert_eq(
    followup_at(result, ["buckets", "0", "metrics", "count"]),
    from_json(@json.parse("2")),
  )
}

///|
test "followup empty buckets omitted" {
  let result = run(
    from_json(
      @json.parse(
        "{\"operation\":\"buckets\",\"events\":[],\"width_seconds\":10}",
      ),
    ),
  )
  assert_eq(followup_at(result, ["buckets"]), from_json(@json.parse("[]")))
  assert_eq(
    followup_at(result, ["events_considered"]),
    from_json(@json.parse("0")),
  )
}
