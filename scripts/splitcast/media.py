#!/usr/bin/env python3
"""Synthetic generated media only. Real FFmpeg -> localhost MediaMTX -> FFmpeg.

No live devices, OBS, deployment, user processes, or public listeners. Software
x264/AAC encoding is used ONLY for explicitly synthetic generated media.
Default five start/stop cycles exercise RTMP game A/V plus RTSP/TCP mic/camera.
Then kill only the harness server, observe transport loss, restart, and receive
new packets. This is transport evidence, never an A01-A15 acceptance pass.

--seconds 605/1805 --cycles 1 can collect synthetic 10/30 minute marker evidence.
Short transmission and long synchronization results are reported separately.
Temporary recordings/logs are removed. Only compact nonprivate JSON persists.
RTSP receivers use FFmpeg +genpts for initially unset PTS. Output packet PTS/DTS
must still pass strict checks. This remuxing does not prove a capture clock.
"""

import argparse
from array import array
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time

from perf import EvidenceError, require, save, version


BASE = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin", "-y"]
FEEDS = {"game": ("rtmp", {"video", "audio"}),
         "mic": ("rtsp", {"audio"}), "camera": ("rtsp", {"video"})}
CONFIG_SOURCE = "https://raw.githubusercontent.com/bluenviron/mediamtx/v1.18.2/mediamtx.yml"


def execute(argv, timeout=30, binary=False):
    result = subprocess.run(argv, capture_output=True, text=not binary, timeout=timeout)
    require(result.returncode == 0, f"{Path(argv[0]).name} failed with exit {result.returncode}")
    return result.stdout


def probe(path, packets=False, frames=False):
    cmd = ["ffprobe", "-v", "error", "-of", "json", "-show_streams", "-show_format"]
    if packets:
        cmd += ["-show_packets", "-show_entries", "packet=stream_index,pts_time,dts_time,duration_time,size:stream=index,codec_type,codec_name,start_time:format=duration"]
    if frames:
        cmd += ["-select_streams", "v:0", "-show_frames", "-show_entries", "frame=best_effort_timestamp_time:stream=index,codec_type,codec_name,start_time:format=duration"]
    return json.loads(execute(cmd + [str(path)], timeout=60))


class Children:
    def __init__(self, directory):
        self.directory = directory
        self.children = []
        self.logs = []

    def start(self, argv, name):
        log = (self.directory / f"{len(self.children)}-{name}.log").open("wb")
        self.logs.append(log)
        # MTX_* is an implicit configuration channel. Do not inherit it.
        env = {k: v for k, v in os.environ.items() if not k.startswith("MTX_")}
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                start_new_session=True, env=env)
        self.children.append(proc)
        return proc

    def stop(self, proc, sig=signal.SIGTERM):
        if proc.poll() is None:
            os.killpg(proc.pid, sig)
            try:
                proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=4)

    def clean(self):
        for proc in reversed(self.children):
            self.stop(proc)
        for log in self.logs:
            log.close()
        require(all(p.poll() is not None for p in self.children), "unreaped harness child")


def free_ports():
    sockets = [socket.socket() for _ in range(2)]
    try:
        for sock in sockets:
            sock.bind(("127.0.0.1", 0))
        return [sock.getsockname()[1] for sock in sockets]
    finally:
        for sock in sockets:
            sock.close()


def config(rtsp_port, rtmp_port):
    return f"""logLevel: info
logDestinations: [stdout]
readTimeout: 3s
writeTimeout: 3s
writeQueueSize: 128
rtsp: true
rtspAddress: 127.0.0.1:{rtsp_port}
rtspTransports: [tcp]
rtspEncryption: "no"
rtmp: true
rtmpAddress: 127.0.0.1:{rtmp_port}
rtmpEncryption: "no"
webrtc: false
hls: false
srt: false
api: false
metrics: false
pprof: false
playback: false
authInternalUsers:
- user: any
  pass:
  ips: ['127.0.0.1']
  permissions:
  - action: publish
  - action: read
pathDefaults:
  source: publisher
  overridePublisher: false
  record: false
paths:
  game:
  mic:
  camera:
"""


def listener_sockets(pid):
    inodes = set()
    for fd in Path(f"/proc/{pid}/fd").iterdir():
        try:
            target = fd.readlink().as_posix()
        except FileNotFoundError:
            continue
        if target.startswith("socket:["):
            inodes.add(target[8:-1])
    result = []
    for proto in ("tcp", "tcp6", "udp", "udp6"):
        for line in Path(f"/proc/{pid}/net/{proto}").read_text().splitlines()[1:]:
            fields = line.split()
            if fields[9] not in inodes:
                continue
            if proto.startswith("tcp") and fields[3] != "0A":
                continue
            address, port = fields[1].split(":")
            result.append({"protocol": proto, "address_hex": address, "port": int(port, 16)})
    return sorted(result, key=lambda item: item["port"])


def wait_server(proc, ports):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        require(proc.poll() is None, "MediaMTX exited during config validation/startup")
        listeners = listener_sockets(proc.pid)
        if len(listeners) == 2:
            require({x["port"] for x in listeners} == set(ports), "unexpected MediaMTX listener")
            require(all(x["protocol"] == "tcp" and x["address_hex"] == "0100007F" for x in listeners), "non-loopback/TCP MediaMTX listener")
            return listeners
        time.sleep(0.1)
    raise EvidenceError("MediaMTX readiness timeout")


def generate(directory, seconds):
    video = "testsrc2=size=320x180:rate=60,drawbox=x=0:y=0:w=64:h=64:color=black:t=fill,drawbox=x=0:y=0:w=64:h=64:color=white:t=fill:enable='lt(mod(t,2),0.1)'"
    audio = "aevalsrc=if(lt(mod(t\\,2)\\,0.1)\\,0.8*sin(2*PI*1000*t)\\,0):s=48000"
    path = directory / "generated-game.mp4"
    execute(BASE + ["-f", "lavfi", "-i", video, "-f", "lavfi", "-i", audio,
                    "-t", str(seconds + 30), "-c:v", "libx264", "-threads", "1", "-preset", "ultrafast",
                    "-tune", "zerolatency", "-g", "60", "-bf", "0", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "128k", str(path)], timeout=120)
    return path


def url(feed, ports):
    proto = FEEDS[feed][0]
    return f"{proto}://127.0.0.1:{ports[1] if proto == 'rtmp' else ports[0]}/{feed}"


def sender(source, feed, ports):
    cmd = BASE + ["-re", "-i", str(source)]
    if feed == "game":
        cmd += ["-map", "0:v:0", "-map", "0:a:0"]
    elif feed == "mic":
        cmd += ["-map", "0:a:0", "-vn"]
    else:
        cmd += ["-map", "0:v:0", "-an"]
    cmd += ["-c", "copy"]
    if FEEDS[feed][0] == "rtsp":
        cmd += ["-f", "rtsp", "-rtsp_transport", "tcp"]
    else:
        cmd += ["-f", "flv", "-flvflags", "no_duration_filesize"]
    return cmd + [url(feed, ports)]


def receiver(feed, ports, path, seconds):
    cmd = BASE + ["-analyzeduration", "1000000", "-probesize", "1000000"]
    if FEEDS[feed][0] == "rtsp":
        cmd += ["-fflags", "+genpts", "-rtsp_transport", "tcp", "-timeout", "5000000"]
    else:
        cmd += ["-rw_timeout", "5000000"]
    return cmd + ["-i", url(feed, ports), "-t", str(seconds), "-map", "0", "-c", "copy", str(path)]


def wait_publication(feed, ports, processes):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        require(all(p.poll() is None for p in processes), "synthetic sender/server exited before ready")
        try:
            cmd = ["ffprobe", "-v", "error", "-analyzeduration", "100000", "-probesize", "100000"]
            if FEEDS[feed][0] == "rtsp":
                cmd += ["-rtsp_transport", "tcp", "-timeout", "1500000"]
            else:
                cmd += ["-rw_timeout", "1500000"]
            value = json.loads(execute(cmd + ["-show_streams", "-of", "json", url(feed, ports)], timeout=3))
            if {s["codec_type"] for s in value["streams"]} == FEEDS[feed][1]:
                return
        except (EvidenceError, subprocess.TimeoutExpired):
            pass
        time.sleep(0.1)
    raise EvidenceError(f"publication readiness timeout for {feed}")


def packet_evidence(data, expected):
    streams = data["streams"]
    require({s["codec_type"] for s in streams} == expected, "missing/unexpected media stream")
    result = {}
    for stream in streams:
        packets = [p for p in data["packets"] if p["stream_index"] == stream["index"]]
        require(len(packets) >= 10, "missing media packets")
        require(all("pts_time" in p and "dts_time" in p and int(p["size"]) > 0 for p in packets), "missing packet timestamps/payload")
        pts = [float(p["pts_time"]) for p in packets]
        dts = [float(p["dts_time"]) for p in packets]
        require(all(math.isfinite(t) for t in pts + dts), "invalid media timestamp")
        bad = [(a, b) for a, b in zip(pts, pts[1:]) if b <= a]
        require(not bad, f"non-monotonic {stream['codec_type']} media PTS: {bad[:5]}")
        require(all(b >= a for a, b in zip(dts, dts[1:])), "non-monotonic media DTS")
        result[stream["codec_type"]] = {
            "codec": stream["codec_name"], "packets": len(packets),
            "bytes": sum(int(p["size"]) for p in packets), "first_pts_s": pts[0], "last_pts_s": pts[-1],
            "span_s": pts[-1] - pts[0], "max_pts_gap_s": max(b - a for a, b in zip(pts, pts[1:])),
        }
    return result


def rising_edges(values, threshold, seconds_per_sample, origin=0, quiet=0.5):
    edges, last_active = [], -math.inf
    for i, value in enumerate(values):
        if abs(value) >= threshold:
            now = origin + i * seconds_per_sample
            if now - last_active >= quiet:
                edges.append(now)
            last_active = now
    return edges


def sync_evidence(video, audio):
    require(len(video) >= 2 and len(audio) >= 2, "missing decoded sync markers")
    pairs = []
    for v in video:
        a = min(audio, key=lambda t: abs(t - v))
        if abs(a - v) <= 0.5:
            pairs.append((v, a, (a - v) * 1000))
    require(len(pairs) >= 2, "missing matching sync markers")
    errors = [p[2] for p in pairs]
    span = pairs[-1][0] - pairs[0][0]
    return {"method": "decoded white square and 1kHz pulse rising edges on recorded PTS",
            "pairs": len(pairs), "first_video_s": pairs[0][0], "last_video_s": pairs[-1][0],
            "marker_span_s": span, "first_audio_minus_video_ms": errors[0],
            "last_audio_minus_video_ms": errors[-1], "median_audio_minus_video_ms": statistics.median(errors),
            "max_abs_offset_ms": max(abs(x) for x in errors), "first_to_last_drift_ms": errors[-1] - errors[0],
            "within_20ms": all(abs(x) <= 20 for x in errors),
            "synthetic_10min_sync": "MEASURED" if span >= 600 else "NOT_RUN",
            "synthetic_30min_sync": "MEASURED" if span >= 1800 else "NOT_RUN",
            "cross_feed_sync": "NOT_MEASURED; independent feeds do not share a proven capture clock"}


def video_markers(path):
    info = probe(path, frames=True)
    timestamps = [float(f["best_effort_timestamp_time"]) for f in info["frames"]]
    pixels = execute(BASE + ["-i", str(path), "-map", "0:v:0", "-vf", "crop=32:32:0:0,scale=1:1,format=gray",
                            "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"], timeout=120, binary=True)
    require(len(pixels) == len(timestamps), "marker decoder frame count mismatch")
    video_edges, active = [], False
    for pixel, timestamp in zip(pixels, timestamps):
        if pixel > 180 and not active:
            video_edges.append(timestamp)
        active = pixel > 180
    return video_edges


def audio_markers(path):
    # The frame probe selects video. Query audio start PTS separately.
    audio_stream = next(s for s in probe(path)["streams"] if s["codec_type"] == "audio")
    pcm = execute(BASE + ["-i", str(path), "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-f", "s16le", "pipe:1"], timeout=120, binary=True)
    values = array("h")
    values.frombytes(pcm)
    if sys.byteorder != "little":
        values.byteswap()
    return rising_edges(values, 8000, 1 / 48000, float(audio_stream["start_time"]))


def analyze_markers(path):
    return sync_evidence(video_markers(path), audio_markers(path))


def round_trip(children, source, ports, seconds, tag):
    senders = [children.start(sender(source, feed, ports), f"{tag}-{feed}-send") for feed in FEEDS]
    for feed in FEEDS:
        wait_publication(feed, ports, senders)
    outputs = {feed: children.directory / f"{tag}-{feed}.mkv" for feed in FEEDS}
    receivers = [children.start(receiver(feed, ports, outputs[feed], seconds), f"{tag}-{feed}-receive") for feed in FEEDS]
    deadline = time.monotonic() + seconds + 20
    while any(p.poll() is None for p in receivers) and time.monotonic() < deadline:
        require(all(p.poll() is None for p in senders), "sender exited during media transmission")
        time.sleep(0.1)
    if not all(p.poll() == 0 for p in receivers):
        logs = [Path(children.logs[children.children.index(p)].name).read_text()[-2000:] for p in receivers]
        raise EvidenceError("receiver failed or exceeded bounded timeout: " + repr(logs))
    for proc in senders:
        children.stop(proc)
    result = {}
    for feed, output in outputs.items():
        packet_data = probe(output, packets=True)
        try:
            evidence = packet_evidence(packet_data, FEEDS[feed][1])
        except EvidenceError as exc:
            reader = receivers[list(FEEDS).index(feed)]
            log = Path(children.logs[children.children.index(reader)].name).read_text()[-2000:]
            raise EvidenceError(f"{tag}/{feed}: {exc}; receiver diagnostic: {log}") from exc
        require(all(s["span_s"] >= seconds - 1 for s in evidence.values()), "short recording/missing media")
        require(all(s["max_pts_gap_s"] < 0.2 for s in evidence.values()), "media packet gap")
        result[feed] = {"transport": "RTMP/TCP" if feed == "game" else "RTSP interleaved TCP",
                        "streams": evidence,
                        "timestamp_policy": "FFmpeg +genpts for RTSP remuxing; output PTS strictly increasing" if feed != "game" else "combined game A/V timestamps preserved through remuxing"}
    result["game_markers"] = analyze_markers(outputs["game"])
    mic, camera = audio_markers(outputs["mic"]), video_markers(outputs["camera"])
    require(len(mic) >= 2 and len(camera) >= 2, "missing separate mic/camera decoded markers")
    result["separate_feed_markers"] = {"mic_pulses": len(mic), "camera_flashes": len(camera),
                                       "sync_verdict": "NOT_MEASURED; independent playback timelines"}
    result["children_stopped"] = all(p.poll() is not None for p in senders + receivers)
    return result


def fault_test(children, source, ports, server):
    publisher = children.start(sender(source, "game", ports), "fault-send")
    wait_publication("game", ports, [publisher, server])
    output = children.directory / "fault-partial.mkv"
    reader = children.start(receiver("game", ports, output, 60), "fault-receive")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if output.exists() and output.stat().st_size > 4096:
            break
        require(reader.poll() is None, "fault reader failed before injection")
        time.sleep(0.1)
    require(output.exists() and output.stat().st_size > 4096, "no media before fault injection")
    start = time.monotonic()
    children.stop(server, signal.SIGKILL)
    for proc in (reader, publisher):
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            raise EvidenceError("transport did not terminate within 8s after harness server loss")
    partial = packet_evidence(probe(output, packets=True), {"video", "audio"})
    require(partial["video"]["span_s"] < 60, "loss injection did not truncate media")
    return {"fault": "SIGKILL owned MediaMTX server; real TCP transport loss, not packet-loss emulation",
            "bounded_exit_s": time.monotonic() - start,
            "publisher_exit_code": publisher.returncode, "reader_exit_code": reader.returncode,
            "partial_game_streams": partial, "recovery": "explicit bounded restart by harness, not application auto-reconnect"}


def run(args):
    require(5 <= args.seconds <= 1810 and 1 <= args.cycles <= 10, "seconds must be 5..1810 and cycles 1..10")
    report = {"schema": 1, "kind": "synthetic_real_network_media", "status": "FAIL",
              "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
              "base_revision": "3cf330792d31df0721289d91e5643aa5fdee8f77",
              "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "command": ["python3", "scripts/splitcast/media.py", "--seconds", str(args.seconds), "--cycles", str(args.cycles), "--output", args.output],
              "software_encoding": "ONLY synthetic lavfi-generated source; libx264 and AAC",
              "versions": {"ffmpeg": version(["ffmpeg", "-version"]), "ffprobe": version(["ffprobe", "-version"]),
                           "mediamtx": version(["mediamtx", "--version"])},
              "acceptance": {f"A{i:02}": "NOT_RUN; synthetic transport evidence is not hardware/application acceptance" for i in range(1, 16)},
              "config_reference": CONFIG_SOURCE, "cycles": [], "requested_seconds_per_cycle": args.seconds,
              "long_sync": "NOT_RUN"}
    save(args.output, report)
    children = None
    try:
        require(report["versions"]["mediamtx"] == "v1.18.2", "only actual inspected MediaMTX v1.18.2 config supported; inspect new version before adapting")
        help_commands = {"rtsp_input": ["ffmpeg", "-hide_banner", "-h", "demuxer=rtsp"],
                         "rtsp_output": ["ffmpeg", "-hide_banner", "-h", "muxer=rtsp"],
                         "rtmp_container": ["ffmpeg", "-hide_banner", "-h", "muxer=flv"],
                         "mediamtx_cli": ["mediamtx", "--help"]}
        report["inspected_help_sha256"] = {key: hashlib.sha256(execute(cmd).encode()).hexdigest() for key, cmd in help_commands.items()}
        with tempfile.TemporaryDirectory(prefix="splitcast-synthetic-") as temporary:
            directory = Path(temporary)
            children = Children(directory)
            try:
                source = generate(directory, args.seconds)
                ports = free_ports()
                conf = directory / "mediamtx.yml"
                text = config(*ports)
                conf.write_text(text)
                report["config_sha256"] = hashlib.sha256(text.encode()).hexdigest()
                report["disabled_listeners"] = ["webrtc", "hls", "srt", "api", "metrics", "pprof", "playback"]
                report["moq"] = "not implemented in inspected MediaMTX v1.18.2; actual socket audit requires only two loopback TCP listeners"
                server = children.start(["mediamtx", str(conf)], "server")
                report["listeners"] = wait_server(server, ports)
                for cycle in range(args.cycles):
                    result = round_trip(children, source, ports, args.seconds, f"cycle-{cycle + 1}")
                    report["cycles"].append(result)
                    require(len([p for p in children.children if p.poll() is None]) == 1, "duplicate/residual media child after stop")
                report["loss"] = fault_test(children, source, ports, server)
                require(all(p.poll() is not None for p in children.children), "child survived fault cycle")
                server = children.start(["mediamtx", str(conf)], "restarted-server")
                wait_server(server, ports)
                report["after_restart"] = round_trip(children, source, ports, 6, "recovered")
                report["start_stop_5x"] = "PASS" if args.cycles >= 5 else "NOT_RUN"
                markers = report["cycles"][0]["game_markers"]
                report["long_sync"] = {k: markers[k] for k in ("synthetic_10min_sync", "synthetic_30min_sync")}
                report["short_media_transmission"] = "PASS"
                report["status"] = "PASS"
            finally:
                children.clean()
                for port in ports if "ports" in locals() else []:
                    with socket.socket() as sock:
                        sock.settimeout(0.2)
                        require(sock.connect_ex(("127.0.0.1", port)) != 0, "harness listener survived cleanup")
                report["cleanup"] = {"all_owned_children_reaped": all(p.poll() is not None for p in children.children),
                                     "owned_child_count": len(children.children), "temporary_media_removed": True,
                                     "listeners_closed": True}
    except (EvidenceError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
        report["status"] = "FAIL"
        report["reason"] = str(exc)
    finally:
        save(args.output, report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seconds", type=float, default=8)
    parser.add_argument("--cycles", type=int, default=5)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    def interrupted(signum, frame):
        raise EvidenceError(f"interrupted by signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    result = run(args)
    print(json.dumps({k: result[k] for k in ("status", "kind", "versions")} | {"output": args.output, "reason": result.get("reason")}))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
