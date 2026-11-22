"""Run FLASH Python LSP regressions with real servers and isolated temporary files."""

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--nvim", default="nvim")
parser.add_argument("--server", choices=["pyright", "ty"], default="pyright")
parser.add_argument(
    "--config",
    type=Path,
    default=Path(__file__).resolve().parents[1] / "nvim/.config/nvim",
)
parser.add_argument(
    "--case",
    choices=[
        "cross_file",
        "definition",
        "new_module",
        "delayed_response",
        "tab_switch",
        "hidden_buffer",
    ],
)
args = parser.parse_args()
command = ["ty", "server"] if args.server == "ty" else ["pyright-langserver", "--stdio"]
if not shutil.which(command[0]):
    parser.error(f"{command[0]} is not installed")
setup = (
    "lua package.preload['lsp.servers'] = function() return {{cmd = {"
    + ",".join(repr(s) for s in command)
    + "}, ft = {'python'}}} end"
)
failed = []
for case in (
    [args.case]
    if args.case
    else [
        "cross_file",
        "definition",
        "new_module",
        "delayed_response",
        "tab_switch",
        "hidden_buffer",
    ]
):
    with tempfile.TemporaryDirectory(prefix="flash-python-") as directory:
        root = Path(directory).resolve()
        project = root / "project"
        project.mkdir()
        (project / "pyproject.toml").write_text(
            '[project]\nname="flash-lsp-test"\nversion="0.0.0"\nrequires-python=">=3.11"\n'
        )
        (project / "main.py").write_text(
            "from provider import current\nvalue: int = current()\n"
        )
        if case != "new_module":
            (project / "provider.py").write_text(
                "def current() -> int:\n    return 1\n"
            )
        env = os.environ | {
            "FLASH_TEST_ROOT": str(project),
            "FLASH_TEST_CASE": case,
            "FLASH_TEST_SERVER": command[0],
            "TY_UV": "0",
            "XDG_STATE_HOME": str(root / "state"),
        }
        try:
            result = subprocess.run(
                [
                    args.nvim,
                    "--headless",
                    "-i",
                    "NONE",
                    "--cmd",
                    setup,
                    "-u",
                    str(args.config.resolve() / "init.lua"),
                    str(project / "main.py"),
                    "-l",
                    str(Path(__file__).with_suffix(".lua").resolve()),
                ],
                cwd=project,
                env=env,
                check=False,
                capture_output=True,
                text=True,
                timeout=35,
            )
            passed = result.returncode == 0 and (
                f"FLASH_LSP_TEST_PASS:{case}" in result.stdout + result.stderr
            )
            print(
                f"{args.nvim} / {args.server} / {case}:",
                "PASS" if passed else "FAIL",
                flush=True,
            )
            if not passed:
                failed.append(case)
                print(result.stdout + result.stderr, flush=True)
        except subprocess.TimeoutExpired:
            failed.append(case)
            print(f"{case}: process timed out", flush=True)
if failed:
    raise SystemExit("Failed: " + ", ".join(failed))
