///|
fn metric_delta(before : Value, after : Value, key : String) -> Value raise {
  match (get(before, key), get(after, key)) {
    (Number(a), Number(b)) => {
      let delta = b - a
      if delta.is_inf() || delta.is_nan() {
        raise InputError("metric delta overflow")
      }
      Number(delta)
    }
    _ => Null
  }
}

///|
fn compare_metrics(before : Value, after : Value) -> Value raise {
  let empty = record([
    ("count", Number(0.0)),
    ("errors", Number(0.0)),
    ("error_fraction", Null),
    ("duration_p95_ms", Null),
    ("levels", Object(Map([]))),
  ])
  let old = if before == Null { empty } else { before }
  let next = if after == Null { empty } else { after }
  record([
    ("before", old),
    ("after", next),
    (
      "delta",
      record([
        ("count", metric_delta(old, next, "count")),
        ("errors", metric_delta(old, next, "errors")),
        ("error_fraction", metric_delta(old, next, "error_fraction")),
        ("duration_p95_ms", metric_delta(old, next, "duration_p95_ms")),
      ]),
    ),
  ])
}

///|
pub fn compare_windows(before : Value, after : Value) -> Value raise {
  let old_field = optional_str(get(before, "group_by"), "request_id")
  let new_field = optional_str(get(after, "group_by"), "request_id")
  if old_field != new_field {
    raise InputError("window comparison requires the same group_by field")
  }
  let old = analyze(before)
  let next = analyze(after)
  let old_groups : Map[String, Value] = Map([])
  let new_groups : Map[String, Value] = Map([])
  let union : Map[String, Bool] = Map([])
  for group in arr(get(old, "groups")) {
    let key = canonical(get(group, "key"))
    old_groups[key] = group
    union[key] = true
  }
  for group in arr(get(next, "groups")) {
    let key = canonical(get(group, "key"))
    new_groups[key] = group
    union[key] = true
  }
  let keys = union.keys().collect()
  keys.sort()
  let changes = keys.map(fn(key) {
    let old_group = old_groups.get(key).unwrap_or(Null)
    let new_group = new_groups.get(key).unwrap_or(Null)
    record([
      ("key", get(if new_group == Null { old_group } else { new_group }, "key")),
      (
        "status",
        String(
          if old_group == Null {
            "added"
          } else if new_group == Null {
            "removed"
          } else {
            "retained"
          },
        ),
      ),
      (
        "metrics",
        compare_metrics(get(old_group, "metrics"), get(new_group, "metrics")),
      ),
    ])
  })
  record([
    ("group_by", String(old_field)),
    ("metrics", compare_metrics(get(old, "metrics"), get(next, "metrics"))),
    ("groups", Array(changes)),
    ("before_diagnostics", get(old, "diagnostics")),
    ("after_diagnostics", get(next, "diagnostics")),
    (
      "complete",
      Bool(
        arr(get(old, "diagnostics")).is_empty() &&
        arr(get(next, "diagnostics")).is_empty(),
      ),
    ),
  ])
}

///|
pub fn run(request : Value) -> Value raise {
  match optional_str(get(request, "operation"), "analyze") {
    "stream_apply" | "stream_plan" | "stream_recover" =>
      from_json(@recovery.execute(request.to_json()))
    "stream_replay" => stream_replay(request)
    "buckets" => bucket_events(request)
    "analyze" => analyze(request)
    "compare" => compare_windows(get(request, "before"), get(request, "after"))
    _ => raise InputError("operation must be analyze or compare")
  }
}
