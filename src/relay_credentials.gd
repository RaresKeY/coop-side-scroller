extends RefCounted
# Validate only the public issuer response. No account/master key belongs here.
const ENDPOINT := "https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/ice"

static func decode(body: PackedByteArray, unix_now: float) -> Dictionary:
 if body.size() > 65536: return {}
 var payload = JSON.parse_string(body.get_string_from_utf8())
 if not payload is Dictionary or payload.get("version") != 1: return {}
 var expiry = payload.get("expiresAt")
 if not (expiry is float or expiry is int) or not is_finite(float(expiry)) or expiry != int(expiry): return {}
 if expiry-unix_now < 60 or expiry-unix_now > 3700: return {}
 var servers = payload.get("iceServers")
 if not servers is Array or servers.is_empty() or servers.size()>16: return {}
 var pattern = RegEx.new()
 pattern.compile("^(stun|turn|turns):(?:stun|turn)\\.cloudflare\\.com:(3478|5349|443|80)(\\?transport=(udp|tcp))?$")
 var safe: Array = []
 var has_relay := false
 for entry in servers:
  if not entry is Dictionary or not entry.get("urls") is Array or entry.urls.is_empty() or entry.urls.size()>16: return {}
  var item = {"urls":[]}
  var relay := false
  for url in entry.urls:
   if not url is String or pattern.search(url)==null: return {}
   item.urls.append(url)
   if url.begins_with("turn"): relay = true
  if relay:
   if not entry.get("username") is String or not entry.get("credential") is String: return {}
   if entry.username.is_empty() or entry.credential.is_empty() or entry.username.length()>4096 or entry.credential.length()>4096: return {}
   item.username = entry.username
   item.credential = entry.credential
   has_relay = true
  safe.append(item)
 return {"iceServers":safe,"expiresAt":int(expiry)} if has_relay else {}
