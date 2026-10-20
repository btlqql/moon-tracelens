
///|
test "recovery initialize" {
 let result=run(parse_value("{\"operation\":\"stream_apply\",\"state\":null,\"action\":{\"type\":\"init\",\"source\":\"demo\",\"identity\":\"inode1\"}}"))
assert_eq(test_at(result,["state"]),parse_value("{\"schema\":1,\"source\":\"demo\",\"identity\":\"inode1\",\"generation\":0,\"format\":\"jsonl\",\"max_line_bytes\":4096,\"offset\":0,\"line\":0,\"tail_hex\":\"\",\"discarding\":false,\"closed\":false}"))
assert_eq(test_at(result,["records"]),parse_value("[]"))
}

///|
test "recovery preserves pending bytes" {
 let result=run(parse_value("{\"operation\":\"stream_apply\",\"state\":{\"schema\":1,\"source\":\"demo\",\"identity\":\"inode1\",\"generation\":0,\"format\":\"jsonl\",\"max_line_bytes\":4096,\"offset\":0,\"line\":0,\"tail_hex\":\"\",\"discarding\":false,\"closed\":false},\"action\":{\"type\":\"append\",\"offset\":0,\"hex\":\"e4b8\"}}"))
assert_eq(test_at(result,["state", "tail_hex"]),parse_value("\"e4b8\""))
assert_eq(test_at(result,["state", "offset"]),parse_value("2"))
assert_eq(test_at(result,["records"]),parse_value("[]"))
}

///|
test "recovery quarantine invalid utf8" {
 let result=run(parse_value("{\"operation\":\"stream_apply\",\"state\":{\"schema\":1,\"source\":\"demo\",\"identity\":\"inode1\",\"generation\":0,\"format\":\"jsonl\",\"max_line_bytes\":4096,\"offset\":0,\"line\":0,\"tail_hex\":\"\",\"discarding\":false,\"closed\":false},\"action\":{\"type\":\"append\",\"offset\":0,\"hex\":\"ff0a\"}}"))
assert_eq(test_at(result,["state", "offset"]),parse_value("2"))
assert_eq(test_at(result,["records", "0", "kind"]),parse_value("\"quarantine\""))
assert_eq(test_at(result,["records", "0", "hex"]),parse_value("\"ff0a\""))
assert_eq(test_at(result,["records", "0", "reason"]),parse_value("\"invalid_utf8\""))
}

///|
test "recovery empty committed store" {
 let result=run(parse_value("{\"operation\":\"stream_recover\",\"manifest\":null,\"batches\":[]}"))
assert_eq(test_at(result,["revision"]),parse_value("0"))
assert_eq(test_at(result,["state"]),parse_value("null"))
assert_eq(test_at(result,["source_bytes"]),parse_value("0"))
}
