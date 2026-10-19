extends RefCounted
# This envelope versions the adapter handshake, independently of gameplay bytes.
const VERSION := 1
const PROTOCOL := 1
const MAX_CODE := 65536

static func encode(data: Dictionary) -> String:
 return Marshalls.utf8_to_base64(JSON.stringify(data))

static func decode(code: String) -> Dictionary:
 var text = code.strip_edges()
 if text.is_empty() or text.length() > MAX_CODE or text.length() % 4 != 0: return {}
 var base64_pattern = RegEx.new()
 base64_pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
 if base64_pattern.search(text) == null: return {}
 var data = JSON.parse_string(Marshalls.base64_to_utf8(text))
 if not data is Dictionary: return {}
 if data.get("game") != "ember-coop" or data.get("version") != VERSION or data.get("protocol") != PROTOCOL: return {}
 if data.get("type") not in ["offer","answer"]: return {}
 if not data.get("session") is String or data.session.length() != 32 or not data.session.is_valid_hex_number(false): return {}
 if not data.get("sdp") is String or not data.sdp.begins_with("v=0") or data.sdp.length() > 32768: return {}
 if not data.get("ice") is Array or data.ice.is_empty() or data.ice.size() > 64: return {}
 for candidate in data.ice:
  if not candidate is Array or candidate.size() != 3: return {}
  if not candidate[0] is String or candidate[0].length() > 256: return {}
  # JSON numbers parse as floats; reject fractions before converting to int.
  if not (candidate[1] is float or candidate[1] is int): return {}
  if not is_finite(float(candidate[1])) or candidate[1] < 0 or candidate[1] > 65535 or candidate[1] != int(candidate[1]): return {}
  if not candidate[2] is String or not candidate[2].begins_with("candidate:") or candidate[2].length() > 4096: return {}
 return data
