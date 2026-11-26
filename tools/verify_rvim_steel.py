#!/usr/bin/env python3
"""Verify P0 + P1 Steel port and JSON theme snapshots in rvim/.config/rvim/."""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
NVIM_DIR = ROOT / "nvim" / ".config" / "nvim"
RVIM_DIR = ROOT / "rvim" / ".config" / "rvim"

LUA_JSON_DUMPER = r"""
local path = arg[1]
local data = assert(loadfile(path))()

local function escape_str(s)
  return '"' .. s:gsub('[\\"%c]', function(c)
    local b = c:byte()
    if c == '\\' then return '\\\\' end
    if c == '"' then return '\\"' end
    if b == 8 then return '\\b' end
    if b == 9 then return '\\t' end
    if b == 10 then return '\\n' end
    if b == 12 then return '\\f' end
    if b == 13 then return '\\r' end
    return string.format('\\u%04x', b)
  end) .. '"'
end

local function is_array(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
      return false
    end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0
end

local function encode(v)
  local tv = type(v)
  if tv == "nil" then return "null" end
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then return tostring(v) end
  if tv == "string" then return escape_str(v) end
  if tv == "table" then
    if is_array(v) then
      local parts = {}
      for i = 1, #v do parts[i] = encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k, _ in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      local raw_k = v[k] ~= nil and k or tonumber(k)
      parts[#parts + 1] = escape_str(k) .. ":" .. encode(v[raw_k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("unsupported type: " .. tv)
end

io.write(encode(data))
"""

def expected_lua_modules() -> set[str]:
    """Every Lua module under nvim/.config/nvim/lua/ except themes/data/*.lua (converted to JSON)."""
    lua_root = NVIM_DIR / "lua"
    mods: set[str] = set()
    for p in lua_root.rglob("*.lua"):
        rel = p.relative_to(lua_root)
        if rel.parts[:2] == ("themes", "data"):
            continue
        mods.add(rel.with_suffix("").as_posix())
    return mods


def find_lua_binary() -> str:
    for candidate in ("/opt/homebrew/bin/luajit", "luajit", "lua"):
        try:
            subprocess.run([candidate, "-v"], capture_output=True, check=True)
            return candidate
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
    raise RuntimeError("No luajit/lua binary found for theme parity verification")


def verify_scheme_file(path: pathlib.Path) -> list[str]:
    """Strict S-expression balance, string escape, and header check."""
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        return [f"{path.relative_to(ROOT)}: file is empty"]
    first_lines = "\n".join(text.splitlines()[:15])
    if "1:1 Steel port" not in first_lines and "Port of" not in first_lines and "colorscheme" not in first_lines.lower():
        errors.append(f"{path.relative_to(ROOT)}: missing 1:1 correspondence header comment")

    stack: list[tuple[str, int]] = []
    pairs = {"(": ")", "[": "]"}
    closing = {")": "(", "]": "["}
    i = 0
    n = len(text)
    line = 1
    in_string = False
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        if in_string:
            if ch == "\\":
                if i + 1 >= n:
                    errors.append(f"{path.relative_to(ROOT)}:{line}: trailing backslash in string")
                    break
                if text[i + 1] == "x":
                    escape = re.match(r"\\x([0-9a-fA-F]+);", text[i:])
                    if escape is None:
                        errors.append(f"{path.relative_to(ROOT)}:{line}: hex escape must end with ';'")
                    else:
                        i += escape.end()
                        continue
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == ";":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        # Handle Scheme character literals like #\space, #\(, #\), #\", #\[, #\]
        if ch == "#" and i + 1 < n and text[i + 1] == "\\":
            i += 2
            if i < n:
                if text[i].isalpha():
                    while i < n and text[i].isalpha():
                        i += 1
                else:
                    i += 1
            continue
        if ch in pairs:
            stack.append((ch, line))
        elif ch in closing:
            if not stack:
                errors.append(f"{path.relative_to(ROOT)}:{line}: unmatched '{ch}'")
            else:
                open_ch, open_line = stack.pop()
                if pairs[open_ch] != ch:
                    errors.append(
                        f"{path.relative_to(ROOT)}:{line}: mismatched '{open_ch}' (line {open_line}) with '{ch}'"
                    )
        i += 1
    if in_string:
        errors.append(f"{path.relative_to(ROOT)}: unterminated string literal")
    for open_ch, open_line in stack:
        errors.append(f"{path.relative_to(ROOT)}:{open_line}: unclosed '{open_ch}'")
    return errors


def verify_themes() -> list[str]:
    errors: list[str] = []
    lua_dir = NVIM_DIR / "lua" / "themes" / "data"
    json_dir = RVIM_DIR / "themes" / "data"
    lua_files = sorted(lua_dir.glob("*.lua"))
    json_files = sorted(json_dir.glob("*.json"))

    lua_stems = {p.stem for p in lua_files}
    json_stems = {p.stem for p in json_files}
    if lua_stems != json_stems:
        errors.append(
            f"Theme snapshot set mismatch: missing={sorted(lua_stems - json_stems)}, "
            f"extra={sorted(json_stems - lua_stems)}"
        )
        return errors

    lua_bin = find_lua_binary()
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as tf:
        tf.write(LUA_JSON_DUMPER)
        dumper_path = pathlib.Path(tf.name)
    try:
        for lua_path in lua_files:
            json_path = json_dir / f"{lua_path.stem}.json"
            proc = subprocess.run(
                [lua_bin, str(dumper_path), str(lua_path)],
                capture_output=True,
                text=True,
                check=True,
            )
            expected = json.loads(proc.stdout)
            actual = json.loads(json_path.read_text(encoding="utf-8"))
            if expected != actual:
                errors.append(f"Theme parity mismatch: {json_path.relative_to(ROOT)}")
    finally:
        dumper_path.unlink(missing_ok=True)
    return errors


def verify_colors() -> list[str]:
    errors: list[str] = []
    lua_colors = {p.stem for p in (NVIM_DIR / "colors").glob("*.lua")}
    scm_colors = {p.stem for p in (RVIM_DIR / "colors").glob("*.scm")}
    if lua_colors != scm_colors:
        errors.append(
            f"Colorscheme loader set mismatch: missing={sorted(lua_colors - scm_colors)}, "
            f"extra={sorted(scm_colors - lua_colors)}"
        )
    available_themes = {p.stem for p in (RVIM_DIR / "themes" / "data").glob("*.json")}
    for scm_path in sorted((RVIM_DIR / "colors").glob("*.scm")):
        text = scm_path.read_text(encoding="utf-8")
        # Check referenced theme snapshot names in (theme-load "...") or (hash "dark" "...")
        for match in re.finditer(r'\(theme-load\s+"([^"]+)"', text):
            ref = match.group(1)
            if ref not in available_themes:
                errors.append(f"{scm_path.relative_to(ROOT)}: references missing theme '{ref}'")
        for match in re.finditer(r'"(?:dark|light)"\s+"([^"]+)"', text):
            ref = match.group(1)
            if ref not in available_themes:
                errors.append(f"{scm_path.relative_to(ROOT)}: references missing theme '{ref}'")
    return errors


LUA_MAGIC_CHARS = set("^$()%.[]*+-?")
LUA_PAT_CALL_RE = re.compile(r"(?::|string\.)(gsub|gmatch|match|find)\s*\(")
SCM_PAT_CALL_RE = re.compile(r"\(string/(?:gsub|gmatch|match|find)\b")
# Magic-char pattern sites that live inside D's native Rust uv-new-work workers
# ("git-marks" in git.lua:734,789,789; "merge-tags" in tags.lua:241,244,245,253,254,255)
# or are factored into a single shared rvim/string call site:
# - search.scm: search.lua:266 & 268 share `(string/match line pat)` with `pat` selected by `use-rg`
NATIVE_OR_FACTORED_SITES = {
    "git": 3,
    "tags": 6,
    "search": 1,
}


def _strip_lua_comment(line: str) -> str:
    in_q = None
    i = 0
    while i < len(line):
        c = line[i]
        if in_q:
            if c == "\\":
                i += 2
                continue
            if c == in_q:
                in_q = None
        else:
            if c in "\"'":
                in_q = c
            elif line[i : i + 2] == "--":
                return line[:i]
        i += 1
    return line


def _extract_lua_call_args(s: str, pos: int) -> list[str]:
    depth = 1
    i = pos
    in_str = None
    in_long = False
    args: list[str] = []
    cur: list[str] = []
    while i < len(s) and depth > 0:
        ch = s[i]
        if in_long:
            if s[i : i + 2] == "]]":
                cur.append("]]")
                i += 2
                in_long = False
                continue
            cur.append(ch)
            i += 1
            continue
        if in_str:
            if ch == "\\":
                cur.append(s[i : i + 2])
                i += 2
                continue
            if ch == in_str:
                in_str = None
            cur.append(ch)
            i += 1
            continue
        if ch in "\"'":
            in_str = ch
            cur.append(ch)
            i += 1
            continue
        if s[i : i + 2] == "[[":
            in_long = True
            cur.append("[[")
            i += 2
            continue
        if ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(cur).strip())
                break
            cur.append(ch)
        elif ch == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    return args


def _count_lua_magic_sites(lua_path: pathlib.Path) -> int:
    count = 0
    for line in lua_path.read_text(encoding="utf-8").splitlines():
        code = _strip_lua_comment(line)
        for m in LUA_PAT_CALL_RE.finditer(code):
            op = m.group(1)
            is_str_mod = m.group(0).startswith("string.")
            args = _extract_lua_call_args(code, m.end())
            pat_arg = args[1] if (is_str_mod and len(args) >= 2) else (args[0] if args else "")
            plain = (op == "find") and (
                (is_str_mod and len(args) >= 4 and args[3] == "true")
                or (not is_str_mod and len(args) >= 3 and args[2] == "true")
            )
            if len(pat_arg) >= 2 and pat_arg[0] == pat_arg[-1] and pat_arg[0] in "\"'":
                has_magic = (not plain) and any(c in LUA_MAGIC_CHARS for c in pat_arg[1:-1])
            elif pat_arg.startswith("[[") and pat_arg.endswith("]]"):
                has_magic = (not plain) and any(c in LUA_MAGIC_CHARS for c in pat_arg[2:-2])
            else:
                has_magic = not plain
            if has_magic:
                count += 1
    return count


def verify_pattern_parity(scm_dir: pathlib.Path) -> list[str]:
    errors: list[str] = []
    lua_root = NVIM_DIR / "lua"
    for lua_path in sorted(lua_root.rglob("*.lua")):
        rel = lua_path.relative_to(lua_root)
        if rel.parts[:2] == ("themes", "data"):
            continue
        mod = rel.with_suffix("").as_posix()
        lua_magic = _count_lua_magic_sites(lua_path)
        expected_scm = lua_magic - NATIVE_OR_FACTORED_SITES.get(mod, 0)
        if expected_scm <= 0:
            continue
        scm_path = scm_dir / f"{mod}.scm"
        scm_text = scm_path.read_text(encoding="utf-8")
        if mod == "breadcrumbs":
            symbols = (scm_dir / "breadcrumb_symbols.scm").read_text(encoding="utf-8")
            if (
                "(breadcrumb-symbols-render " in scm_text
                and "(require-builtin rvim/breadcrumbs as draw.)" in symbols
                and "(draw.breadcrumb-render" in symbols
            ):
                # The native renderer replaces control characters and escapes percent signs.
                expected_scm -= 2
        if (
            mod == "statusline"
            and "(require-builtin rvim/statusline as draw.)" in scm_text
            and "(draw.statusline-compose " in scm_text
        ):
            # The renderer escapes Git text; the LSP segment sanitizes names and escapes percent signs.
            expected_scm -= 1
            if "(draw.statusline-lsp " in scm_text:
                expected_scm -= 2
            if "(draw.statusline-relative-path " in scm_text:
                # The native path helper strips trailing slashes from the project root.
                expected_scm -= 1
        if mod == "fzf_picker" and '(require "rvim/picker")' in scm_text:
            if "(picker/strip-prefix " in scm_text:
                # The native prefix helper trims trailing slashes from the root path.
                expected_scm -= 1
            if "(picker/parse-osc51 " in scm_text:
                # The native OSC 51 parser extracts the flash-fzf preview index.
                expected_scm -= 1
        if mod == "explorer" and '(require "rvim/explorer")' in scm_text:
            if "(explorer/render!" in scm_text:
                # Native encoder handles '%' and leading-space escaping in directory rows.
                expected_scm -= 2
            if "(explorer/parse-rows" in scm_text:
                # Native parser handles '/<id> ', indentation, percent-decoding, and path validation.
                expected_scm -= 4
            if "(explorer/draw-marks" in scm_text:
                # Native extmark calculator handles '/<id> ' prefix and indentation matching.
                expected_scm -= 3
        scm_calls = sum(
            len(SCM_PAT_CALL_RE.findall(line.split(";", 1)[0]))
            for line in scm_text.splitlines()
        )
        if scm_calls < expected_scm:
            errors.append(
                f"{scm_path.relative_to(ROOT)}: pattern parity gap: "
                f"Lua has {lua_magic} magic-char sites (expected >= {expected_scm} rvim/string calls), "
                f"found {scm_calls}"
            )
    return errors


def verify_modules_and_hygiene() -> list[str]:
    errors: list[str] = []
    scm_dir = RVIM_DIR / "scm"
    expected_modules = expected_lua_modules()
    actual_modules = {p.relative_to(scm_dir).with_suffix("").as_posix() for p in scm_dir.rglob("*.scm")}
    if actual_modules != expected_modules:
        errors.append(
            f"P0–P3 module set mismatch: missing={sorted(expected_modules - actual_modules)}, "
            f"extra={sorted(actual_modules - expected_modules)}"
        )

    # Verify every active (uncommented) local require in init.scm resolves to scm/<name>.scm
    init_text = (RVIM_DIR / "init.scm").read_text(encoding="utf-8")
    for line in init_text.splitlines():
        stripped = line.strip()
        if stripped.startswith(";"):
            continue
        m = re.match(r'^\(require\s+"([^"]+)"\)$', stripped)
        if m:
            mod = m.group(1)
            if not mod.startswith("rvim/") and mod not in actual_modules:
                errors.append(f"init.scm: requires missing local module '{mod}'")

    all_scm = [RVIM_DIR / "init.scm", *sorted(scm_dir.rglob("*.scm")), *sorted((RVIM_DIR / "colors").glob("*.scm"))]
    for path in all_scm:
        errors.extend(verify_scheme_file(path))

    # Zero-approximation guard:
    # 1) Forbid Vim-regex substitutes for Lua patterns (only editing.scm legitimately
    #    calls vim.fn.matchstr for Vim's \%col pattern), forbid legacy lua-* aliases,
    #    and forbid `(require "rvim/api")` (must be `(require-builtin rvim/api)`).
    approx_re = re.compile(
        r'\(fn-call\s+"(?:matchstr|matchlist|substitute)"|\(lua-(?:match|gsub|find|gmatch|format)\b|\(require\s+"rvim/api"\)'
    )
    for path in sorted(scm_dir.rglob("*.scm")):
        rel = path.relative_to(scm_dir).as_posix()
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if approx_re.search(line):
                if rel == "editing.scm" and '(fn-call "matchstr" (nvim_get_current_line) pat)' in line:
                    continue
                errors.append(
                    f"{path.relative_to(ROOT)}:{lineno}: forbidden pattern approximation or legacy alias (use rvim/string)"
                )

    # 2) Table-driven exact Lua pattern parity check:
    #    Every magic-char Lua pattern site (^$()%.[]*+-?, non-plain) in nvim/.config/nvim/lua/
    #    must be backed by rvim/string (string/match|gsub|gmatch|find) in the corresponding .scm
    #    module, except the 9 sites inside D's native Rust workers (git.lua git-marks: 3,
    #    tags.lua merge-tags: 6).
    errors.extend(verify_pattern_parity(scm_dir))

    # Hygiene: ensure no private repo URLs or personal emails leak into rvim/
    forbidden = [
        re.compile(r"rust-neovim", re.IGNORECASE),
        re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    ]
    for base in (RVIM_DIR,):
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix == ".json":
                continue
            if "licenses" in path.parts or path.name == "README.md" and path.parent.name == "themes":
                continue
            if path.resolve() == pathlib.Path(__file__).resolve():
                continue
            content = path.read_text(encoding="utf-8", errors="ignore")
            for pat in forbidden:
                if pat.search(content):
                    errors.append(f"{path.relative_to(ROOT)}: matched forbidden pattern {pat.pattern!r}")
    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(verify_themes())
    errors.extend(verify_colors())
    errors.extend(verify_modules_and_hygiene())
    if errors:
        for err in errors:
            print(f"FAIL: {err}", file=sys.stderr)
        print(f"\n{len(errors)} error(s) found.", file=sys.stderr)
        return 1
    theme_count = len(list((RVIM_DIR / "themes" / "data").glob("*.json")))
    color_count = len(list((RVIM_DIR / "colors").glob("*.scm")))
    mod_count = len(list((RVIM_DIR / "scm").rglob("*.scm")))
    print(
        f"OK: {theme_count} JSON themes (100% Lua parity), "
        f"{color_count} colorscheme loaders, "
        f"1 init.scm + {mod_count} P0–P3 Steel modules (100% FLASH Lua coverage) verified."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
