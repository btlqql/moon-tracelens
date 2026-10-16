///|
test "malformed record breaks continuation ownership" {
  let result = run(
    record([
      (
        "sources",
        Array([
          record([
            ("name", String("app")),
            ("format", String("pipe")),
            (
              "text",
              String(
                "1970-01-01T00:00:00Z|info|api|r|good\nbad line\n  bad stack\n1970-01-01T00:00:01Z|error|api|r|failed\n  valid stack",
              ),
            ),
          ]),
        ]),
      ),
    ]),
  )
  let events = arr(get(result, "events"))
  let diagnostics = arr(get(result, "diagnostics"))
  assert_eq(events.length(), 2)
  assert_eq(diagnostics.length(), 2)
  assert_eq(get(events[0], "message"), String("good"))
  assert_eq(get(events[1], "message"), String("failed\n  valid stack"))
  assert_eq(get(diagnostics[1], "line"), Number(3.0))
}

///|
test "continuations do not cross separately supplied sources with the same name" {
  let result = run(
    record([
      (
        "sources",
        Array([
          record([
            ("name", String("same")),
            ("format", String("pipe")),
            ("text", String("1970-01-01T00:00:00Z|info|api|r|first")),
          ]),
          record([
            ("name", String("same")),
            ("format", String("pipe")),
            ("text", String("  orphan")),
          ]),
        ]),
      ),
    ]),
  )
  assert_eq(arr(get(result, "diagnostics")).length(), 1)
  assert_eq(get(arr(get(result, "events"))[0], "message"), String("first"))
}
