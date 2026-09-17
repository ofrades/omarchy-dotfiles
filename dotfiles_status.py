#!/usr/bin/env python3
"""Single-shot status helper for the omarchy-dotfiles bar widget.

Runs `mise bootstrap dotfiles status --json`, recent checkpoint history,
and `tailscale status --json`, then prints one JSON document for QML.

Never fails hard: every probe has a timeout and any failure is reported
inside the payload so the panel can show it instead of going blank.
"""

import json
import shutil
import subprocess
import sys


def command_output(command, timeout):
    try:
        completed = subprocess.run(
            command, check=False, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""
    return completed.returncode, (completed.stdout or "").strip()


def payload():
    mise_bin = shutil.which("mise")
    tailscale_bin = shutil.which("tailscale")

    data = {
        "ok": True,
        "mise": {"installed": mise_bin is not None, "version": ""},
        "files": [],
        "edits": [],
        "history": {
            "enabled": False,
            "trackedEntries": 0,
            "trackedFiles": 0,
            "checkpoints": 0,
            "latest": None,
            "watcher": "",
            "pendingOperations": 0,
        },
        "sync": {
            "origin": "",
            "branch": "",
            "mode": "",
            "pendingApplications": [],
            "conflicts": [],
            "lastError": "",
            "lastPublish": "",
            "lastFetch": "",
        },
        "activity": [],
        "tailscale": {
            "installed": tailscale_bin is not None,
            "running": False,
            "selfName": "",
            "selfIps": [],
            "peers": [],
        },
        "lastError": "",
    }

    if mise_bin:
        exit_code, out = command_output([mise_bin, "--version"], 5)
        if exit_code == 0:
            data["mise"]["version"] = out.splitlines()[0] if out else ""

        exit_code, out = command_output(
            [mise_bin, "bootstrap", "dotfiles", "status", "--json"], 15
        )
        if exit_code == 0 and out:
            try:
                status = json.loads(out)
            except json.JSONDecodeError:
                data["lastError"] = "Could not parse mise dotfiles status"
            else:
                for entry in status.get("files", []) or []:
                    data["files"].append(
                        {
                            "target": str(entry.get("target", "")),
                            "mode": str(entry.get("mode", "")),
                            "state": str(entry.get("state", "")),
                        }
                    )
                edits = status.get("edits", []) or []
                if isinstance(edits, list):
                    data["edits"] = [str(item) for item in edits]
                elif isinstance(edits, dict):
                    data["edits"] = [str(key) for key in edits.keys()]
                hist = status.get("history", {}) or {}
                data["history"]["enabled"] = hist.get("enabled") is True
                data["history"]["trackedEntries"] = int(hist.get("tracked_entries", 0) or 0)
                data["history"]["trackedFiles"] = int(hist.get("tracked_files", 0) or 0)
                data["history"]["checkpoints"] = int(hist.get("checkpoints", 0) or 0)
                latest = hist.get("latest") or None
                if isinstance(latest, dict):
                    data["history"]["latest"] = {
                        "id": latest.get("id"),
                        "createdAt": str(latest.get("created_at", "")),
                        "trigger": str(latest.get("trigger", "")),
                        "description": str(latest.get("description", "")),
                    }
                data["history"]["watcher"] = str(hist.get("watcher", "") or "")
                data["history"]["pendingOperations"] = int(
                    hist.get("pending_operations", 0) or 0
                )
                sync = hist.get("sync", {}) or {}
                data["sync"]["origin"] = str(sync.get("origin", "") or "")
                data["sync"]["branch"] = str(sync.get("branch", "") or "")
                data["sync"]["mode"] = str(sync.get("mode", "") or "")
                pending = sync.get("pending_applications", []) or []
                data["sync"]["pendingApplications"] = [str(item) for item in pending]
                conflicts = sync.get("conflicts", []) or []
                data["sync"]["conflicts"] = [str(item) for item in conflicts]
                data["sync"]["lastError"] = str(sync.get("last_error", "") or "")
                data["sync"]["lastPublish"] = str(sync.get("last_publish", "") or "")
                data["sync"]["lastFetch"] = str(sync.get("last_fetch", "") or "")
        else:
            data["lastError"] = "Could not read mise dotfiles status"

        exit_code, out = command_output(
            [mise_bin, "bootstrap", "dotfiles", "history", "-J", "-n", "20"], 10
        )
        if exit_code == 0 and out:
            try:
                checkpoints = json.loads(out)
            except json.JSONDecodeError:
                pass
            else:
                for item in checkpoints if isinstance(checkpoints, list) else []:
                    if not isinstance(item, dict):
                        continue
                    data["activity"].append(
                        {
                            "id": item.get("id"),
                            "createdAt": str(item.get("created_at", "")),
                            "trigger": str(item.get("trigger", "")),
                            "description": str(
                                item.get("description", "")
                                or item.get("summary", "")
                                or "Checkpoint"
                            ),
                        }
                    )
    else:
        data["lastError"] = "mise is not installed"

    if tailscale_bin:
        exit_code, out = command_output([tailscale_bin, "status", "--json"], 8)
        if exit_code == 0 and out:
            try:
                status = json.loads(out)
            except json.JSONDecodeError:
                pass
            else:
                data["tailscale"]["running"] = status.get("BackendState") == "Running"
                yourself = status.get("Self", {}) or {}
                data["tailscale"]["selfName"] = str(yourself.get("HostName", "") or "")
                ips = yourself.get("TailscaleIPs", []) or []
                data["tailscale"]["selfIps"] = [str(ip) for ip in ips]
                peers = status.get("Peer", {}) or {}
                for peer in peers.values():
                    if not isinstance(peer, dict):
                        continue
                    peer_ips = peer.get("TailscaleIPs", []) or []
                    data["tailscale"]["peers"].append(
                        {
                            "hostName": str(peer.get("HostName", "") or "unknown"),
                            "dnsName": str(peer.get("DNSName", "") or ""),
                            "os": str(peer.get("OS", "") or ""),
                            "online": peer.get("Online") is True,
                            "ips": [str(ip) for ip in peer_ips],
                        }
                    )
                data["tailscale"]["peers"].sort(
                    key=lambda peer: (not peer["online"], peer["hostName"].lower())
                )

    return data


def main():
    print(json.dumps(payload()))


if __name__ == "__main__":
    sys.exit(main())
