///|
priv struct StreamState {
  source : String
  identity : String
  generation : Int32
  format : String
  max_line : Int32
  offset : Double
  line : Int32
  tail : Array[Byte]
  discarding : Bool
  closed : Bool
}

///|
fn small_int(value : Value, maximum : Int32) -> Int32 raise InputError {
  let n = ordinal(value)
  if n > maximum.to_double() {
    raise InputError("integer exceeds configured range")
  }
  n.to_int()
}

///|
fn boolean(value : Value) -> Bool raise InputError {
  match value {
    Bool(b) => b
    _ => raise InputError("expected boolean")
  }
}

///|
fn bytes_hex(value : Value) -> Array[Byte] raise {
  let text = string(value)
  if text.length() > 131072 {
    raise InputError("hex chunk exceeds 65536 bytes")
  }
  @hex.decode(text[:]).to_array()
}

///|
fn hex_bytes(bytes : Array[Byte]) -> Value {
  String(@hex.encode(Bytes::from_array(bytes)[:]))
}

///|
fn state_value(state : StreamState) -> Value {
  record([
    ("schema", Number(1)),
    ("source", String(state.source)),
    ("identity", String(state.identity)),
    ("generation", Number(state.generation.to_double())),
    ("format", String(state.format)),
    ("max_line_bytes", Number(state.max_line.to_double())),
    ("offset", Number(state.offset)),
    ("line", Number(state.line.to_double())),
    ("tail_hex", hex_bytes(state.tail)),
    ("discarding", Bool(state.discarding)),
    ("closed", Bool(state.closed)),
  ])
}

///|
fn read_state(value : Value) -> StreamState raise {
  fields_only(value, [
    "schema", "source", "identity", "generation", "format", "max_line_bytes", "offset",
    "line", "tail_hex", "discarding", "closed",
  ])
  if required(value, "schema") != Number(1) {
    raise InputError("unsupported checkpoint schema")
  }
  let source = identifier(required(value, "source"))
  let identity = identifier(required(value, "identity"))
  let format = string(required(value, "format"))
  if format != "jsonl" && format != "pipe" {
    raise InputError("unsupported format")
  }
  let maximum = small_int(required(value, "max_line_bytes"), 65536)
  if maximum < 1 {
    raise InputError("line byte limit must be positive")
  }
  let tail = bytes_hex(required(value, "tail_hex"))
  let offset = ordinal(required(value, "offset"))
  let closed = boolean(required(value, "closed"))
  let discarding = boolean(required(value, "discarding"))
  if tail.length() > maximum ||
    tail.length().to_double() > offset ||
    (closed && (!tail.is_empty() || discarding)) {
    raise InputError("inconsistent checkpoint tail")
  }
  if tail.contains((10).to_byte()) {
    raise InputError("checkpoint tail contains a complete line")
  }
  {
    source,
    identity,
    generation: small_int(required(value, "generation"), 1000000),
    format,
    max_line: maximum,
    offset,
    line: small_int(required(value, "line"), 1000000000),
    tail,
    discarding,
    closed,
  }
}

///|
fn initial_state(action : Value) -> StreamState raise {
  fields_only(action, ["type", "source", "identity", "format", "max_line_bytes"])
  let format = if has(action, "format") {
    string(field(action, "format"))
  } else {
    "jsonl"
  }
  if format != "jsonl" && format != "pipe" {
    raise InputError("unsupported format")
  }
  {
    source: identifier(required(action, "source")),
    identity: identifier(required(action, "identity")),
    generation: 0,
    format,
    max_line: limit(action, "max_line_bytes", 4096, 65536),
    offset: 0,
    line: 0,
    tail: [],
    discarding: false,
    closed: false,
  }
}

///|
fn physical_record(
  state : StreamState,
  bytes : Array[Byte],
  start : Double,
  end : Double,
  incomplete : Bool,
  quarantined : Bool,
) -> Value {
  let fields : Map[String, Value] = Map([
    (
      "id",
      String(
        Array([
          String(state.source),
          Number(state.generation.to_double()),
          Number(start),
          Number(end),
        ]).canonical(),
      ),
    ),
    ("source", String(state.source)),
    ("generation", Number(state.generation.to_double())),
    ("format", String(state.format)),
    ("start", Number(start)),
    ("end", Number(end)),
    ("line", Number(state.line.to_double() + 1)),
    ("hex", hex_bytes(bytes)),
  ])
  if quarantined {
    fields["kind"] = String("quarantine")
    fields["reason"] = String("oversized_line_fragment")
  } else {
    let content = bytes.copy()
    if content.last().unwrap_or((0).to_byte()) == (10).to_byte() {
      ignore(content.pop())
      if content.last().unwrap_or((0).to_byte()) == (13).to_byte() {
        ignore(content.pop())
      }
    }
    try {
      fields["text"] = String(
        @utf8.decode(Bytes::from_array(content)[:], ignore_bom=false),
      )
      fields["kind"] = String(if incomplete { "incomplete" } else { "record" })
      if incomplete {
        fields["reason"] = String("source_closed_with_unterminated_line")
      }
    } catch {
      _ => {
        fields["kind"] = String("quarantine")
        fields["reason"] = String("invalid_utf8")
      }
    }
  }
  Object(fields)
}

///|
fn append_state(state : StreamState, action : Value) -> Value raise {
  fields_only(action, ["type", "offset", "hex", "close"])
  let bytes = bytes_hex(required(action, "hex"))
  let expected = ordinal(required(action, "offset"))
  if expected != state.offset {
    raise InputError("append offset differs from captured checkpoint")
  }
  let close = if has(action, "close") {
    boolean(field(action, "close"))
  } else {
    false
  }
  if state.closed && (!bytes.is_empty() || !close) {
    raise InputError("source generation is sealed")
  }
  if state.offset + bytes.length().to_double() > 9007199254740991.0 {
    raise InputError("source offset exceeds exact integer range")
  }
  let records : Array[Value] = []
  let tail = state.tail.copy()
  let mut discarding = state.discarding
  let mut offset = state.offset
  let mut line = state.line
  for byte in bytes {
    tail.push(byte)
    offset += 1
    if tail.length() > state.max_line || byte == (10).to_byte() {
      let over = discarding || tail.length() > state.max_line
      records.push(
        physical_record(
          { ..state, line, },
          tail.copy(),
          offset - tail.length().to_double(),
          offset,
          false,
          over,
        ),
      )
      tail.clear()
      discarding = over
      if byte == (10).to_byte() {
        line += 1
        discarding = false
      }
      if line > 1000000000 || records.length() > 4096 {
        raise InputError("step line or record quota exceeded")
      }
    }
  }
  if close && !tail.is_empty() {
    records.push(
      physical_record(
        { ..state, line, },
        tail.copy(),
        offset - tail.length().to_double(),
        offset,
        true,
        discarding,
      ),
    )
    tail.clear()
    discarding = false
  }
  if close {
    discarding = false
  }
  let next : StreamState = {
    ..state,
    offset,
    line,
    tail,
    discarding,
    closed: close,
  }
  let accounted = state.tail.length() + bytes.length() - tail.length()
  record([
    ("state", state_value(next)),
    ("records", Array(records)),
    ("received_bytes", Number(bytes.length().to_double())),
    ("emitted_bytes", Number(accounted.to_double())),
    ("pending_bytes", Number(tail.length().to_double())),
  ])
}

///|
fn apply_action(previous : Value, action : Value) -> Value raise {
  let kind = string(required(action, "type"))
  if previous == Null {
    if kind != "init" {
      raise InputError("first action must initialize a source")
    }
    return record([
      ("state", state_value(initial_state(action))),
      ("records", Array([])),
    ])
  }
  let state = read_state(previous)
  match kind {
    "append" => append_state(state, action)
    "seal" => {
      fields_only(action, ["type"])
      append_state(
        state,
        record([
          ("type", String("append")),
          ("offset", Number(state.offset)),
          ("hex", String("")),
          ("close", Bool(true)),
        ]),
      )
    }
    "rotate" => {
      fields_only(action, ["type", "identity", "kind"])
      let rotation = string(required(action, "kind"))
      let identity = identifier(required(action, "identity"))
      if !["rename", "truncate", "ambiguous"].contains(rotation) {
        raise InputError("unsupported source boundary")
      }
      if state.generation >= 1000000 {
        raise InputError("generation limit exceeded")
      }
      let closed_result = append_state(
        state,
        record([
          ("type", String("append")),
          ("offset", Number(state.offset)),
          ("hex", String("")),
          ("close", Bool(true)),
        ]),
      )
      let records = array(field(closed_result, "records"))
      records.push(
        record([
          ("kind", String("source_boundary")),
          ("source", String(state.source)),
          ("generation", Number(state.generation.to_double())),
          ("reason", String(rotation)),
          ("loss_possible", Bool(rotation != "rename")),
        ]),
      )
      record([
        (
          "state",
          state_value({
            ..state,
            identity,
            generation: state.generation + 1,
            offset: 0,
            line: 0,
            tail: [],
            discarding: false,
            closed: false,
          }),
        ),
        ("records", Array(records)),
      ])
    }
    _ => raise InputError("unsupported source action: " + kind)
  }
}
