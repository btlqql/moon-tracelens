///|
test "split UTF8 bytes and CRLF remain pending until a complete line" {
  let init=apply_action(Null,from_json({"type":"init","source":"a","identity":"dev:inode"}))
  let a=apply_action(field(init,"state"),from_json({"type":"append","offset":0,"hex":"e4b8"}))
  assert_eq(field(a,"pending_bytes"),Number(2))
  let b=apply_action(field(a,"state"),from_json({"type":"append","offset":2,"hex":"ad0d0a"}))
  assert_eq(field(b,"pending_bytes"),Number(0))
  let records=array(field(b,"records"))
  assert_eq(field(records[0],"text"),String("中"))
  assert_eq(field(records[0],"start"),Number(0))
  assert_eq(field(records[0],"end"),Number(5))
}

///|
test "truncation seals old bytes and changes generation" {
  let init=apply_action(Null,from_json({"type":"init","source":"a","identity":"same"}))
  let a=apply_action(field(init,"state"),from_json({"type":"append","offset":0,"hex":"61"}))
  let b=apply_action(field(a,"state"),from_json({"type":"rotate","identity":"same","kind":"truncate"}))
  assert_eq(field(field(b,"state"),"generation"),Number(1))
  assert_eq(field(field(b,"state"),"offset"),Number(0))
  assert_eq(field(array(field(b,"records"))[1],"loss_possible"),Bool(true))
}

///|
test "committed batches replay and orphan batches are not promoted" {
  let init=prepare(Null,[],from_json({"type":"init","source":"a","identity":"i"}))
  let batch=field(init,"batch");let manifest=field(init,"manifest")
  let append=prepare(manifest,[batch],from_json({"type":"append","offset":0,"hex":"610a"}))
  let report=recover(manifest,[batch,field(append,"batch")])
  assert_eq(field(field(report,"state"),"offset"),Number(0))
  assert_eq(array(field(report,"orphan_hashes")).length(),1)
  let next=recover(field(append,"manifest"),[batch,field(append,"batch")])
  assert_eq(field(field(next,"state"),"offset"),Number(2))
}
