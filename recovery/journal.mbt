///|
fn digest(value : Value) -> String {
  let d = @sha256.Digest::new()
  for byte in @utf8.encode(value.canonical()[:]) {
    d.write(byte)
  }
  d.check_sum()
}

///|
fn hash_name(value : Value) -> String raise InputError {
  let name = string(value)
  if name.length() != 64 {
    raise InputError("invalid journal hash")
  }
  for c in name {
    if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
      raise InputError("invalid journal hash")
    }
  }
  name
}

///|
fn recover(manifest : Value, batches : Array[Value]) -> Value raise {
  if batches.length() > 256 {
    raise InputError("journal exceeds 256 batches")
  }
  let indexed : Map[String, Value] = Map([])
  for batch in batches {
    let hash = hash_name(required(batch, "hash"))
    if indexed.contains(hash) {
      raise InputError("duplicate journal hash")
    }
    indexed[hash] = batch
  }
  let chain : Array[Value] = []
  let used : Map[String, Bool] = Map([])
  let mut head : Value = Null
  let mut revision = 0
  if manifest != Null {
    fields_only(manifest, ["schema", "revision", "head"])
    if required(manifest, "schema") != Number(1) {
      raise InputError("unsupported manifest schema")
    }
    revision = small_int(required(manifest, "revision"), 256)
    if revision < 1 {
      raise InputError("manifest revision must be positive")
    }
    head = String(hash_name(required(manifest, "head")))
    let mut current = head
    while current != Null {
      let key = hash_name(current)
      if used.contains(key) {
        raise InputError("journal cycle")
      }
      used[key] = true
      let batch = match indexed.get(key) {
        Some(b) => b
        None => raise InputError("store_corrupt: committed batch missing")
      }
      fields_only(batch, [
        "schema", "revision", "previous", "action", "state", "records", "hash",
      ])
      if required(batch, "schema") != Number(1) {
        raise InputError("unsupported batch schema")
      }
      let unsigned = object(batch).copy()
      ignore(unsigned.remove("hash"))
      if digest(Object(unsigned)) != key {
        raise InputError("store_corrupt: batch checksum mismatch")
      }
      chain.push(batch)
      current = required(batch, "previous")
      if chain.length() > 256 {
        raise InputError("journal chain limit")
      }
    }
  }
  if chain.length() != revision {
    raise InputError("store_corrupt: revision and chain length disagree")
  }
  let records : Array[Value] = []
  let mut state : Value = Null
  let mut expected : Value = Null
  let mut total_bytes = 0
  for i in 0..<chain.length() {
    let batch = chain[chain.length() - 1 - i]
    if required(batch, "revision") != Number((i + 1).to_double()) ||
      field(batch, "previous") != expected {
      raise InputError("store_corrupt: noncontiguous revisions")
    }
    let action = required(batch, "action")
    let applied = apply_action(state, action)
    if required(batch, "state") != field(applied, "state") ||
      required(batch, "records") != field(applied, "records") {
      raise InputError(
        "store_corrupt: checkpoint does not replay from prior action",
      )
    }
    if field(action, "type") == String("append") {
      total_bytes += bytes_hex(field(action, "hex")).length()
    }
    if total_bytes > 4194304 {
      raise InputError("journal source byte quota exceeded")
    }
    for record in array(field(applied, "records")) {
      records.push(record)
    }
    state = field(applied, "state")
    expected = field(batch, "hash")
  }
  let orphan : Array[String] = []
  for key, _ in indexed {
    if !used.contains(key) {
      orphan.push(key)
    }
  }
  orphan.sort_by(lexical_compare)
  record([
    ("state", state),
    ("records", Array(records)),
    ("revision", Number(revision.to_double())),
    ("head", head),
    ("orphan_hashes", strings(orphan)),
    ("source_bytes", Number(total_bytes.to_double())),
  ])
}

///|
fn prepare(
  manifest : Value,
  batches : Array[Value],
  action : Value,
) -> Value raise {
  let current = recover(manifest, batches)
  let revision = small_int(field(current, "revision"), 256)
  if revision >= 256 {
    raise InputError("journal revision quota reached; create a new store")
  }
  let outcome = apply_action(field(current, "state"), action)
  let extra = if field(action, "type") == String("append") {
    bytes_hex(field(action, "hex")).length()
  } else {
    0
  }
  let total = ordinal(field(current, "source_bytes")) + extra.to_double()
  if total > 4194304 {
    raise InputError("journal source byte quota exceeded")
  }
  let batch = object(
    record([
      ("schema", Number(1)),
      ("revision", Number((revision + 1).to_double())),
      ("previous", field(current, "head")),
      ("action", action),
      ("state", field(outcome, "state")),
      ("records", field(outcome, "records")),
    ]),
  )
  let hash = digest(Object(batch))
  batch["hash"] = String(hash)
  let next = record([
    ("schema", Number(1)),
    ("revision", Number((revision + 1).to_double())),
    ("head", String(hash)),
  ])
  record([
    ("batch", Object(batch)),
    ("manifest", next),
    ("expected_head", field(current, "head")),
    (
      "actions",
      strings([
        "write_batch", "sync_batch", "sync_batch_directory", "write_manifest", "sync_manifest",
        "rename_manifest", "sync_store_directory",
      ]),
    ),
    ("state", field(outcome, "state")),
    ("records", field(outcome, "records")),
  ])
}

///|
pub fn execute(request : Json) -> Json raise {
  let r = from_json(request)
  let operation = string(required(r, "operation"))
  let result = match operation {
    "stream_apply" => {
      fields_only(r, ["operation", "state", "action"])
      apply_action(required(r, "state"), required(r, "action"))
    }
    "stream_plan" => {
      fields_only(r, ["operation", "manifest", "batches", "action"])
      prepare(
        required(r, "manifest"),
        array(required(r, "batches")),
        required(r, "action"),
      )
    }
    "stream_recover" => {
      fields_only(r, ["operation", "manifest", "batches"])
      recover(required(r, "manifest"), array(required(r, "batches")))
    }
    _ => raise InputError("unsupported recovery operation")
  }
  result.to_json()
}
