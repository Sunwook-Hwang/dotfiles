# Package-based Neovim configuration structure

`nvim-pack/.config/nvim-pack/init.lua` loads the feature modules directly from
`nvim-pack/.config/nvim-pack/lua/`. Snacks is configured before modules register its toggles.
It resolves its own file location, including symlinks, so `nvim -u /path/to/init.lua`
also works when the adjacent `lua/` directory is present.

***FLASH***'s `nvim/.config/nvim/init.lua` stays independent: it loads feature modules from its own
`lua/` directory and does not import any Package-based Neovim modules. Copy its whole profile directory
when moving it to a server. `vi` always starts ***FLASH***; `pvi` selects `NVIM_APPNAME=nvim-pack`. Package-based Neovim plugins and Mason tools are separate
from these configuration files and must also be available on a network-isolated server.

| Module              | Responsibility                                                    |
| ------------------- | ----------------------------------------------------------------- |
| `options.lua`       | Disable defaults, editor options, leader                          |
| `buffer_policy.lua` | Shared buffer eligibility, guarded actions and restriction events |
| `keymaps.lua`       | Editing, window movement/resizing, cursor word highlight          |
| `bigfile.lua`       | Snacks bigfile configuration and supplemental growth checks       |
| `plugins.lua`       | `vim.pack` package registration                                   |
| `context.lua`       | Native sticky context and its update lifecycle                    |
| `ui.lua`            | Snacks setup: dashboard, indent, picker styling, terminal layout  |
| `git.lua`           | Gitsigns, hunk operations, inline blame                           |
| `session.lua`       | Session persistence                                               |
| `clipboard.lua`     | SSH clipboard copying                                             |
| `whichkey.lua`      | Keybinding help                                                   |
| `pickers.lua`       | Search picker mappings                                            |
| `breadcrumbs.lua`   | Native statusline context, scope navigation and toggle             |
| `breadcrumb_symbols.lua` | Cached LSP symbol hierarchy and request lifecycle             |
| `outline.lua`       | Aerial outline and cursor tracking                                |
| `terminal.lua`      | Bottom terminal and lazygit toggles                               |
| `format.lua`        | Conform formatter registration and formatting                     |
| `completion.lua`    | Native completion and snippets                                    |
| `project.lua`       | Shared project roots, Python library boundaries and root cache    |
| `explorer.lua`      | Explorer toggle and working-directory updates                     |
| `lsp.lua`           | Native LSP, Snacks capability-aware keys, servers, Python, Mason  |
| `buffers.lua`       | Tabline, buffer selection and deletion                            |
| `statusline.lua`    | Statusline rendering and invalidation                             |
| `theme.lua`         | Final editor commands and colorscheme                             |

`ui.lua` passes the configuration from `bigfile.lua` to Snacks and calls the cached
terminal toggle from `terminal.lua` when an explorer terminal shortcut is pressed.
Snacks also manages capability-aware LSP keymaps, feature toggle bindings, and
filtered bulk buffer deletion. Sticky context, breadcrumbs, and statusline
rendering keep their existing implementations and default states.
Modules that use Snacks import the installed
`snacks` plugin directly. Configuration module names intentionally differ from
plugin entry points such as `snacks`.

Automatic editing and code-analysis features use `buffer_policy.allows(buf)`;
normal loaded buffers are eligible unless marked as large files. Manual source
operations that should remain available on large files can use `is_source(buf)`,
which also recognizes unloaded normal buffers for buffer lists and sessions.
Manual formatting follows the same protection limits as code analysis.
Use `guard(callback)` for code-analysis keymaps. Do not duplicate `large_file`
checks in feature modules. `bigfile.lua` detects size and edit growth, then calls
`restrict(buf)` once. The policy disables Snacks buffer features and emits
`PackBufferRestricted`; each feature owns its cleanup, including Git/LSP detachment,
pending requests, overlays and outline data. Check eligibility when an action runs
and when an asynchronous result arrives. Global defaults and other buffers stay unchanged.

Statusline breadcrumbs display the cached LSP document-symbol hierarchy without a
Dropbar dependency or indentation-based guesses. `<leader>Td` toggles them; clicking
a symbol jumps to its declaration line. Cursor movement and statusline redraws
never request symbols. File changes and LSP attachment changes refresh the cache;
disabling the feature or restricting/unloading a buffer cancels pending work.
Files without symbol support show only their path. Control-flow blocks appear only
when supplied as symbols by the language server; Dropbar's sibling menus are not
implemented. Python environment selection cancels superseded requests and drops
results after its source is unloaded, renamed or restricted.

새 기능의 실행 조건은 `buffer_policy`에서 가져옵니다. 큰 파일 판정은
`bigfile.lua`만 담당하고, 전환 시 공통 이벤트로 이미 켜진 기능도 정리합니다.
플러그인의 실행 필터·단축키·종료 처리를 연결해야 하며,
버퍼 플래그 하나만 설정한다고 외부 플러그인이 자동으로 차단되는 것은 아닙니다.

***FLASH*** implements the same contract in its own `buffer_policy.lua`,
without importing Package-based Neovim modules or plugins. Plugin-free Vim keeps the equivalent `IsSource`,
`BufferAllows`, and `RestrictBuffer` helpers inside `.vimrc`. Their
`NopackBufferRestricted` event cancels affected automatic work and clears active
UI. All three profiles protect files exceeding 2 MiB, 50,000 lines, or a single
10,000-byte line. Detection on open and changed-range checks on edits share the
same limits; features may retain stricter workload budgets, such as native Git
sign diff limits. Protection lasts until the buffer is discarded. Buffer lists,
project browsing, and sessions still recognize protected or unloaded source buffers.

***FLASH***도 독립적인 `buffer_policy.lua`를 사용하고, Plugin-free Vim은 같은 정책을 파일 내부
함수로 구현합니다. 큰 파일 제한 전환은 한 번만 알리고, 각 기능이 자신의 요청·타이머·
표시를 정리합니다. 파일 열기와 편집 중 증가를 모두 검사하며, 커서 이동마다 파일
전체를 다시 검사하지 않습니다. 큰 파일의 기본 편집·탐색·버퍼 목록·세션은 유지합니다.

When investigating cursor lag, start with the events and callbacks in the relevant
feature module. File splitting does not itself change refresh frequency, introduce
lazy loading, or improve performance. Avoid re-sourcing individual modules during
a running session: their setup code registers mappings and events. Restart Neovim
after changes.

## Live sharing

Package-based Neovim installs [peerpad.nvim](https://github.com/Sunwook-Hwang/peerpad.nvim)
through `vim.pack`; `init.lua` calls its setup directly. It interoperates with ***FLASH***'s native live sharing.
`<leader>Ps` starts sharing, `<leader>Pj` joins, `<leader>Pq` disconnects, and
`<leader>Pi` shows session information. The commands are `:Peerpad`,
`:PeerpadJoin`, `:PeerpadStop`, and `:PeerpadStatus`.
Transport loads only when needed; discovery checks once per source-file read.
For disconnected servers, copy this package along with the other Package-based Neovim plugins.

Package-based Neovim에서도 ***FLASH***와 같은 리더키 단축키로 공유·참여·종료·상태 확인을 사용합니다.
NFS로 같은 파일을 보더라도 참여자 사이 TCP 연결은 필요하며, 원본 저장은 호스트만 합니다.

## Scope and profiling

Snacks Scope uses indentation without Treesitter. `[i` / `]i` jump to scope
edges; `ii` / `ai` select the inner / full scope in visual or operator-pending
mode (for example, `vii` or `dai`). Scope highlighting remains disabled.

The Lua profiler starts disabled. `<leader>Dp` starts/stops recording and opens
results when stopped; `<leader>DP` reopens results; `<leader>Dh` toggles profiling
highlights. Recording adds overhead and captures only supported Lua calls,
including Lua autocmd callbacks registered while recording.

Scope는 들여쓰기로 범위를 탐색하며 Treesitter를 사용하지 않습니다.
`[i` / `]i`로 범위 양 끝으로 이동하고, `vii` / `vai`로 내부 / 전체 범위를 선택합니다.
Profiler는 기본 OFF입니다. `<leader>Dp`로 측정을 시작·종료하고,
`<leader>DP`로 결과를 다시 열며, `<leader>Dh`로 측정 결과 강조를 토글합니다.
측정 중에는 실행 부담이 추가되며 모든 호출을 기록하는 것은 아닙니다.

## 한국어

Package-based Neovim은 `lua/` 바로 아래 기능 이름으로 파일을 분리했습니다. 진입점인
`nvim-pack/.config/nvim-pack/init.lua`에 초기화 순서가 명시되어 있으며, 기존 실행 순서를 유지합니다.
다른 컴퓨터로 옮길 때는 `nvim-pack/.config/nvim-pack/init.lua`와 옆의 `lua/` 디렉터리를 함께 복사해야 합니다.
플러그인과 Mason 도구는 별도로 준비해야 합니다.

***FLASH***는 Package-based Neovim 모듈을 불러오지 않습니다. `nvim/.config/nvim/init.lua`와 옆의 `lua/` 디렉터리를 함께 가져가야 합니다.
커서 지연을 조사할 때는 해당 기능 파일의 이벤트 등록과 갱신 콜백을 확인하면 됩니다.
이번 분리는 동작과 갱신 주기를 바꾸지 않습니다. 설정 변경 후에는 Neovim을 재시작하세요.
