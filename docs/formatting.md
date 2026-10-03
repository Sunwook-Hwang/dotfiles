# Formatting rules

These rules preserve the formatting applied to this repository. Formatter
configuration lives at the repository root; `.editorconfig` supplies matching
editor indentation and line endings.

| Files                       | Tool and rules                                                                                                   |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Lua                         | StyLua: tabs, width 4, wrap at 120 columns, prefer double quotes; do not sort `require` calls                    |
| Markdown / JSON             | Prettier: 2 spaces, width 80; preserve prose wrapping, do not format embedded code blocks                        |
| Shell scripts               | shfmt: infer syntax from the file and read 2-space indentation from `.editorconfig`, matching editor invocations |
| `zsh/.zshrc` / `vim/.vimrc` | No external formatter registered; only conservative whitespace cleanup                                           |
| Python                      | Ruff first, Black fallback, matching all three editors; shared 88-column configuration                           |
| Other text configs          | Remove whitespace-only blank-line content and extra final blank lines; retain nonempty lines and literal values  |

All files use UTF-8 and LF line endings. Do not strip trailing whitespace from
nonempty lines indiscriminately: it can be part of mappings, strings, or Markdown.
Git config entries keep tab indentation. TOML, tmux, Ghostty and Git settings are
not rewritten by a formatter for a different language.

## Editor integration

The tool choices come from `nvim/.config/nvim/lua/format.lua`,
`nvim-pack/.config/nvim-pack/lua/format.lua`, and `vim/.vimrc`.
StyLua, Prettier/prettierd, Ruff, Black, and shfmt read the shared configuration
files at the project root. Use the editor's `<leader>lf` mapping to format a buffer.
Package-based Neovim uses prettierd when available, with Prettier as its fallback. Python uses
Ruff first and Black as a fallback; the two may still produce different results.

The baseline was produced with StyLua 2.5.2, Prettier 3.9.9, shfmt 3.14.1,
Ruff 0.16.9, and Black 26.5.1. Formatter upgrades may change output; review their
diffs before adopting a new version.

## Reuse in another project

Run `dotformat <format> [project-path]` to copy the relevant configuration files.
Omit the path to use the current directory. Formats are `lua`, `python`,
`prettier`, and `shell`; `stylua`, `ruff`, `black`, and `shfmt` are also accepted.
The command is installed at `~/.local/bin/dotformat`; other shells need that
directory on PATH. It copies `.editorconfig` along with the selected rules,
skips existing files (including symbolic links), and does not run any formatter.
An existing `pyproject.toml` is left intact, with a reminder to merge its tool
sections manually. The target directory must already exist.

| Project language                                                      | Configuration to reuse                                      |
| --------------------------------------------------------------------- | ----------------------------------------------------------- |
| Lua                                                                   | `.stylua.toml` and `.editorconfig`                          |
| Python                                                                | Ruff/Black sections of `pyproject.toml` and `.editorconfig` |
| JavaScript, TypeScript, HTML, CSS, JSON, YAML, Markdown, Vue, GraphQL | `.prettierrc.json` and `.editorconfig`                      |
| Shell                                                                 | `.editorconfig`                                             |

Merge the Ruff/Black sections into an existing `pyproject.toml` instead of replacing
its package metadata. In a shared project, use the team's existing rules when they
differ. These are repository-local configuration files, not global home-directory
settings. The formatter reads the configuration for the file's project.

Other editor registrations include clang-format (C/C++/CUDA), buildifier (Bazel),
Buf/clang-format (Proto), cmake-format, latexindent, and rustfmt. This repository
has no source files or custom style configuration for those tools; they keep their
existing defaults.

## 한국어

현재 포매팅 기준을 `.stylua.toml`, `.prettierrc.json`, `.editorconfig`,
`pyproject.toml`에 고정했습니다. 편집기에서 `<leader>lf`로 포매팅하면 프로젝트의
설정 파일을 읽습니다.

***FLASH***·Package-based Neovim·Plugin-free Vim의 포매터 선택을 따릅니다. Python은 Ruff를 우선 사용하고, 없으면
Black을 사용합니다. 셸은 에디터와 동일하게 `.editorconfig`를 읽습니다. 포매터가 없는 설정은
값을 유지합니다. 포매터 업데이트 시에는 변경 내용을 검토해야 합니다.

다른 프로젝트에는 위 표의 설정 파일만 복사하면 됩니다. 기존 `pyproject.toml`은
덮어쓰지 말고 Ruff/Black 설정만 합치세요. 공동 작업 프로젝트에 이미 규칙이 있으면
그 규칙을 우선합니다.

`dotformat lua`, `dotformat python /path/to/project`처럼 실행하면 설정을 복사합니다.
형식은 `dotformat <포맷> [프로젝트 경로]`이며, 경로를 생략하면 현재 디렉토리를
사용합니다. 기존 설정은 덮어쓰지 않고 건너뜁니다. 포매터를 실행하거나 설치하는
명령은 아닙니다. 설치 위치는 `~/.local/bin/dotformat`이며 다른 셸에서도 이 경로가
PATH에 있으면 사용할 수 있습니다.
