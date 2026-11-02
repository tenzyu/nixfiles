from __future__ import annotations

import argparse
import base64
import fcntl
import json
import os
import signal
import sys
import threading
from urllib.parse import quote

from .config import Config, Error, atomic_write, path, secret
from .net import request


def parser():
    p = argparse.ArgumentParser(prog="splitcast", description="Personal two-host capture and production control")
    p.add_argument("--config", required=True, help="version-1 JSON configuration; accepted before or after command")
    commands = p.add_subparsers(dest="command", required=True)
    commands.add_parser("agent", help="run the loopback agent and own its session children")
    commands.add_parser("ui", help="print a private browser bootstrap URL using this user's token file")
    for name in ("prepare", "stop", "status", "devices"):
        commands.add_parser(name)
    doctor = commands.add_parser("doctor")
    doctor.add_argument("--offline", action="store_true", help="probe this host without a running agent")
    start = commands.add_parser("start")
    start.add_argument("--output", choices=("recording", "twitch"), default="recording")
    routes = commands.add_parser("routes")
    routes.add_argument("--settings", help="JSON selections to atomically save while idle")
    mic = commands.add_parser("mic")
    mic.add_argument("action", choices=("mute", "unmute", "status"), nargs="?", default="status")
    tts = commands.add_parser("tts")
    tts.add_argument("action", choices=("on", "off", "mute", "unmute", "skip", "clear", "status"), nargs="?", default="status")
    say = commands.add_parser("say")
    say.add_argument("text")
    say.add_argument("--id")
    overlay = commands.add_parser("overlay")
    overlay.add_argument("text")
    for name in ("preview", "diagnostics"):
        item = commands.add_parser(name)
        item.add_argument("--output", help="write PNG or allowlisted JSON to this path")
    return p


def normalize(argv):
    out, config = [], []
    index = 0
    occurrences = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--":
            out.extend(argv[index:])
            break
        if arg == "--config":
            occurrences += 1
            if index + 1 >= len(argv):
                raise Error("--config requires a path")
            config += [arg, argv[index + 1]]
            index += 2
        elif arg.startswith("--config="):
            occurrences += 1
            config.append(arg)
            index += 1
        else:
            out.append(arg)
            index += 1
    if occurrences > 1:
        raise Error("Supply --config only once")
    return config + out


def serve(config):
    from .agent import Agent
    from .server import Server
    config.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(config.state_dir, 0o700)
    with (config.state_dir / "agent.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Error("An agent already owns this role's state directory") from None
        agent = Agent(config)
        try:
            server = Server(agent)
        except OSError:
            agent.close()
            raise Error("Control port is occupied; use the existing agent or choose another port") from None
        def stop(*args):
            threading.Thread(target=server.shutdown, daemon=True).start()
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        agent.monitor()
        try:
            server.serve_forever(poll_interval=.2)
        finally:
            server.server_close()
            agent.close()


def main(argv=None):
    os.umask(0o077)
    try:
        args = parser().parse_args(normalize(list(sys.argv[1:] if argv is None else argv)))
        config = Config.load(args.config)
        if args.command == "agent":
            serve(config)
            return 0
        if args.command == "ui":
            token = secret(config["peer"]["token_file"])
            print(f"http://127.0.0.1:{config['peer']['control_port']}/#token={quote(token, safe='')}")
            return 0
        data = vars(args).copy()
        for key in ("command", "config", "offline"):
            data.pop(key, None)
        destination = data.pop("output", None) if args.command in ("preview", "diagnostics") else None
        if args.command == "routes":
            value = data.pop("settings", None)
            if value is not None:
                try:
                    data["settings"] = json.loads(value)
                except ValueError:
                    raise Error("--settings must be JSON") from None
        if args.command == "say" and data.get("id") is None:
            data.pop("id")
        if getattr(args, "offline", False):
            from .media import doctor
            result = doctor(config)
        else:
            origin = f"http://127.0.0.1:{config['peer']['control_port']}"
            result = request(origin + "/api/command", data={"command": args.command, "args": data},
                             headers={"Authorization": "Bearer " + secret(config["peer"]["token_file"]), "Origin": origin},
                             timeout=min(180, config["peer"]["timeout_seconds"] * 8), limit=4 * 1024 * 1024, control=True)
        if args.command == "preview":
            image = result.get("image", "")
            prefix = "data:image/png;base64,"
            if not image.startswith(prefix):
                raise Error("OBS did not return a PNG preview")
            destination = path(destination) if destination else config.state_dir / "preview.png"
            atomic_write(destination, base64.b64decode(image[len(prefix):], validate=True))
            result = {"path": str(destination)}
        elif args.command == "diagnostics" and destination:
            atomic_write(path(destination), json.dumps(result, indent=2))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1 if args.command == "doctor" and not result.get("ok") else 0
    except Error as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
