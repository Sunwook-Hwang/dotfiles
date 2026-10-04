# ***FLASH*** — 네이티브 Neovim 가이드

`<leader>`는 사용자가 설정한 리더 키입니다. 기본은 Space이며 `lua/options.lua`에서 변경할 수 있습니다. ***FLASH*** 로드 전에 지정한 `vim.g.mapleader`도 유지합니다.


[English](flash.md) | [한국어](flash.ko.md)

`nvim/.config/nvim/init.lua`는 **패키지가 전혀 필요 없는 순수 Native Neovim 설정**입니다.
Neovim 0.12 내장 API와 시스템 명령만 사용하는 기능별 Lua 모듈로 구성되어 있습니다.
플러그인 매니저, 외부 Lua 플러그인, Treesitter 파서 다운로드 없이 실행할 수 있습니다.
LSP·포매터·Git·검색 도구는 설치되어 있을 때만 사용하며 자동으로 내려받지 않습니다.

- 설정 파일: `nvim/.config/nvim/init.lua`와 같은 위치의 `lua/` 폴더
- 요구 버전: Neovim 0.12 이상

목차:

- [실행과 시작 화면](#실행과-시작-화면)
- [화면 구성](#화면-구성)
- [단축키 찾기](#단축키-찾기)
- [파일과 버퍼](#파일과-버퍼)
- [검색과 선택 UI](#검색과-선택-ui)
- [Git](#git)
- [LSP·완성·진단](#lsp완성진단)
- [포맷팅](#포맷팅)
- [Undo·세션·터미널](#undo세션터미널)
- [편집 편의 기능](#편집-편의-기능)
- [성능과 안전 제한](#성능과-안전-제한)
- [의도적으로 제공하지 않는 기능](#의도적으로-제공하지-않는-기능)
- [도구 설치와 서버 이동](#도구-설치와-서버-이동)
- [Ctags fallback](#ctags-fallback)
- [설정 구조](#설정-구조)

## 실행과 시작 화면

```sh
NVIM_APPNAME=nvim nvim
```

파일 인자 없이 실행하면 네이티브 dashboard가 열립니다. `j/k` 또는 방향키로 선택하고
`Enter`로 실행할 수 있으며, 커서는 선택 가능한 행에서만 움직입니다.

| 키        | 동작                        |
| --------- | --------------------------- |
| `f`       | 프로젝트 파일 찾기          |
| `r`       | 최근 파일                   |
| `l`       | 마지막 세션 복원            |
| `p`       | 저장된 세션 선택            |
| `n`       | 새 파일                     |
| `c`       | 현재 Neovim 설정 열기       |
| `q`       | 종료                        |
| `<leader>A` | 편집 중 dashboard 다시 열기 |

파일을 인자로 넘겨 실행하면 dashboard를 건너뛰고 바로 파일을 엽니다.

Dashboard는 전용 floating window를 사용합니다. `Esc`로 닫으면 기존 편집 창의
버퍼·커서·스크롤·창 옵션이 그대로 유지됩니다. 메뉴 선택과 직접 입력한 `:edit`는
원래 편집 창에서 파일을 엽니다.

## 화면 구성

### 상태줄

왼쪽에는 Git 브랜치와 현재 파일 상태, 파일명을 표시합니다. 오른쪽에는 진단 요약,
LSP·포매터 상태, 파일타입과 고정 폭 위치 정보를 표시합니다.

```text
[master .M] file.lua [+]    E: 1 W: 2 [LSP: lua_ls] [FORMAT: stylua] lua |  123:  8 |  42%
```

- 진단 개수가 0이면 해당 항목을 숨깁니다.
- LSP가 없으면 사용 가능한 ctags를 `[CTAGS: Universal]` 또는 `[CTAGS: Exuberant]`로 표시하고, 둘 다 없으면 강조 배경의 `[LSP X]`를 표시합니다.
- 사용할 포매터가 없으면 `[FORMAT X]`를 표시합니다.
- `[FORMAT: 이름]`은 현재 버퍼에서 실제 사용할 외부 도구 또는 LSP 이름입니다.
- `<leader>Tl`로 LSP와 포매터 상태 영역을 함께 숨기거나 다시 표시합니다.
- `<leader>Td`로 LSP 심볼 기반 상태줄 문맥(`경로 > 클래스 > 함수`)을 토글합니다. 심볼 클릭 시 선언 줄로 이동합니다. 심볼 지원이 없으면 경로만 표시하며 코드 원문이나 들여쓰기로 추정하지 않습니다.

### 버퍼·들여쓰기·Sticky Scroll

- 상단 tabline에 열린 버퍼와 수정 상태를 표시합니다.
- `Alt-1..8`은 해당 번호 버퍼, `Alt-9`는 마지막 버퍼로 이동합니다.
- 들여쓰기 선은 파일의 `shiftwidth`에 맞춰 `┊`로 표시합니다.
- Sticky Scroll은 기본 꺼짐이며, 켜면 함수·조건·반복문의 상위 문맥을 최대 8줄까지 고정합니다.
- Sticky 영역은 실제 줄 번호, 들여쓰기 위치, syntax highlight와 구분선을 유지합니다.
- `<leader>Ti`로 들여쓰기/공백 표시, `<leader>Ts`로 Sticky Scroll을 토글합니다.

`Ctrl-d` / `Ctrl-u`는 줄바꿈·접기를 포함해 반 페이지를 약 120ms 동안 부드럽게
이동합니다. 기본값은 꺼짐이며 `<leader>TS`(대문자 `S`)로 토글합니다.
Diff·floating/특수 버퍼·큰 파일·스크롤/커서 연동 창·매크로 기록/실행 중에는
기본 스크롤을 즉시 실행합니다.

Sticky Scroll은 들여쓰기와 기본 syntax를 이용한 휴리스틱입니다. 위쪽 1,000줄 또는
256 KiB까지만 탐색하며 복잡한 여러 줄 선언이나 특이한 언어 문법은 놓칠 수 있습니다.

## 단축키 찾기

Normal 모드에서 리더 키를 누르면 현재 사용 가능한 리더 단축키를 하단에 표시합니다.
LSP나 탐색기처럼 버퍼에만 붙는 매핑도 현재 상태에 맞춰 반영합니다.

- 다음 키를 누르면 안내창을 닫고 해당 단축키를 실행합니다.
- `Esc`, `Ctrl-c` 또는 등록되지 않은 키로 취소합니다.
- 빠르게 완성한 리더 단축키는 안내창을 거치지 않고 바로 실행합니다.
- Visual·Insert·Terminal 모드에는 개입하지 않습니다.

## 파일과 버퍼

| 키                     | 동작                                      |
| ---------------------- | ----------------------------------------- |
| `<leader>f`              | 프로젝트 파일 fuzzy picker                |
| `<leader><CR>`          | Git 추적 파일 picker                      |
| `<leader>e`              | 편집 가능한 파일 탐색기 토글 |
| `<leader>sb`             | 열린 버퍼 picker                          |
| `<leader>sr`             | 최근 파일 picker                          |
| `<leader>sn`             | Neovim 설정 파일 picker                   |
| `Shift-h/l`, `[b`/`]b` | 이전/다음 버퍼                            |
| `<leader>bj/bk`          | tabline에서 현재 버퍼 순서 이동           |
| `<leader>bD/bL`          | 디렉터리/파일타입 기준 버퍼 정렬          |
| `<leader>bp`             | 버퍼 선택                                 |
| `<leader>bw`             | 미저장 변경을 보호하며 현재 버퍼 닫기     |
| `<leader>c`              | 현재 버퍼 강제 닫기                       |
| `<leader>bm`, `<leader>be` | 현재 버퍼 외의 안전한 버퍼 닫기           |
| `<leader>bh/bl`          | 현재 버퍼 왼쪽/오른쪽의 안전한 버퍼 닫기  |

위 버퍼 닫기 단축키는 버퍼가 여러 개 남아 있으면 분할 창과 크기를 유지합니다.
버퍼가 하나만 남으면 현재 탭에서 그 버퍼를 표시하는 중복 편집창을 하나로 합칩니다.
사이드바·플로팅 창·다른 탭은 유지하며, 마지막 버퍼를 닫으면 빈 버퍼를 표시합니다.

프로젝트 루트는 Git 루트를 우선합니다. Git이 없으면 CMake, Make, package.json,
Python, Cargo, Bazel, Buf 프로젝트 marker를 위쪽으로 찾습니다. 편집창 cwd, 검색, LSP와 ctags가 같은 루트를 사용합니다.
탐색기는 프로젝트 루트에서 시작하며 현재 파일까지의 폴더를 펼칩니다.
설치된 Python 라이브러리는 `site-packages` 또는 `dist-packages` 바로 아래의
패키지 폴더를 루트로 사용합니다(예: `site-packages/tvm`). Git 탐색도 이 경계를
넘지 않아 상위 Homebrew나 프로젝트 저장소가 대신 선택되지 않습니다. 패키지 내부의
Git 저장소는 계속 인식합니다. 패키지 폴더 없이 바로 설치된 단일 모듈은
`site-packages` 또는 `dist-packages` 자체를 루트로 사용합니다.
Python 표준 라이브러리는 `os.py`와 `importlib/__init__.py`가 함께 있는 디렉터리
(예: `lib/python3.13`)를 루트로 사용합니다. 설치 패키지의 루트가 바깥쪽 표준
라이브러리 루트보다 우선하며, 어느 쪽도 상위 저장소까지 탐색하지 않습니다.

### 편집 가능한 파일 탐색기

`<leader>e`는 프로젝트 루트에서 현재 파일까지 펼친 트리를 줄 번호 없이 왼쪽에 표시합니다. Oil 플러그인이나 외부
패키지 없이, Oil처럼 목록을 Vim 명령으로 편집한 뒤 `:w`와 확인으로 반영합니다.

| 키 | 동작 |
| --- | --- |
| `Enter` / `za` | 편집창에서 파일 열기 / 폴더 펼치기·접기 |
| `zc` | 현재 폴더 또는 상위 폴더 접기 |
| `-` / `\w` | 상위 / 작업 디렉터리 |
| `\v` / `\s` / `\t` | 세로 분할 / 가로 분할 / 새 탭으로 열기 |
| `\p` | 파일 미리보기 토글 |
| `Ctrl+c` | 탐색기 닫고 편집창으로 복귀 |
| `gr` | 목록 새로고침 |
| `g.` | 숨김 파일 토글 (기본 표시) |
| `\i` | Git ignore 파일 토글 (기본 표시) |
| `gs` | 이름·크기·수정 시각 및 오름/내림차순 선택 |
| `\d` / `\D` | 전역 / 탭 작업 디렉터리 변경 |
| `gx` | 외부 앱으로 열기 |
| `g?` | 탐색기 도움말 토글; 트리 편집 후에도 같은 키로 닫기 |
| `yy` → `p`, 복제한 줄 이름 변경, `:w` | 파일·디렉터리 복사 |
| `i` / `a` | 커서 위치 / 커서 다음에서 파일명 수정 |
| `I` / `A` | 파일명 처음 / 끝에서 수정 |
| `cc` | 파일명 전체 교체 |
| 이름 수정, `Esc`, `:w` | 확인 후 내용은 유지하고 이름 변경 |
| `o`, 이름 입력, `:w` | 빈 파일 생성; 끝에 `/`를 붙이면 폴더 생성 |
| `dd`, `:w` | 확인 후 파일·디렉터리 삭제 |

폴더 생성은 `o` → `src/` 입력 → `Esc` → `:w` → 확인입니다.
끝의 `/` 없이 `src`만 쓰면 빈 파일을 만듭니다. 폴더 이름을 바꿀 때도 `/`를 유지합니다.
폴더 줄에서 `o`를 누르면 자동으로 그 안에 생성하며, 접힌 기존 폴더도 펼칩니다.
`O`는 같은 깊이에서 위에 항목을 만듭니다.
`test/main.py`를 입력하면 없는 `test` 폴더와 파일을 한 번에 생성합니다.
`a/b/`는 중첩 폴더를 만듭니다. 경로는 해당 줄이 속한 폴더 기준입니다.
새 폴더 줄과 그 하위 항목을 함께 저장해도 됩니다. 절대 경로와 `.`·`..`는 허용하지 않습니다.

`yypp`는 목록에 두 사본을 만듭니다. 각각 다른 이름을 지정한 뒤 저장합니다.
`cc`, `S`, `I`는 숨겨진 파일 식별자를 보존합니다. 중복 이름, 기존 대상 덮어쓰기,
외부에서 변경된 원본은 저장 전에 차단합니다. 미저장 목록에서 이동하려 하면
저장·폐기·취소를 묻습니다. 창 이동은 `Ctrl+h/j/k/l` 또는 `Ctrl+w h/j/k/l`입니다.
`Ctrl+s`는 저장, `Ctrl+t`는 터미널 토글을 유지합니다. 탐색기 전용 명령은
LocalLeader(기본 `\`)를 사용하며 `h/l`은 일반 커서 이동을 유지합니다.

`g?`는 트리와 도움말에서 같은 도움말 창 하나를 토글합니다.
도움말 안에서는 `q`, `Esc`, `Ctrl+c`로 닫습니다. 원래 트리를 닫거나 숨기면
도움말도 닫히며, 도움말 창을 파일 편집창으로 바꾸는 동작은 차단합니다.
숨김 파일과 Git 무시 항목은 기본 표시하며 각각 따로 토글할 수 있습니다.
Git 무시 여부는 비동기 일괄 조회 후 새로고침까지 재사용합니다.
숨긴 항목은 저장할 때 삭제 대상으로 취급하지 않습니다.

복사와 재귀 정리는 네이티브 비동기 파일 작업으로 처리합니다. `:w` 진행 중에는
탐색기 목록만 잠시 읽기 전용이 되며 중복 저장을 차단합니다. 편집창에서는 계속
코드를 수정할 수 있습니다. 변경 없는 목록은 다시 쓰지 않습니다. 숨겨진 미저장
목록과 복사한 파일 식별자는 보존하고, 숨겨진 저장된 디렉터리 버퍼는 정리합니다.
이름 변경은 열린 파일 버퍼와 미저장 내용을 유지합니다. 수정 중인 파일 삭제는
차단하며, 삭제된 파일의 깨끗한 버퍼는 기존 버퍼 닫기 정책으로 제거합니다.

폴더의 하위 항목은 같은 창에서 아래로 펼쳐집니다. 처음 펼칠 때 해당 폴더만
읽고, 접기·다시 펼치기는 새로고침·재진입·저장 전까지 기존 목록을 재사용합니다.
줄 번호와 `+`·`-` 표시 대신 세로 가이드선으로 트리 깊이를 표시합니다.
목록 편집·undo 후 가이드선만 갱신하며 디렉터리를 다시 조회하지 않습니다. 폴더에서 `o`는 하위 항목을
만들고, 붙여넣기는 선택한 줄의 깊이에 맞춥니다. 폴더 삭제는 먼저 접어서 `dd`하거나
표시된 하위 항목까지 함께 선택합니다. 폴더 이름 변경·삭제와 내부 항목 수정은 나눠 저장합니다. 새 폴더와 하위 항목 생성은 함께 저장할 수 있습니다.
디렉터리 심볼릭 링크는 순환을 피하도록 별도 루트로 엽니다. 로컬 파일, 디렉터리
재귀 복사, 심볼릭 링크를 지원합니다. 휴지통·SSH 어댑터, 권한 칼럼, 덮어쓰기,
이름 맞교환은 지원하지 않습니다. 목록 편집은 저장 전에 undo할 수 있지만,
실제 파일 작업을 되돌리는 히스토리는 제공하지 않습니다.

여백의 Git index/worktree 표시는 유지합니다. `.M`은 저장된 수정, `M.`은 staged,
`??`는 미추적 파일이며 혼합된 디렉터리는 `**`입니다.

## 검색과 선택 UI

외부 Telescope 없이 입력창, 결과 목록과 미리보기로 구성된 공통 picker를 사용합니다.

| 키         | 동작                                |
| ---------- | ----------------------------------- |
| `<leader>st` | 프로젝트 live 정규식 검색           |
| `<leader>t`  | 커서 단어 검색 후 결과 필터         |
| `<leader>s/` | 열린 파일의 저장된 디스크 내용 검색 |
| `<leader>sc` | 명령 검색                           |
| `<leader>sh` | 도움말 검색                         |
| `<leader>sk` | 현재 키맵 검색                      |
| `<leader>sp` | colorscheme 미리보기와 선택         |
| `<leader>sd` | 전체 진단 검색                      |

Picker에서는 `Ctrl-n/p` 또는 `Tab/Shift-Tab`으로 선택하고 `Enter`로 적용합니다.
`Esc`는 취소하고 `Ctrl-q`는 결과를 quickfix로 보냅니다. 검색은 `rg`를 우선하고 없으면
`grep` 또는 `find`를 사용합니다.

## Git

Git 기능은 네트워크 명령을 실행하지 않습니다. 현재 버퍼의 미저장 변경도 index와 비교해
여백에 추가 `+`, 수정 `~`, 삭제 `-` sign으로 표시합니다.

| 키            | 동작                                                               |
| ------------- | ------------------------------------------------------------------ |
| `<leader>gg`    | 90% × 90% 플로팅 lazygit; 없으면 네이티브 Git 상태 창                                |
| `<leader>sg`    | 최근 커밋 목록                                                     |
| `<leader>gd`    | 편집 가능한 현재 파일과 index 좌우 diff; 어느 창에서든 `:q`로 닫기 |
| `<leader>gD`    | 편집 가능한 현재 파일과 HEAD 좌우 diff; 어느 창에서든 `:q`로 닫기  |
| `<leader>gn/gp` | 다음/이전 변경 hunk로 이동; 끝에서 순환                            |
| `<leader>gb`    | 현재 줄 inline blame 토글                                          |

Inline blame은 저장된 파일의 작성자, 날짜와 커밋 메시지를 현재 줄 끝에 표시합니다.
커서 이동 후 150ms 동안 입력이 없을 때 갱신하고, 미저장 편집 중에는 잘못된 줄 attribution을
피하기 위해 숨겼다가 저장 후 다시 표시합니다. 큰 파일에서는 실행하지 않습니다.

추가 편집 기능은 pack과 같은 키를 사용합니다.

| 키 | 동작 |
| --- | --- |
| `<leader>gs/gr` | 현재 hunk 또는 Visual 선택 줄 스테이징/되돌리기 |
| `<leader>gS/gR` | 버퍼 전체 스테이징/되돌리기 |
| `<leader>gU` | 이 버퍼에서 마지막으로 수행한 스테이징 취소 |
| `<leader>gv` | hunk 인라인 미리보기; 커서 이동·편집 시 닫기 |
| `<leader>gt` | 삭제된 줄 표시 토글 |
| `<leader>gB` | 커밋 정보를 포함한 상세 blame |
| `ih` | hunk 텍스트 객체; `vih`, `dih` 등에서 사용 |

스테이징은 미저장 편집도 포함합니다. 되돌리기는 index를 기준으로 버퍼를 수정하며
파일을 저장하지 않습니다. 스테이징 취소 전에 같은 파일의 index 내용이 달라졌다면
다른 변경을 덮어쓰지 않고 중단합니다. hunk 작업은 256 KiB 이하의 일반 UTF-8 텍스트
파일을 지원하며 충돌 중인 index와 바이너리는 제외합니다. index 쓰기가 시작되면
`:NopackCancel`도 완료를 기다려 Git 잠금 파일이 정상 해제되도록 합니다.

## LSP·완성·진단

실행 파일을 찾은 서버만 Neovim 내장 LSP로 시작합니다. 검색 순서는 다음과 같습니다.

1. 현재 `PATH`
2. 기존 `stdpath("data")/mason/bin`

Mason을 로드하거나 도구를 설치하지 않습니다. 현재 등록된 서버는 다음과 같습니다.

| 언어                          | 서버                                                |
| ----------------------------- | --------------------------------------------------- |
| C/C++/Objective-C/CUDA        | `clangd`                                            |
| MLIR                          | `mlir-lsp-server`                                   |
| Python                        | `ty server`, 없으면 `pyright-langserver`            |
| Lua                           | `lua-language-server`                               |
| JavaScript/TypeScript/JSX/TSX | `typescript-language-server`                        |
| HTML                          | `vscode-html-language-server`                       |
| CSS/SCSS/Less                 | `vscode-css-language-server`                        |
| Bazel/Starlark                | `starpls server`                                    |
| Protocol Buffers              | `buf lsp serve`                                     |
| Shell                         | `bash-language-server start`                        |
| CMake                         | `neocmakelsp stdio`, 없으면 `cmake-language-server` |
| YAML                          | `yaml-language-server`                              |
| TeX                           | `texlab`                                            |
| Rust                          | `rust-analyzer`                                     |
| Web 보조 서버                 | Tailwind, Svelte, GraphQL, Emmet, Prisma, ESLint    |

Tailwind·ESLint는 프로젝트 설정이나 dependency가 있을 때만 연결하고 Emmet은 설정 marker가
있을 때만 연결합니다. 임의의 실행 파일을 자동 탐지해 새 언어에 연결하지는 않습니다.

| 키                 | 동작                             |
| ------------------ | -------------------------------- |
| `Ctrl-Space`       | Insert 모드 완성 후보 수동 요청  |
| `Ctrl-n/p`         | 완성 후보 이동                   |
| `Enter`            | 선택 후보 확정 또는 일반 줄바꿈  |
| `Tab`, `Shift-Tab` | snippet 자리 또는 완성 후보 이동 |
| `gd`               | LSP 정의, 실패하면 ctags 정의    |
| `gr`, `gD`, `K`    | 참조, 선언, hover 문서           |
| `gR`, `gi`, `gt`   | 참조/구현/타입 정의 결과 picker  |
| `<leader>la/lr`      | 코드 액션/이름 변경              |
| `<leader>ls`         | 현재 버퍼 LSP 재시작             |
| `<leader>lv`         | Python 분석 환경 선택            |
| `[d`, `]d`         | 이전/다음 진단                   |
| `<leader>ld/lD/sd`   | 현재 줄/버퍼/전체 진단 보기      |
| `<leader>lt`         | 진단 표시 토글                   |
| `<leader>o`          | LSP 또는 ctags 코드 아웃라인     |

분석 가능한 버퍼에서는 입력 중 자동으로 완성 후보를 표시합니다. LSP가 있으면
식별자 입력과 서버의 트리거 문자에 반응하며, `Ctrl-Space`로 직접 요청할 수도 있습니다.

LSP가 없으면 현재·열린 버퍼 단어와 ctags 심볼을 내장 완성에 사용합니다. `gd`와 코드
아웃라인도 지원되는 ctags가 있으면 설치된 ctags가 지원하는 언어의 저장된 소스를 대상으로 fallback합니다.

편집창과 아웃라인은 포커스를 유지한 채 양방향으로 위치를 추적하며, 커서 이동 시 심볼을 다시 요청하지 않습니다. LSP는 가장 안쪽의 포함 심볼을, 범위 정보가 없는 ctags는 앞쪽에서 가장 가까운 선언을 선택합니다.

`:checkhealth vim.lsp`로 연결 상태를 확인할 수 있습니다.

아웃라인 안에서는 `r`로 새로고침하고, `q`로 닫습니다. `Enter`는 선택한 심볼로
이동하면서 편집창으로 포커스를 옮깁니다.

## 포맷팅

`<leader>lf`는 저장하지 않은 현재 버퍼를 비동기로 포맷합니다. 외부 도구 결과를
`vim.text.diff()`로 비교해 변경 구간만 적용하고 한 번의 undo로 되돌릴 수 있게 합니다.
실행 중 버퍼가 바뀌거나 닫히면 늦게 도착한 결과를 버립니다.

| 파일타입                           | 외부 포매터                   |
| ---------------------------------- | ----------------------------- |
| Lua                                | `stylua`                      |
| C/C++/CUDA                         | `clang-format`                |
| Python                             | `ruff format`, 없으면 `black` |
| JS/TS/JSX/TSX, HTML, CSS/SCSS/Less | `prettier`                    |
| JSON/JSONC, YAML, Markdown/MDX     | `prettier`                    |
| GraphQL, Vue, Handlebars           | `prettier`                    |
| Bazel/Starlark                     | `buildifier`                  |
| Protocol Buffers                   | `clang-format`                |
| Shell                              | `shfmt`                       |
| CMake                              | `cmake-format`                |
| TeX                                | `latexindent`                 |
| Rust                               | `rustfmt`                     |

등록된 외부 포매터가 없으면 연결된 LSP의 document formatting을 시도합니다. MLIR과 Zsh는
외부 포매터를 등록하지 않았습니다. 저장 시 자동 포맷과 선택 영역 포맷은 사용하지 않습니다.

## Undo·세션·터미널

***FLASH***와 Package-based Neovim은 `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/undo`에 저장된 undo 기록을
공유합니다. 설정을 바꿔도 저장된 파일의 기록을 이어서 사용할 수 있으며,
동시에 실행 중인 두 편집기의 undo 트리를 실시간으로 합치지는 않습니다.

| 키                 | 동작                                                     |
| ------------------ | -------------------------------------------------------- |
| `<leader>u`          | undo 상태 목록과 코드 미리보기; `Enter`로 선택 상태 적용 |
| `<leader>pr`         | 현재 프로젝트 세션 복원                                  |
| `<leader>pl`         | 마지막 세션 복원                                         |
| `<leader>pS`         | 저장된 세션 선택                                         |
| `<leader>pd`         | 현재 실행에서 세션 저장 중지                             |
| `Ctrl-t`           | 같은 shell terminal을 아래 split에서 토글                |
| Terminal `Esc Esc` | Terminal 모드 종료                                       |

***FLASH***와 Package-based Neovim은 `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/sessions`에서 작업 디렉터리별
세션을 공유합니다. 파일, 커서 위치, 작업 디렉터리, 분할 창과 탭을 복원하며 탐색기·도움말·
플로팅 창·터미널·fold·설정별 옵션은 복원하지 않습니다. 미저장 파일 내용의 백업은 아니며, 같은 프로젝트는 마지막 저장이 우선합니다.

이름 있는 소스 버퍼가 있으면 **Neovim 종료 시 세션을 자동 저장**합니다.
`<leader>pd`는 현재 실행에서의 저장을 중지하며 기존 세션 파일을 삭제하지 않습니다.

Neovim 0.13 개발 버전의 `:restart`와 `ZR`에도 일반 세션 저장과 같은 보조 버퍼 제외
정책을 적용합니다. `:restart!`는 Neovim 기본 동작대로 세션을 복원하지 않습니다.
`Q`, `.`, Insert 모드 커서 이동 키는 호환 매핑 없이 설치된 Neovim 버전의 기본
동작을 따릅니다. `autoread`는 켜 두되 새 버퍼별 파일 감시는 비활성화하여
0.12처럼 포커스 복귀·`:checktime` 때 갱신합니다. NFS에서도 `:checktime`으로 확인할
수 있습니다. 저장하지 않은 편집 내용은 자동으로 덮어쓰지 않으며, 별도의 주기적
확인 타이머도 추가하지 않습니다.

터미널을 띄운 채 `Ctrl-h/j/k/l`로 편집창과 오갈 수 있고, 터미널 입력 모드에서도
Shift 방향키로 창 크기를 조절합니다. `Esc Esc` 또는 `Ctrl-\` 다음 `Ctrl-n`으로
터미널 일반 모드에 들어가 `hjkl`, `Ctrl-u/d`로 출력 기록을 탐색하고 `y`로 복사합니다.
`i`를 누르면 셸 입력으로 돌아갑니다. `Ctrl-t`로 숨겨도 셸 작업은 유지되지만
Neovim 자체를 종료한 뒤까지 작업을 유지하는 기능은 아닙니다.

## 편집 편의 기능

주석 토글은 플러그인 없이 Neovim 내장 기능을 사용합니다. 파일타입에 맞는
`commentstring`이 필요하며, 동작하지 않으면 `:set filetype? commentstring?`으로 확인합니다.

| 키 | 동작 |
| --- | --- |
| `gcc` | 현재 줄 주석 토글 |
| Visual `gc` | 선택한 줄 주석 토글; 예: `V`로 여러 줄 선택 후 `gc` |
| Visual `>` / `<` | 선택 영역 들여쓰기 / 내어쓰기 후 선택 유지 |
| `<leader>a` | 파일 전체 선택 |
| `<leader>Th` | 커서 단어의 다른 출현 위치 강조 토글; 기본 꺼짐 |
| `<leader>Sa` | 파일 전체 범위로 커서 단어 또는 Visual 선택 문자열의 치환 명령 준비 |
| `<leader>Sf` | 현재 줄부터 마지막 줄까지 같은 치환 명령 준비 |
| Normal `Esc` | 검색 강조 해제 |
| Normal `+` / `-` | 숫자 증가 / 감소 |
| `jk` | Insert 모드 종료 |
| `Ctrl-s` | 저장 |
| `Alt-j/k` | 현재 줄 또는 Visual 선택 이동 |
| `Ctrl-h/j/k/l` | Normal·Terminal 모드에서 창 이동 |
| Insert `Alt-방향키` | Insert 모드를 나가면서 해당 방향 창으로 이동 |
| Shift 방향키 | Normal·Terminal 모드에서 창 크기를 5칸씩 조절 |
| `<leader>w` | 현재 탭의 모든 창에 diff 적용; 해제는 `:windo diffoff` |
| Visual `p` / `P` | 복사한 내용을 유지하면서 선택 영역 교체 |
| Normal `x` | 문자를 삭제하되 복사 레지스터는 덮어쓰지 않음 |

치환 키는 명령을 바로 실행하지 않습니다. 바꿀 문자열과 마지막 `/`를 입력하고,
필요하면 `g`(줄의 모든 일치)·`c`(확인) 플래그를 붙인 뒤 Enter로 실행합니다.

괄호·대괄호·중괄호·따옴표·백틱은 자동으로 짝을 만들고, 빈 쌍에서 Backspace는
두 문자를 함께 삭제합니다. 검색 `n`/`N`은 결과를 화면 중앙에 유지하며,
복사한 내용은 잠깐 강조됩니다.

SSH·herdr 밖의 Windows·macOS·Linux에서는 `unnamedplus`로 Neovim의 시스템 clipboard provider를
사용합니다. SSH 또는 herdr에서는 `yy`와 Visual `y`의 내용을 OSC52로 화면을 보고 있는 PC의 터미널에 전송하며,
터미널이 OSC52를 지원하고 허용해야 합니다. `p`는 PC의 clipboard를 조회하지 않고
Neovim 내부 레지스터를 사용합니다. 다른 앱에서 복사한 내용은 터미널의 붙여넣기 단축키로
입력합니다.

## 성능과 안전 제한

| 대상           | 제한                                         |
| -------------- | -------------------------------------------- |
| 일반 외부 명령 | 기본 5초, stdout 2 MiB                       |
| 파일/검색 후보 | 최대 10,000개                                |
| 화면 표시 결과 | 최대 200개                                   |
| 파일 미리보기  | 앞 64 KiB                                    |
| Git sign       | 256 KiB, 20,000줄, sign 2,000개              |
| 포맷팅         | 2 MiB 이하 파일                              |
| Sticky Scroll  | 위쪽 1,000줄, 256 KiB                        |
| 큰 파일 보호   | 2 MiB, 50,000줄 또는 한 줄 10,000바이트 초과 |
| SSH OSC52 복사 | 100,000바이트 초과 시 경고 후 전송 생략      |

큰 파일에서는 LSP, syntax, 자동완성, ctags, Git sign, Sticky Scroll과 포맷팅을 중지하고
커서 십자 강조도 끕니다. wrap 설정은 유지합니다. `:NopackCancel`은 실행 중인 검색·Git·ctags 작업과 예약된
갱신을 취소합니다.

## 의도적으로 제공하지 않는 기능

- 플러그인·LSP·포매터 자동 다운로드 및 업데이트
- `todo-comments.nvim` 방식의 TODO/FIXME 강조
- 외부 colorscheme 묶음
- Neovide 전용 글꼴·확대/축소 설정
- Debug Adapter Protocol(DAP)
- Treesitter parser 자동 설치

이 기능들은 네트워크 의존성, 플랫폼 차이, 작업 내용 변경 위험 또는 유지 비용 때문에
***FLASH***의 기본 범위에서 제외합니다.

## 도구 설치와 서버 이동

위 언어별 표에서 필요한 도구만 설치합니다. ***FLASH***는 도구를 설치하지 않습니다.
셸 alias가 아니라 실행 파일·심볼릭 링크·launcher를 PATH에 둬야 합니다.
각 후보마다 PATH → 기존 Mason bin 순서로 찾으므로, PATH의 Pyright보다 Mason의 ty가
우선합니다. 설치 스크립트는 pack의 Mason 도구를 ***FLASH***와 공유하지만 Mason을 로드하지 않습니다.

`~/.local/opt/nvim-tools/` 아래 `node-tools/`, `python/`, `llvm/`,
`lua-language-server/`를 두고, 단독 실행 파일이나 launcher는 `~/.local/bin`에
배치할 수 있습니다. 실행 파일 디렉터리를 PATH에 추가합니다.

```sh
# Bash / Zsh
export PATH="$HOME/.local/bin:$HOME/.local/opt/nvim-tools/node-tools/node_modules/.bin:$HOME/.local/opt/nvim-tools/python/bin:$PATH"
```

```csh
# Csh / Tcsh
setenv PATH "$HOME/.local/bin:$HOME/.local/opt/nvim-tools/node-tools/node_modules/.bin:$HOME/.local/opt/nvim-tools/python/bin:$PATH"
```

필요하면 LLVM·StyLua·별도로 푼 Node.js의 `bin`도 추가한 다음 그 셸에서 Neovim을
새로 실행합니다. 이미 실행 중인 편집기에는 셸의 PATH 변경이 전달되지 않습니다.

### 도구 준비

Python 기본 조합은 ty와 Ruff입니다. 호환되는 `ty`, `ruff` 실행 파일을 PATH에 둡니다.
대안인 Pyright·Black 설치 예시는 아래와 같습니다. Pyright는 Node.js가 필요합니다.

```sh
npm install --prefix "$HOME/.local/opt/nvim-tools/node-tools" --save-exact pyright
python3 -m venv "$HOME/.local/opt/nvim-tools/python"
"$HOME/.local/opt/nvim-tools/python/bin/python" -m pip install black
```

웹 개발에는 위 Node 도구 디렉터리에 `typescript-language-server`, 그 서버와 호환되는
`typescript`, `vscode-langservers-extracted`, `prettier`를 설치합니다. 서버의 Node.js
버전과 호환되는 버전을 선택하고 생성된 lock 파일을 보관하세요.
PATH나 Mason에서 찾은 `tsserver`는 `tsserver.fallbackPath`로 전달하며, 프로젝트·동봉
TypeScript 탐색은 언어 서버가 담당합니다. 언어 서버 실행 파일만 복사해서는 부족합니다.
프로젝트의 `node_modules/.bin`은 자동 검색하지 않습니다.

추가 웹 서버의 패키지명은 다음과 같습니다.

| 실행 파일 | npm 패키지 |
| --- | --- |
| `tailwindcss-language-server` | `@tailwindcss/language-server` |
| `svelteserver` | `svelte-language-server` |
| `graphql-lsp` | `graphql-language-service-cli` |
| `emmet-ls` | `emmet-ls` |
| `prisma-language-server` | `@prisma/language-server` |
| `vscode-eslint-language-server` | `vscode-langservers-extracted` |

C/C++/CUDA는 clangd와 clang-format을 각각 준비하고, LLVM 배포본의 라이브러리와
디렉터리 구조를 보존합니다. 정확한 분석에는 프로젝트의 컴파일 옵션이 필요하며,
CMake에서는 `cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`으로 생성합니다.
LuaLS도 `main.lua`와 리소스를 포함한 배포본 전체를 보존하고 launcher를 PATH에 연결합니다.
StyLua는 별도로 설치하는 포매터입니다.

### 인터넷 없는 서버로 이동

**`init.lua`와 같은 위치의 `lua/`를 함께** `~/.config/nvim/`에 복사하거나
`nvim -u /path/to/init.lua`로 실행합니다. ***FLASH***에는 플러그인 폴더나 `vim.pack` lock 파일이
필요 없습니다. 도구는 서버의 OS·CPU·libc·런타임 요구 사항에 맞아야 합니다.
macOS 실행 파일이나 macOS에서 만든 venv는 Linux 서버에 그대로 사용할 수 없습니다.

Node 도구는 `.bin`만이 아니라 의존성과 심볼릭 링크를 포함한 전체 폴더를 옮깁니다.

```sh
# 호환되는 환경의 인터넷 연결 머신
tar -czf nvim-node-tools.tar.gz -C "$HOME/.local/opt/nvim-tools" node-tools
# 압축파일을 서버로 옮긴 후
mkdir -p "$HOME/.local/opt/nvim-tools"
tar -xzf nvim-node-tools.tar.gz -C "$HOME/.local/opt/nvim-tools"
```

서버에도 Node.js가 있어야 합니다. 인터넷 없는 서버에서 `npm install`을 다시 실행하지
않습니다. LuaLS·LLVM도 전체 배포본을 유지합니다. Python 도구는 호환 환경에서 의존성까지
wheel로 준비하고, 서버의 최종 경로에서 venv를 새로 만듭니다.

```sh
# 인터넷 연결 머신: 실행 후 wheelhouse/를 서버로 이동
python3 -m pip download --only-binary=:all: --dest wheelhouse black
# 서버
python3 -m venv "$HOME/.local/opt/nvim-tools/python"
"$HOME/.local/opt/nvim-tools/python/bin/python" -m pip install --no-index --find-links=wheelhouse black
```

### Python 환경 선택과 문제 해결

`<leader>lv`에서 `.venv`, `venv`, 활성 virtualenv/Conda, PATH Python, 검색된 Conda 환경
또는 직접 입력한 환경 폴더·Python 실행 파일을 선택합니다. `Automatic`은 선택을 해제합니다.
선택은 현재 실행 동안 프로젝트 분석에 적용되며 셸이나 포매터 PATH를 바꾸지 않습니다.
환경이 바뀌면 ty는 해당 프로젝트 클라이언트를 재시작하고, Pyright에는 Python 경로 설정을
전달합니다. 프로젝트의 Pyright venv 설정이 우선할 수 있습니다.

도구 설치 후 Neovim을 재실행하고 다음으로 확인합니다.

```vim
:messages
:set filetype?
:checkhealth vim.lsp
:lua vim.print(vim.lsp.get_clients({bufnr=0}))
:lua print(vim.fn.exepath('ty'))
:lua print(vim.fn.stdpath('data') .. '/mason/bin')
```

외부에서 프로젝트 설정이나 도구를 바꿨다면 `:NopackRefresh`로 프로젝트 루트와
포매터 가용성을 갱신할 수 있습니다. 새 LSP 등록을 위해서는 Neovim을 재실행합니다.

`exepath()`는 PATH만 확인하며 ***FLASH***의 Mason fallback은 포함하지 않습니다.
LSP가 연결되어도 선택한 Python 환경에 패키지가 없으면 import 오류가 날 수 있습니다.
큰 파일 보호 상태에서도 LSP·포맷팅은 의도적으로 중지됩니다.

## Ctags fallback

Universal Ctags를 우선하고 Exuberant Ctags도 지원합니다. BSD/Emacs ctags는 지원하지
않습니다. `ctags --version`으로 확인하고 특정 실행 파일을 지정하려면 다음처럼 실행합니다.

```sh
nvim --cmd "let g:nopack_ctags='/path/to/ctags'"
```

| 키 / 명령 | 동작 |
| --- | --- |
| `gd` | LSP 이후 ctags 시도; 첫 fallback에서 프로젝트 인덱스 생성 |
| `g Ctrl-t` | 태그 스택에서 이전 위치로 복귀 |
| `:CtagsUpdate` | 현재 프로젝트 인덱스 재생성 |
| `:CtagsClearAll` | 관리하는 모든 프로젝트 태그 캐시 삭제 |
| `:NopackCancel` | 실행 작업과 예약 갱신 취소 |

LSP 없는 완성과 ctags 아웃라인은 필요할 때 현재 파일을 인덱싱합니다. 사용 중인 프로젝트
인덱스는 저장 후 750ms 동안 변경을 모아 갱신하며, 외부 파일 변경은 `:CtagsUpdate`로
반영합니다. Git 프로젝트에서는 추적 파일과 무시되지 않은 미추적 파일을 사용합니다.
캐시는 `stdpath('data')/nopack/tags/`에 저장하며 `:setlocal tags?`로 연결 상태를 봅니다.
전체 생성은 120초/64 MiB, 파일 갱신은 10초/16 MiB로 제한합니다. ctags는 저장된 이름과
위치 정보이므로 타입 분석이나 미저장 변경을 정확하게 추적하는 LSP를 대신하지는 않습니다.

## 실시간 버퍼 공동 편집

***FLASH***는 플러그인이나 별도 서버 실행 파일 없이 서로 다른 Neovim 사이에서
하나의 텍스트 버퍼를 공동 편집할 수 있습니다. 서로 다른 노드가 같은 NFS 파일을
보는 환경도 지원합니다. NFS는 파일 저장에 쓰고 미저장 편집 내용은 TCP로 전달합니다.
따라서 NFS 접근 외에 노드 간 선택한 포트로 연결할 수 있어야 합니다.

노드 A에서 원본 파일을 연 뒤 실행합니다.

```vim
:Peerpad
```

이때 파일 옆에 호스트·포트·임의 토큰을 담은 `.<이름>.flash-share` 파일을 만듭니다.
이후 현재 편집창에서 그 파일을 열면 참여 여부를 묻기 때문에 IP나 토큰을 주고받을 필요가
없습니다. 거절했거나 공유 시작 전에 이미 파일을 열어 두었다면 인자 없는 `:PeerpadJoin`으로
현재 파일의 세션에 참여합니다. 수동 접속 명령은 `:messages`에서도 확인할 수 있습니다.

```vim
:PeerpadJoin <노드-A-IP> <포트> <토큰>
```

이 파일은 원본을 쓸 수 있는 권한 대상(소유자·그룹·기타)만 읽을 수 있어서, 원래 파일을
수정할 수 있는 사람만 참여합니다. `:PeerpadStop`이나 종료 시 삭제됩니다. 비정상 종료로
남은 파일은 같은 호스트에서 다시 열 때 정리되고, 그 밖의 경우에는 직접 지워야 합니다.
파일을 열 때마다 하는 확인을 끄려면 설정 로드 전에 `vim.g.flash_share_discovery = false`로
설정합니다. 실행 중에는 `require("peerpad").config.discovery = false`로 끕니다.

Git 프로젝트에서는 안내 파일과 임시 파일을 로컬 Git `info/exclude`에 제외합니다.
프로젝트의 추적 중인 설정은 바꾸지 않습니다. 안전한 제외 또는 안내 파일 생성이
불가능해도 수동 명령으로 공유할 수 있습니다. 이미 광고 중인 세션이 있으면 두 번째
주최자는 시작하지 못합니다. 백그라운드 프리뷰에서는 참여 창을 띄우지 않으며,
연결 도중 대상 창이나 내용이 바뀌면 그 창을 덮어쓰지 않고 `:buffer`로 공유 버퍼를 열 수 있습니다.

양쪽 모두 새로 열린 공유 버퍼에서 편집합니다. 기존 NFS 파일 버퍼를 따로 계속
수정하지 마세요. 동시 삽입과 겹치는 삭제는 편집 연산을 병합하며 상대 버퍼 전체를
자신의 내용으로 덮어쓰지 않습니다.

| 명령 / 키 | 동작 |
| --- | --- |
| `<leader>Ps` | 공유 시작 |
| `<leader>Pj` | 현재 파일의 공유 세션 참여 |
| `<leader>Pq` | 공유 종료 |
| `<leader>Pi` | 공유 상태 확인 |
| `:Peerpad [포트] [바인드주소]` | 현재 소스 버퍼를 공유하고 알림 파일 생성; 기본은 `0.0.0.0`의 빈 포트 |
| `:PeerpadJoin [<호스트> <포트> <토큰>]` | 현재 파일의 공유 세션 또는 지정한 세션에 참여 |
| `:PeerpadStatus` | 주최자·참가자, 변경 번호, 대기 중인 편집 수, 참가자별 커서 위치 확인 |
| `u`, `Ctrl+r` | 자신의 편집만 undo/redo; 버퍼 변경마다 한 단계 |
| 주최자의 공유 버퍼에서 `:w` | 동기화된 내용을 원본 소스 버퍼를 통해 저장 |
| `:PeerpadStop` | 연결 종료; 주최자는 서버도 종료 |

공유 버퍼는 별도의 `acwrite` 버퍼이며 자체 메모리 undo를 사용합니다. 원본 버퍼와
기존 영구 undo는 유지됩니다. 소스 전용 LSP·아웃라인·포매팅·프로젝트 분석은 공유
버퍼에 붙지 않으며, 파일타입 구문 색상과 기본 편집은 사용할 수 있습니다.
공유 버퍼에서는 기존 undo 브라우저나 `:undo` 대신 `u`·`Ctrl+r`를 사용하세요.

저장은 주최자만 담당합니다. 참가자의 저장, 다른 경로 쓰기, 파일 덧붙이기는 차단합니다.
주최자의 편집이 아직 동기화되지 않았거나 원본 버퍼·디스크 내용이 세션 밖에서 바뀌면
저장을 거부합니다. 연결이 끝나면 종료 알림을 표시합니다. 공유 내용이 열린 원본과 같고
대기 편집이 없으면 창 분할을 유지한 채 원본으로 돌아가고 중복 공유 버퍼를 제거합니다.
내용이 다르거나 원본을 확인할 수 없으면 `[disconnected]` 복구 버퍼를 남깁니다.
미저장 내용은 일반 버퍼로 복사해 저장하세요. 종료 시 원본을 덮어쓰거나 다시 읽지 않습니다.
자동 재접속이나 Neovim 종료 후 세션 복원은 제공하지 않습니다.

공유 명령을 쓰거나 연 파일에 알림 파일이 있을 때만 모듈을 불러오며, 그 밖에는 파일을
읽을 때마다 `stat` 한 번만 합니다. 파일 폴링·유휴 타이머는 없고 커서 이동은 공유 버퍼에서만 전송하며, 접속과
인증 제한(5초·10초)에만 일회성 타이머를 씁니다. 편집 시 변경 범위만 읽지만 문서 병합에는 비용이 있습니다. 문서는 1 MiB까지이고
편집 대기열과 히스토리에도 상한이 있습니다. 참가 인원은 주최자를 포함해 8명이며,
`:Peerpad` 전에 `vim.g.flash_share_max_peers`(2~64)로 바꿀 수 있습니다. 인원이 찬
세션에 참여하면 연결 초기화 대신 그 사실을 알려 줍니다.
여러 파일 공유는 지원하지 않습니다.

참가자마다 다른 색으로 커서 위치를 강조하고, 그 줄 끝에 `사용자@IP`를 표시합니다.
IP는 주최자 서버가 실제 접속에서 확인한 주소라 참가자가 위조할 수 없으며, 주최자와
같은 호스트의 참가자는 그 호스트 주소로 표시합니다. 사용자 이름은 참가자가 직접 보고한
값이며, 같은 표시가 겹치면 나중 참가자에 `#<번호>`를 붙입니다. 커서는 해당 참가자의 편집이 동기화된 뒤에 전송되고, 다음 갱신 전까지 이후
편집을 따라 움직입니다. 색은 `LiveSharePeer1`..`LiveSharePeer6`으로 바꿀 수 있습니다.

공유 텍스트의 마지막 줄바꿈은 고정됩니다. 이를 지우거나 그 뒤에 쓰는 편집은 결과가 같은
앞쪽 편집으로 바꿔 보내므로, 파일 끝 근처의 동시 편집도 항상 올바른 텍스트로 합쳐집니다.

TCP 연결은 토큰으로 인증하지만 **암호화하지 않습니다**. 네트워크를 엿볼 수 있거나
알림 파일을 읽을 수 있는 사람은 참여해 텍스트를 볼 수 있습니다. 상대가 보낸 텍스트의
modeline은 옵션을 바꾸지 못합니다. 신뢰할 수 있는 내부망이나
SSH 터널에서 사용하고 공용 인터넷에 포트를 노출하지 마세요.

### 라이브쉐어만 갱신하기

`nvim/.config/nvim/lua/peerpad/`에는 별도 `peerpad.nvim` 저장소와 동일한
모듈 4개가 있습니다. ***FLASH*** 버퍼 사용 정책은
`lua/peerpad/config.lua`에 둡니다. 공통 명령·단축키·자동 탐색은 `peerpad.setup()`에서
한 번만 등록합니다. 같은 상위 디렉터리의 별도 저장소를 수정한 뒤,
dotfiles 디렉터리에서 아래처럼 모듈만 복사하면 됩니다.

```sh
cp -R ../peerpad.nvim/lua/peerpad/. nvim/.config/nvim/lua/peerpad/
```

플러그인 설치나 다른 ***FLASH*** 코드 수정은 필요 없습니다. 갱신 후 Neovim을 재시작하세요.
***FLASH***와 Package-based Neovim은 `:Peerpad`, `:PeerpadJoin`, `:PeerpadStop`, `:PeerpadStatus`
명령어를 동일하게 사용합니다.

## 설정 구조

[진입점](../nvim/.config/nvim/init.lua)이 인접한 [기능 모듈](../nvim/.config/nvim/lua/)을
명시된 의존 순서로 불러옵니다. 심볼릭 링크의 실제 경로를 해석하며 Package-based Neovim 모듈·플러그인과
runtime을 분리합니다.

| 담당 모듈 | 역할 |
| --- | --- |
| `options`, `keymaps`, `theme` | Runtime, 기본 설정, 편집 키, 테마 |
| `buffer_policy`, `bigfile` | 소스·편집창 구분과 분석 가능 여부 |
| `project`, `jobs`, `state` | 루트, 취소 가능한 작업, 공유 인터페이스·상태 |
| `explorer`, `navigation`, `buffers` | 디렉터리 편집, 편집창 선택, 버퍼 수명 관리 |
| `pickers`, `search`, `editing` | 검색 UI, 결과, undo 미리보기 |
| `git`, `git_actions` | 상태, sign, diff, blame, 스테이징과 hunk 작업 |
| `lsp/`, `tags`, `completion`, `format`, `diagnostics` | 언어 도구와 편집 지원 |
| `outline`, `breadcrumb_symbols`, `breadcrumbs`, `context` | 심볼 캐시, 아웃라인, 문맥 탐색 |
| `dashboard`, `terminal`, `session` | 보조 UI와 세션 수명 관리 |
| `peerpad/` | 공동 편집 설정(`config.lua`), 연결, 연산 병합, 사용자별 undo |
| `statusline`, `indent`, `syntax`, `whichkey` | 네이티브 표시와 키 안내 |

LSP 코드는 `lua/lsp/`에 모았습니다. `servers.lua`는 명령어·파일타입 목록,
`init.lua`는 실행 파일 탐색·클라이언트 등록, `python.lua`는 Python 환경 선택,
`keymaps.lua`는 연결된 버퍼의 단축키, `lifecycle.lua`는 재시작·분리·새 파일 복구,
`diagnostics.lua`는 진단 응답과 숨겨진 버퍼의 갱신 누락 보충을 담당합니다.
최상위 `lua/diagnostics.lua`는 진단 UI 단축키를 담당합니다.

기능 내부 상태는 local에 두고 공유 인터페이스는 `state.lua`를 거치며 구현은 담당 모듈이
소유합니다. `buffer_policy.lua`는 편집 가능한 소스, 분석 가능한 버퍼, 보조 창을 구분합니다.
비동기 작업은 시작 전과 결과 반영 전에 정책을 확인합니다. `NopackBufferRestricted`를
받은 각 기능이 요청 취소·UI 정리를 담당하고, LSP 해제는 큰 파일 감지기가 아닌 `lsp/lifecycle.lua`가
소유합니다. 루트 무효화와 프로세스 취소는 각각 `project.lua`, `jobs.lua`가 담당합니다.
성능 조사 시 파일 크기보다는 담당 기능의 이벤트와 콜백을 확인하세요.
