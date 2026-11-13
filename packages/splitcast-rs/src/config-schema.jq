def valid($s):
  . as $v |
  (if $s.type == "object" then
    type == "object" and (keys == ($s.properties | keys)) and
    all($s.properties | keys[]; . as $k | $v[$k] | valid($s.properties[$k]))
  elif $s.type == "array" then
    type == "array" and length >= ($s.minItems // 0) and length <= ($s.maxItems // 100) and all(.[]; valid($s.items))
  elif $s.type == "string" then
    type == "string" and length <= ($s.maxLength // 4096) and (test("[\u0000\r\n]") | not) and
    (if $s.pattern then test($s.pattern) else true end)
  elif $s.type == "integer" then
    type == "number" and isinfinite == false and isnan == false and floor == . and (tostring | test("^-?(0|[1-9][0-9]*)$")) and
    (if $s.minimum != null then . >= $s.minimum and . <= $s.maximum else true end)
  elif $s.type == "boolean" then type == "boolean"
  else true end) and
  (if $s | has("const") then $v == $s.const else true end) and
  (if $s.enum then $s.enum | index($v) != null else true end);
def routes:
  {game:["game.av",["capture.gpu","transport.rtmp"],["local.headphones","obs.game"]],
   mic:["mic.raw",["transport.rtsp","remote.rnnoise"],["obs.mic"]],
   camera:["camera.selected",["camera.hardware","transport.rtsp"],["obs.camera"]],
   tts:["chat.text",["remote.voicevox","transport.http"],["local.tts"]],
   overlay:["overlay.text",["obs.text"],["obs.overlay"]]};
valid($schema) and
(. as $c |
  ([.routes[].id] | sort) == (routes | keys) and
  all(.routes[]; . as $r | (routes[$r.id]) as $spec |
    $r.source == $spec[0] and $r.processors == $spec[1] and
    $r.targets == ($spec[2] + (if $r.id == "tts" and $c.tts.mix_remote then ["obs.tts"] else [] end))) and
  all(.routes[]; if .id == "game" or .id == "mic" or .id == "overlay" then .enabled
    elif .id == "camera" then .enabled == $c.camera.enabled
    elif .id == "tts" then ($c.tts.enabled | not) or .enabled else false end) and
  (.tts.voicevox_url | test("^http://127\\.0\\.0\\.1(:[0-9]+)?/?$") and
    (capture("^http://127\\.0\\.0\\.1(?::(?<port>[0-9]+))?/?$").port as $p | $p == null or (($p | tonumber) >= 1 and ($p | tonumber) <= 65535))) and
  ([.peer.control_port,.peer.forward_control_port,.obs.websocket_port,.capture.rtmp_port,.capture.rtsp_port,.capture.api_port] | unique | length == 6) and
  (.capture.game_audio == "" or (.capture.game_audio | test("^app:[^|;\\r\\n]+$") and (ascii_downcase != "app:splitcast-tts"))) and
  ((.camera.enabled | not) or (.camera.device | startswith("/dev/v4l/by-id/"))))
