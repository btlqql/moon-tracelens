///|
pub fn bucket_events(request : Value) -> Value raise {
  let width = num(get(request, "width_seconds"))
  let origin = optional_num(get(request, "origin"), 0.0)
  if width <= 0.0 || width > 1000000000.0 {
    raise InputError("invalid time bucket width")
  }
  let report = analyze(request)
  let events = arr(get(report, "events"))
  let buckets : Map[String, Array[Value]] = Map([])
  let starts : Map[String, Double] = Map([])
  for event in events {
    let start = ((num(get(event, "timestamp")) - origin) / width).floor() *
      width +
      origin
    if start.is_nan() ||
      start.is_inf() ||
      (start + width).is_inf() ||
      start + width == start {
      raise InputError("time bucket precision or range exceeded")
    }
    let key = canonical(Number(start))
    let bucket = buckets.get(key).unwrap_or([])
    bucket.push(event)
    buckets[key] = bucket
    starts[key] = start
  }
  let keys = buckets.keys().collect()
  keys.sort_by(fn(a, b) { starts[a].compare(starts[b]) })
  let output = keys.map(fn(key) {
    record([
      ("start", Number(starts[key])),
      ("end", Number(starts[key] + width)),
      ("metrics", metric(buckets[key])),
    ])
  })
  record([
    ("buckets", Array(output)),
    ("width_seconds", Number(width)),
    ("origin", Number(origin)),
    ("events_considered", Number(events.length().to_double())),
    ("diagnostics", get(report, "diagnostics")),
    (
      "interval",
      String("start inclusive; end exclusive; empty buckets omitted"),
    ),
  ])
}
