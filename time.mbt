///|
fn decimal(source : String) -> Int raise InputError {
  if source == "" {
    raise InputError("empty decimal")
  }
  let mut value = 0
  for c in source {
    if c < '0' || c > '9' {
      raise InputError("invalid decimal")
    }
    value = value * 10 + c.to_int() - 48
  }
  value
}

///|
pub fn timestamp(value : Value) -> Double raise {
  if value is Number(n) {
    return num(Number(n))
  }
  let text = str(value)
  if text.length() < 20 {
    raise InputError("timestamp must be RFC3339")
  }
  let year = decimal(text.substring(start=0, end=4))
  let month = decimal(text.substring(start=5, end=7))
  let day = decimal(text.substring(start=8, end=10))
  let hour = decimal(text.substring(start=11, end=13))
  let minute = decimal(text.substring(start=14, end=16))
  let second = decimal(text.substring(start=17, end=19))
  if text[4] != 45 ||
    text[7] != 45 ||
    text[10] != 84 ||
    text[13] != 58 ||
    text[16] != 58 {
    raise InputError("invalid timestamp separators")
  }
  if year < 1 ||
    month < 1 ||
    month > 12 ||
    hour > 23 ||
    minute > 59 ||
    second > 59 {
    raise InputError("timestamp component out of range")
  }
  let lengths = [
    31,
    if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if day < 1 || day > lengths[month - 1] {
    raise InputError("invalid calendar day")
  }
  let adjusted = year - (if month <= 2 { 1 } else { 0 })
  let era = adjusted / 400
  let yoe = adjusted - era * 400
  let m = month + (if month > 2 { -3 } else { 9 })
  let doy = (153 * m + 2) / 5 + day - 1
  let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
  let mut pos = 19
  let mut fraction = 0.0
  if text[pos] == 46 {
    let start = pos
    pos += 1
    while pos < text.length() && text[pos] >= 48 && text[pos] <= 57 {
      pos += 1
    }
    if pos == start + 1 {
      raise InputError("empty timestamp fraction")
    }
    fraction = num(parse_value("0" + text.substring(start~, end=pos)))
  }
  let mut offset = 0
  let suffix = text.substring(start=pos)
  if suffix != "Z" {
    if suffix.length() != 6 ||
      (suffix[0] != 43 && suffix[0] != 45) ||
      suffix[3] != 58 {
      raise InputError("invalid timestamp timezone")
    }
    let h = decimal(suffix.substring(start=1, end=3))
    let m = decimal(suffix.substring(start=4, end=6))
    if h > 23 || m > 59 {
      raise InputError("timezone out of range")
    }
    offset = (h * 60 + m) * 60 * (if suffix[0] == 43 { 1 } else { -1 })
  }
  days.to_double() * 86400.0 +
  (hour * 3600 + minute * 60 + second - offset).to_double() +
  fraction
}
