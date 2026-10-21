///|
fn stream_replay(request : Value) -> Value raise {
  for key, _ in obj(request) {
    if !["operation", "manifest", "batches", "analysis"].contains(key) {
      raise InputError("unknown replay field: " + key)
    }
  }
  let recovered = from_json(
    @recovery.execute(
      record([
        ("operation", String("stream_recover")),
        ("manifest", get(request, "manifest")),
        ("batches", get(request, "batches")),
      ]).to_json(),
    ),
  )
  let texts : Map[String, Array[String]] = Map([])
  let formats : Map[String, Value] = Map([])
  let order : Array[String] = []
  let storage : Array[Value] = []
  for entry in arr(get(recovered, "records")) {
    let kind = str(get(entry, "kind"))
    if kind == "source_boundary" {
      storage.push(entry)
      continue
    }
    let key = canonical(Array([get(entry, "source"), get(entry, "generation")]))
    if !texts.contains(key) {
      texts[key] = []
      formats[key] = get(entry, "format")
      order.push(key)
    }
    if kind == "quarantine" {
      // A malformed non-whitespace line deliberately resets pipe continuation ownership.
      texts[key].push("!TRACE_STORAGE_QUARANTINE!\n")
      storage.push(entry)
    } else {
      texts[key].push(str(get(entry, "text")) + "\n")
      if kind == "incomplete" {
        storage.push(entry)
      }
    }
  }
  let options = if get(request, "analysis") == Null {
    Map([])
  } else {
    obj(get(request, "analysis")).copy()
  }
  if options.contains("events") || options.contains("sources") {
    raise InputError("replay analysis cannot replace committed sources")
  }
  options["sources"] = Array(
    order.map(key => {
      record([
        ("name", String(key)),
        ("format", formats[key]),
        ("text", String(texts[key].join(""))),
      ])
    }),
  )
  record([
    ("analysis", analyze(Object(options))),
    ("state", get(recovered, "state")),
    ("revision", get(recovered, "revision")),
    ("storage_diagnostics", Array(storage)),
    ("source_bytes", get(recovered, "source_bytes")),
  ])
}
