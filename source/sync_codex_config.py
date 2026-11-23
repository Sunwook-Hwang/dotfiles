"""Apply the optional machine-local layer to the file all Codex clients read."""

import fcntl
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import tomllib
except ImportError:  # Linux distributions with Python 3.10 and pip.
    from pip._vendor import tomli as tomllib


def overlay(base, local):
    if isinstance(base, dict) and isinstance(local, dict):
        return {**base, **{k: overlay(base.get(k), v) for k, v in local.items()}}
    return local


def unapply(base, applied, current):
    """Recover base values while keeping edits Codex made after the last sync."""
    if current == applied:
        return base
    if isinstance(applied, dict) and isinstance(current, dict):
        result = dict(base) if isinstance(base, dict) else {}
        for key in applied.keys() | current.keys():
            value = unapply(result.get(key), applied.get(key), current.get(key))
            if value is None:
                result.pop(key, None)
            else:
                result[key] = value
        return result
    return current


def edits(old, new, path=()):
    if old == new:
        return
    if isinstance(old, dict) and isinstance(new, dict):
        for key in sorted(old.keys() | new.keys()):
            yield from edits(old.get(key), new.get(key), (*path, key))
    else:
        yield {
            "keyPath": ".".join(json.dumps(k, ensure_ascii=False) for k in path),
            "mergeStrategy": "replace",
            "value": new,
        }


def timeout_sync(signum, frame):
    raise TimeoutError("Codex timed out while merging config.local.toml")


def render(original, old, new):
    # Codex's own TOML editor preserves comments, quoted keys and unrelated tables.
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp, "config.toml")
        config.write_bytes(original)
        requests = [
            ("initialize", {"clientInfo": {"name": "dotfiles", "version": "1"}}),
            ("config/batchWrite", {"edits": list(edits(old, new))}),
        ]
        with subprocess.Popen(
            ["codex", "app-server"],
            cwd=tmp,
            env={**os.environ, "CODEX_HOME": tmp},
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        ) as proc:
            try:
                signal.alarm(15)
                for i, (method, params) in enumerate(requests, 1):
                    print(
                        json.dumps({"id": i, "method": method, "params": params}),
                        file=proc.stdin,
                        flush=True,
                    )
                    for line in proc.stdout:
                        reply = json.loads(line)
                        if reply.get("id") == i:
                            if "result" not in reply:
                                raise ValueError(
                                    f"Codex rejected {method}; existing config.toml kept"
                                )
                            break
                    else:
                        raise ValueError(f"Codex exited before answering {method}")
            finally:
                signal.alarm(0)
                proc.kill()
        data = config.read_bytes()
        if tomllib.loads(data.decode()) != new:
            raise ValueError("Codex did not produce the requested TOML settings")
        return data


def replace(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
        tmp = Path(out.name)
        try:
            out.write(data)
            out.flush()
            os.replace(tmp, path)
        finally:
            tmp.unlink(missing_ok=True)


def sync(directory):
    config = directory / "config.toml"
    local = directory / "config.local.toml"
    state = directory / ".dotfiles-overlay.json"
    original = config.read_bytes() if config.exists() else b""
    current = tomllib.loads(original.decode())
    overrides = (
        tomllib.loads(local.read_text(encoding="utf-8")) if local.exists() else {}
    )
    digest = hashlib.sha256(original).hexdigest()
    journal = json.loads(state.read_bytes()) if state.exists() else {}
    # If interrupted between the two atomic replacements, use the pre-write state.
    previous = (
        journal.get("before", {})
        if digest == journal.get("digest")
        else journal.get("after", {})
    )
    after = {}
    desired = current.copy()
    for key in previous.keys() | overrides.keys():
        base = current.get(key)
        if key in previous:
            base = unapply(*previous[key], base)
        value = base
        if key in overrides:
            value = overlay(base, overrides[key])
            if value != base:
                after[key] = [base, value]
        if value is None:
            desired.pop(key, None)
        else:
            desired[key] = value
    if desired != current:
        if config.is_symlink():
            raise ValueError(
                f"refusing to write machine settings through symlink {config}"
            )
        data = render(original, current, desired)
        if (config.read_bytes() if config.exists() else b"") != original:
            raise ValueError(
                "config.toml changed during sync; reload the shell to retry"
            )
        replace(
            state,
            json.dumps({"digest": digest, "before": previous, "after": after}).encode(),
        )
        replace(config, data)
    elif after and previous != after:
        replace(state, json.dumps({"after": after}).encode())
    if not after:
        state.unlink(missing_ok=True)


if __name__ == "__main__":
    signal.signal(signal.SIGALRM, timeout_sync)
    directory = Path(sys.argv[1])
    fd = os.open(directory, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        sync(directory)
    except (OSError, ValueError, TypeError) as error:
        sys.exit(f"Codex config sync: {error}")
    finally:
        os.close(fd)
