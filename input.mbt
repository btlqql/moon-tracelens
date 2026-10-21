///|
pub(all) suberror InputError {
  InputError(String)
} derive(Show, Eq)

///|
fn get(value : Value, key : String) -> Value {
  match value {
    Object(obj) => obj.get(key).unwrap_or(Null)
    _ => Null
  }
}

///|
fn str(value : Value) -> String raise InputError {
  match value {
    String(s) => s
    _ => raise InputError("expected string")
  }
}

///|
fn arr(value : Value) -> Array[Value] raise InputError {
  match value {
    Array(items) => items
    _ => raise InputError("expected array")
  }
}

///|
fn obj(value : Value) -> Map[String, Value] raise InputError {
  match value {
    Object(fields) => fields
    _ => raise InputError("expected object")
  }
}

///|
fn num(value : Value) -> Double raise InputError {
  match value {
    Number(n) if !n.is_nan() && !n.is_inf() => n
    _ => raise InputError("expected finite number")
  }
}

///|
fn optional_str(value : Value, fallback : String) -> String raise InputError {
  match value {
    Null => fallback
    _ => str(value)
  }
}

///|
fn optional_num(value : Value, fallback : Double) -> Double raise InputError {
  match value {
    Null => fallback
    _ => num(value)
  }
}

///|
fn record(fields : Array[(String, Value)]) -> Value {
  let result : Map[String, Value] = {}
  for (key, value) in fields {
    result[key] = value
  }
  Object(result)
}

///|
fn canonical(value : Value) -> String {
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      "{" +
      keys
      .map(fn(k) { String(k).stringify() + ":" + canonical(fields[k]) })
      .join(",") +
      "}"
    }
    Array(items) => "[" + items.map(canonical).join(",") + "]"
    _ => value.stringify()
  }
}
