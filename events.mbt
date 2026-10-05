///|
fn normalize_event(raw : Value, source : String, line : Int) -> Value raise {
  let fields = obj(raw).copy()
  let time = if get(raw, "timestamp") != Null {
    get(raw, "timestamp")
  } else {
    get(raw, "time")
  }
  let normalized_time = timestamp(time)
  let level = optional_str(get(raw, "level"), "info").to_lower()
  if !["trace", "debug", "info", "warn", "warning", "error", "fatal"].contains(
      level,
    ) {
    raise InputError("unknown log level")
  }
  fields["timestamp"] = Number(normalized_time)
  fields["level"] = String(if level == "warning" { "warn" } else { level })
  fields["message"] = String(str(get(raw, "message")))
  fields["source"] = String(source)
  fields["line"] = Number(line.to_double())
  if get(raw, "duration_ms") != Null && num(get(raw, "duration_ms")) < 0.0 {
    raise InputError("negative duration")
  }
  Object(fields)
}

///|
fn parse_pipe(line : String) -> Value raise {
  let pieces : Array[String] = []
  let mut rest = line
  while pieces.length() < 4 {
    match rest.split_once("|") {
      Some((a, b)) => {
        pieces.push(a.to_string())
        rest = b.to_string()
      }
      None => raise InputError("pipe log needs five columns")
    }
  }
  record([
    ("timestamp", String(pieces[0])),
    ("level", String(pieces[1])),
    ("service", String(pieces[2])),
    ("request_id", if pieces[3] == "" { Null } else { String(pieces[3]) }),
    ("message", String(rest)),
  ])
}

///|
fn ingest(request : Value) -> (Array[Value], Array[Value]) raise {
  let events : Array[Value] = []
  let diagnostics : Array[Value] = []
  if get(request, "events") != Null {
    let records = arr(get(request, "events"))
    for i = 0; i < records.length(); i = i + 1 {
      events.push(normalize_event(records[i], "events", i + 1)) catch {
        error =>
          diagnostics.push(
            record([
              ("source", String("events")),
              ("line", Number((i + 1).to_double())),
              ("reason", String(error.to_string())),
            ]),
          )
      }
    }
  }
  if get(request, "sources") != Null {
    for source in arr(get(request, "sources")) {
      let name = str(get(source, "name"))
      let format = optional_str(get(source, "format"), "jsonl")
      if !["jsonl", "pipe"].contains(format) {
        raise InputError("unsupported log format")
      }
      let mut line_number = 0
      for line in str(get(source, "text")).split("\n") {
        line_number += 1
        if line.trim().is_empty() {
          continue
        }
        if format == "pipe" && (line.has_prefix(" ") || line.has_prefix("\t")) {
          if events.is_empty() ||
            get(events[events.length() - 1], "source") != String(name) {
            raise InputError("orphan multiline continuation")
          }
          let fields = obj(events[events.length() - 1]).copy()
          fields["message"] = String(
            str(fields["message"]) + "\n" + line.to_string(),
          )
          events[events.length() - 1] = Object(fields)
          continue
        }
        try {
          let raw = if format == "jsonl" {
            parse_value(line)
          } else {
            parse_pipe(line.trim_end().to_string())
          }
          events.push(normalize_event(raw, name, line_number))
        } catch {
          error =>
            diagnostics.push(
              record([
                ("source", String(name)),
                ("line", Number(line_number.to_double())),
                ("reason", String(error.to_string())),
              ]),
            )
        }
      }
    }
  }
  events.sort_by(fn(a, b) {
    let x = match get(a, "timestamp") {
      Number(n) => n
      _ => 0.0
    }
    let y = match get(b, "timestamp") {
      Number(n) => n
      _ => 0.0
    }
    let time = x.compare(y)
    if time != 0 {
      time
    } else {
      canonical(a).compare(canonical(b))
    }
  })
  (events, diagnostics)
}

///|
fn metric(events : Array[Value]) -> Value raise {
  let mut failures = 0
  let durations : Array[Double] = []
  let levels : Map[String, Value] = {}
  for event in events {
    let level = str(get(event, "level"))
    if level == "error" || level == "fatal" {
      failures += 1
    }
    levels[level] = Number(
      optional_num(levels.get(level).unwrap_or(Null), 0.0) + 1.0,
    )
    if get(event, "duration_ms") != Null {
      durations.push(num(get(event, "duration_ms")))
    }
  }
  durations.sort()
  let percentile = if durations.is_empty() {
    Null
  } else {
    Number(
      durations[((durations.length().to_double() * 0.95).ceil().to_int() - 1).max(
        0,
      )],
    )
  }
  record([
    ("count", Number(events.length().to_double())),
    ("errors", Number(failures.to_double())),
    (
      "error_fraction",
      if events.is_empty() {
        Null
      } else {
        Number(failures.to_double() / events.length().to_double())
      },
    ),
    ("duration_p95_ms", percentile),
    ("levels", Object(levels)),
  ])
}

///|
pub fn run(request : Value) -> Value raise {
  let (all_events, diagnostics) = ingest(request)
  let mut events = all_events
  if get(request, "where") != Null {
    let query = obj(get(request, "where"))
    events = events.filter(fn(event) {
      for key, expected in query {
        if get(event, key) != expected {
          return false
        }
      }
      true
    })
  }
  if get(request, "since") != Null {
    let since = timestamp(get(request, "since"))
    events = events.filter(fn(e) { num(get(e, "timestamp")) >= since })
  }
  if get(request, "until") != Null {
    let until = timestamp(get(request, "until"))
    events = events.filter(fn(e) { num(get(e, "timestamp")) < until })
  }
  if get(request, "contains") != Null {
    let term = str(get(request, "contains"))
    events = events.filter(fn(e) { str(get(e, "message")).contains(term) })
  }
  let groups : Map[String, Array[Value]] = {}
  let group_field = optional_str(get(request, "group_by"), "request_id")
  let mut missing = 0
  for event in events {
    let key = get(event, group_field)
    if key == Null || key == String("") {
      missing += 1
      continue
    }
    let id = canonical(key)
    let bucket = groups.get(id).unwrap_or([])
    bucket.push(event)
    groups[id] = bucket
  }
  let ordered = groups.keys().collect()
  ordered.sort()
  let timelines = ordered.map(fn(id) {
    let bucket = groups[id]
    record([
      ("key", get(bucket[0], group_field)),
      (
        "elapsed_seconds",
        Number(
          num(get(bucket[bucket.length() - 1], "timestamp")) -
          num(get(bucket[0], "timestamp")),
        ),
      ),
      ("metrics", metric(bucket)),
      ("events", Array(bucket)),
    ])
  })
  record([
    ("events", Array(events)),
    ("diagnostics", Array(diagnostics)),
    ("metrics", metric(events)),
    ("groups", Array(timelines)),
    ("ungrouped_events", Number(missing.to_double())),
  ])
}
