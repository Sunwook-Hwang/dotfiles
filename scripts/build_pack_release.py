#!/usr/bin/env python3
"""Bundle installed pvi plugins and their locked revisions, without editor settings."""

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
        raise SystemExit("Usage: python3 scripts/build_pack_release.py /path/to/pack.zip")
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

    with tempfile.TemporaryDirectory(prefix="pack-build-") as temp:
        bundle = Path(temp) / "pack"
        bundle.mkdir()
        target_plugins = bundle / "data/nvim-pack/site/pack/core/opt"
        (bundle / "nvim-pack-lock.json").write_text(
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
        for filename in ("update_pack.sh", "LICENSE"):
            shutil.copy2(repo / filename, bundle / filename)
        (bundle / "README.txt").write_text(
            "Package-based Neovim plugin bundle\n\n"
            "Install plugins: sh update_pack.sh /path/to/pack.zip\n"
            "Install editor settings separately with update_vims.sh and Source code.zip.\n"
            "Run: env NVIM_APPNAME=nvim-pack nvim\n\n"
            "Requires Neovim 0.12+ and Git. unzip is needed for installation.\n"
            "The installer builds fzf-native locally; make and a C compiler are required.\n"
            "All configured plugins and the matching lockfile are included; editor settings are not.\n"
            "Plugin sources and revisions: nvim-pack-lock.json\n"
            "Third-party code retains its own license; each plugin includes its original license and source.\n"
            "LSP servers, formatters and other platform-specific tools are not bundled.\n"
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        run("zip", "-q", "-r", "-y", str(output), "pack", cwd=temp)
    print(
        f"Built {output}: {len(locked)} plugins, {output.stat().st_size / 1024 / 1024:.1f} MiB"
    )


if __name__ == "__main__":
    main()
