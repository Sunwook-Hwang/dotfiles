#!/usr/bin/env python3
"""Bundle tracked pvi configuration and its installed, locked plugin revisions."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
config = repo / "nvim-pack/.config/nvim-pack"
data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
plugins = data / "nvim-pack/site/pack/core/opt"


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/build_pvi_release.py /path/to/pvi.zip")
    output = Path(sys.argv[1]).resolve()
    if output.exists():
        raise SystemExit(f"Output already exists: {output}")
    # Read the actual Lua package table, including explicit package names.
    specs = json.loads(
        run(
            "nvim",
            "--headless",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "-c",
            "lua vim.pack.add = function(specs) io.write(vim.json.encode(specs)) end; "
            f"dofile({json.dumps(str(config / 'lua/plugins.lua'))}); vim.cmd('qa!')",
        )
    )
    installed = json.loads((config / "nvim-pack-lock.json").read_text())["plugins"]
    locked = {}
    for spec in specs:
        name = spec.get("name", spec["src"].removesuffix(".git").rsplit("/", 1)[-1])
        entry = installed[name]
        if (
            entry["src"] != spec["src"]
            or run("git", "-C", str(plugins / name), "rev-parse", "HEAD")
            != entry["rev"]
        ):
            raise SystemExit(f"Installed plugin differs from its lockfile: {name}")
        locked[name] = entry

    with tempfile.TemporaryDirectory(prefix="pvi-build-") as temp:
        bundle = Path(temp) / "pvi"
        target_config = bundle / "config/nvim-pack"
        target_plugins = bundle / "data/nvim-pack/site/pack/core/opt"
        tracked = run("git", "ls-files", "-z", "nvim-pack/.config/nvim-pack", cwd=repo)
        for filename in tracked.split("\0"):
            if not filename:
                continue
            source = repo / filename
            target = target_config / source.relative_to(config)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        (target_config / "nvim-pack-lock.json").write_text(
            json.dumps({"plugins": locked}, indent=2) + "\n"
        )
        for name, entry in locked.items():
            target = target_plugins / name
            # Fresh shallow repositories retain vim.pack update support without
            # copying personal Git configuration, untracked files or local hooks.
            run(
                "git",
                "clone",
                "--quiet",
                "--no-local",
                "--no-checkout",
                "--depth=1",
                (plugins / name).as_uri(),
                str(target),
            )
            run("git", "-C", str(target), "remote", "set-url", "origin", entry["src"])
            run(
                "git",
                "-C",
                str(target),
                "checkout",
                "--quiet",
                "--detach",
                entry["rev"],
            )
            shutil.rmtree(target / ".git/logs", ignore_errors=True)
        run(
            "nvim",
            "--headless",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "-c",
            "lua for _, path in ipairs(vim.fn.glob("
            + json.dumps(str(target_plugins / "*/doc"))
            + ", false, true)) do vim.cmd.helptags({path, magic={file=false}}) end; vim.cmd('qa!')",
        )
        (bundle / "plugins.txt").write_text("\n".join(locked) + "\n")
        revision = run("git", "rev-parse", "HEAD", cwd=repo)
        (bundle / "REVISION").write_text(revision + "\n")
        for filename in ("update_pvi.sh", "LICENSE"):
            shutil.copy2(repo / filename, bundle / filename)
        (bundle / "README.txt").write_text(
            "Package-based Neovim (pvi) release bundle\n\n"
            "Install: sh update_pvi.sh /path/to/pvi.zip\n"
            "Run: env NVIM_APPNAME=nvim-pack nvim\n\n"
            "Requires Neovim 0.12+ and Git. unzip is needed for installation.\n"
            "All configured plugins and the matching lockfile are included.\n"
            "Plugin sources and revisions: config/nvim-pack/nvim-pack-lock.json\n"
            "Third-party code retains its own license; each plugin includes its original license and source.\n"
            "LSP servers, formatters and other platform-specific tools are not bundled.\n"
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        run("zip", "-q", "-r", "-y", str(output), "pvi", cwd=temp)
    print(
        f"Built {output}: {len(locked)} plugins, {output.stat().st_size / 1024 / 1024:.1f} MiB"
    )


if __name__ == "__main__":
    main()
