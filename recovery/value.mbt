///|
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[Value])
  Object(Map[String, Value])
} derive(Eq, @debug.Debug)

///|
pub fn from_json(value : Json) -> Value {
  match value {
    Json::Null => Null
    Json::True => Bool(true)
    Json::False => Bool(false)
    Json::Number(n, ..) => Number(n)
    Json::String(s) => String(s)
    Json::Array(items) => Array(items.map(from_json))
    Json::Object(fields) => Object(fields.map(fn(_, v) { from_json(v) }))
  }
}

///|
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Number(n) => Json::number(n)
    String(s) => Json::string(s)
    Array(items) => Json::array(items.map(fn(v) { v.to_json() }))
    Object(fields) => Json::object(fields.map(fn(_, v) { v.to_json() }))
  }
}

///|
pub fn Value::canonical(self : Value) -> String {
  match self {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort_by(lexical_compare)
      "{" +
      keys
      .map(fn(k) {
        String(k).to_json().stringify() + ":" + fields[k].canonical()
      })
      .join(",") +
      "}"
    }
    Array(items) => "[" + items.map(fn(v) { v.canonical() }).join(",") + "]"
    _ => self.to_json().stringify()
  }
}

///|
fn lexical_compare(left : String, right : String) -> Int32 {
  let a = left.to_array()
  let b = right.to_array()
  let size = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<size {
    if a[i] < b[i] {
      return -1
    }
    if a[i] > b[i] {
      return 1
    }
  }
  a.length() - b.length()
}

///|
pub(all) suberror InputError {
  InputError(String)
} derive(@debug.Debug)

///|
fn object(value : Value) -> Map[String, Value] raise InputError {
  match value {
    Object(v) => v
    _ => raise InputError("expected object")
  }
}

///|
fn array(value : Value) -> Array[Value] raise InputError {
  match value {
    Array(v) => v
    _ => raise InputError("expected array")
  }
}

///|
fn string(value : Value) -> String raise InputError {
  match value {
    String(v) => v
    _ => raise InputError("expected string")
  }
}

///|
fn field(value : Value, key : String) -> Value {
  match value {
    Object(v) => v.get(key).unwrap_or(Null)
    _ => Null
  }
}

///|
fn has(value : Value, key : String) -> Bool {
  match value {
    Object(v) => v.contains(key)
    _ => false
  }
}

///|
fn required(value : Value, key : String) -> Value raise InputError {
  if !has(value, key) {
    raise InputError("missing field: " + key)
  }
  field(value, key)
}

///|
fn fields_only(
  value : Value,
  allowed : Array[String],
) -> Unit raise InputError {
  for key, _ in object(value) {
    if !allowed.contains(key) {
      raise InputError("unknown field: " + key)
    }
  }
}

///|
fn record(items : Array[(String, Value)]) -> Value {
  let result : Map[String, Value] = Map([])
  for (key, value) in items {
    result[key] = value
  }
  Object(result)
}

///|
fn strings(items : Array[String]) -> Value {
  Array(items.map(fn(s) { String(s) }))
}

///|
fn identifier(value : Value) -> String raise InputError {
  let result = string(value)
  if result.is_empty() || result.length() > 256 {
    raise InputError("identifier length must be 1..256")
  }
  result
}

///|
fn ordinal(value : Value) -> Double raise InputError {
  match value {
    Number(n) if !n.is_nan() &&
      !n.is_inf() &&
      n >= 0.0 &&
      n <= 9007199254740991.0 &&
      n.trunc() == n => n
    _ =>
      raise InputError(
        "event ordinal must be an exact nonnegative JSON integer",
      )
  }
}

///|
fn limit(
  value : Value,
  key : String,
  fallback : Int32,
  maximum : Int32,
) -> Int32 raise InputError {
  if !has(value, key) {
    return fallback
  }
  let n = ordinal(field(value, key))
  if n < 1.0 || n > maximum.to_double() {
    raise InputError("budget out of range: " + key)
  }
  n.to_int()
}

///|
fn validate_value(
  value : Value,
  depth : Int32,
  nodes : Ref[Int32],
) -> Unit raise InputError {
  nodes.val += 1
  if depth > 32 || nodes.val > 20000 {
    raise InputError("model data exceeds depth or node budget")
  }
  match value {
    Number(n) =>
      if n.is_nan() || n.is_inf() {
        raise InputError("non-finite model value")
      }
    Array(items) =>
      for item in items {
        validate_value(item, depth + 1, nodes)
      }
    Object(items) =>
      for _, item in items {
        validate_value(item, depth + 1, nodes)
      }
    String(s) =>
      if s.length() > 65536 {
        raise InputError("model string exceeds 65536 units")
      }
    _ => ()
  }
}
