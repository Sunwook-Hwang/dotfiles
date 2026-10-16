# Package-based Neovim 설정 구조

[English](package-based-neovim.md) | [한국어](package-based-neovim.ko.md)

`nvim-pack/.config/nvim-pack/init.lua`는 인접한
`nvim-pack/.config/nvim-pack/lua/`에서 기능 모듈을 불러옵니다.
플러그인을 설정하기 전에 큰 파일 보호를 등록합니다.
심볼릭 링크를 포함해 진입점의 실제 경로를 해석하므로, 옆에 `lua/`가 있으면
`nvim -u /path/to/init.lua`로도 실행할 수 있습니다.

***FLASH***의 `nvim/.config/nvim/init.lua`는 자신의 `lua/`만 불러오며
Package-based Neovim 모듈과 독립적입니다. 서버로 옮길 때는 해당 설정 디렉터리 전체를
가져가세요. `vi`는 항상 ***FLASH***를 실행하고, `pvi`는 `NVIM_APPNAME=nvim-pack`을
선택합니다. 플러그인과 Mason 도구는 설정 파일과 별개이므로 인터넷이 없는 서버에서는
이들도 미리 준비해야 합니다.

| 모듈 | 역할 |
| ------------------------ | ----------------------------------------------------- |
| `options.lua` | 기본 기능 비활성화, 편집기 옵션, 리더 키 |
| `buffer_policy.lua` | 공통 버퍼 실행 조건, 보호된 동작, 제한 전환 이벤트 |
| `keymaps.lua` | 편집, 창 이동·크기 조절, 커서 단어 강조 |
| `window.lua` | 편집창 확대·복원과 분할 배치 추적 |
| `files.lua` | 이벤트 기반 외부 파일 변경 반영 |
| `bigfile.lua`            | 네이티브 열기·다시 읽기·변경 범위 보호                |
| `plugins.lua` | `vim.pack` 패키지 등록 |
| `context.lua` | 네이티브 스티키 문맥과 갱신 생명주기 |
| `ui.lua`                 | 알림, 입력창, 인덴트, 범위 탐색, dim, 프로파일러      |
| `git.lua` | Gitsigns, 변경 구간 동작, 인라인 blame |
| `session.lua` | 세션 저장·복원 |
| `clipboard.lua` | SSH 클립보드 복사 |
| `whichkey.lua` | 단축키 안내 |
| `pickers.lua`            | Telescope 설정, 네이티브 퍼지 정렬과 검색 단축키      |
| `breadcrumbs.lua` | 네이티브 상태줄 문맥, 범위 이동, 토글 |
| `breadcrumb_symbols.lua` | LSP 심볼 계층 캐시와 요청 생명주기 |
| `outline.lua` | Aerial 아웃라인과 커서 추적 |
| `terminal.lua` | 재사용 터미널, 재시작, 전체화면, Git 상태 |
| `format.lua` | Conform 포매터 등록과 포매팅 |
| `completion.lua` | 네이티브 자동완성과 스니펫 |
| `project.lua` | 공통 프로젝트 루트, Python 라이브러리 경계, 루트 캐시 |
| `explorer.lua` | Oil 탐색기 설정·토글과 작업 디렉터리 갱신 |
| `lsp.lua`                | 네이티브 LSP, 기능별 단축키, 서버, Python, Mason      |
| `buffers.lua` | 탭라인, 버퍼 선택·삭제 |
| `statusline.lua` | 상태줄 표시와 캐시 무효화 |
| `theme.lua` | 최종 편집기 명령과 색상 테마 |

`dashboard.lua`는 Alpha 대시보드를 설정합니다. `pickers.lua`는 첫 검색 때
Telescope와 Plenary, fzf-native, UI-select 확장을 불러옵니다.
`undo_picker.lua`는 분리된 임시 버퍼에서 Telescope Undo를 실행하므로,
기록을 살펴보는 것만으로 편집 버퍼·LSP·Peerpad에 변경이 전달되지 않습니다.
`native_build.lua`는 설치·소스 업데이트 후 fzf-native를 빌드합니다.

Oil·Aerial·Gitsigns·Conform·Persistence·Which-key는 기존 역할을 유지합니다.
터미널·상태칼럼·상태줄·버퍼바·스티키 문맥·상태줄 문맥은 네이티브 구현입니다.
버퍼 삭제는 `mini.bufremove`로 창 배치를 보존합니다.
Snacks와 Toggleterm 의존성은 없습니다.

자동 편집·코드 분석 기능은 `buffer_policy.allows(buf)`를 사용합니다.
로드된 일반 버퍼는 큰 파일로 제한되지 않은 경우 실행 대상입니다.
큰 파일에서도 유지할 수동 소스 동작은 `is_source(buf)`를 사용할 수 있습니다.
이 함수는 버퍼 목록과 세션을 위해 아직 로드되지 않은 일반 버퍼도 인식합니다.
수동 포매팅은 코드 분석과 같은 보호 제한을 따릅니다.

코드 분석 단축키는 `guard(callback)`으로 보호하고, 기능 모듈마다 `large_file`
검사를 중복 구현하지 않습니다. `bigfile.lua`가 파일 크기와 편집 중 증가를 검사한 뒤
`restrict(buf)`를 한 번 호출합니다. 공통 정책은
`PackBufferRestricted`를 발생시킵니다. 각 기능은 Git·LSP 연결, 대기 요청,
화면 표시, 아웃라인 데이터 등 자신의 상태를 정리합니다.
동작 실행 시와 비동기 결과 도착 시 모두 실행 조건을 확인하며,
전역 기본값과 다른 버퍼의 설정은 유지합니다.

상태줄 문맥은 Dropbar나 들여쓰기 추측 없이 캐시된 LSP 문서 심볼 계층을 표시합니다.
`<leader>Td`로 토글하고, 심볼을 클릭하면 선언 위치로 이동합니다.
커서 이동과 상태줄 다시 그리기는 심볼 요청을 발생시키지 않습니다.
파일 변경이나 LSP 연결 변경 시 캐시를 갱신하고, 기능을 끄거나 버퍼를 제한·언로드하면
대기 중인 작업을 취소합니다. 심볼을 지원하지 않는 파일은 경로만 표시합니다.
조건문·반복문은 언어 서버가 심볼로 제공할 때만 나오며,
Dropbar의 형제 심볼 메뉴는 구현하지 않습니다.
Python 환경 선택도 이전 요청을 취소하고, 원본 버퍼가 언로드·이름 변경·제한되면
늦게 도착한 결과를 버립니다.

새 기능의 실행 조건은 `buffer_policy`에서 가져옵니다. 큰 파일 판정은
`bigfile.lua`만 담당합니다. 플러그인의 실행 필터·단축키·종료 처리를 연결해야 하며,
버퍼 플래그 하나만 설정한다고 외부 플러그인이 자동으로 차단되는 것은 아닙니다.

***FLASH***는 독립적인 `buffer_policy.lua`로 같은 정책을 구현하며,
Package-based Neovim 모듈이나 플러그인을 불러오지 않습니다.
Plugin-free Vim은 `.vimrc` 내부의 `IsSource`, `BufferAllows`, `RestrictBuffer`로
같은 정책을 구현합니다. 두 설정의 `NopackBufferRestricted` 이벤트는 관련 자동 작업을
취소하고 화면 표시를 정리합니다.

세 설정 모두 2 MiB 초과, 50,000줄 초과, 한 줄 10,000바이트 초과 파일을 보호합니다.
파일 열기 검사와 편집 중 변경 범위 검사는 같은 제한을 적용합니다.
네이티브 Git 사인의 diff 제한처럼 개별 기능이 더 엄격한 작업 한도를 둘 수 있습니다.
보호는 버퍼를 폐기할 때까지 유지되며, 버퍼 목록·프로젝트 탐색·세션은
보호되었거나 언로드된 소스 버퍼도 인식합니다.

커서 지연을 조사할 때는 관련 기능 모듈의 이벤트와 콜백부터 확인하세요.
파일 분리 자체는 갱신 주기를 바꾸거나 지연 로딩을 도입하거나 성능을 높이지 않습니다.
실행 중 개별 모듈을 다시 불러오면 단축키와 이벤트가 다시 등록될 수 있으므로,
설정을 수정한 뒤에는 Neovim을 재시작하세요.

## 편집과 내비게이션

Telescope 검색창과 네이티브 터미널로 아래 동작을 ***FLASH***와 맞춥니다.

| 키 | 동작 |
| ---------------------------- | ----------------------------------------------------------------------- |
| `*` / `#` | 커서를 움직이지 않고 정방향 / 역방향 단어 검색 등록; `n` / `N`으로 이동 |
| `Ctrl-w o` / `Ctrl-w Ctrl-o` | 편집창 확대와 원래 분할 배치 복원 |
| `Ctrl-t` | 같은 하단 터미널 셸을 표시·숨김 |
| `<leader>TT` | 기존 셸을 종료하고 편집창의 `:pwd`에서 새 셸 시작 |
| `Ctrl-\` 다음 `\` | 편집창·사이드바·터미널 어디서든 터미널 전체화면 토글 |
| `<leader>gg`                 | lazygit 실행; 없으면 Telescope Git 상태 목록 표시                       |
| `<leader>lD` / `<leader>sd` | 현재 버퍼 / 전체 버퍼 진단 목록, 오류부터 표시 |
| `<leader>sk` | 키맵 검색; 설정한 리더 키를 `<leader>`로 표시 |

편집창 확대 중 편집용 분할을 추가하면 새 배치를 기준으로 삼고, 보조 창을 여는 동작은
저장된 배치를 지우지 않습니다. 터미널 전체화면은 셸을 유지하면서 이전 창으로 돌아오며,
터미널이 숨겨졌거나 아직 없는 상태에서도 작동합니다. 두 번째 `\`까지 `Ctrl`을 누르고
있어도 됩니다. `Ctrl-\ Ctrl-n`은 기존처럼 터미널 일반 모드로 전환합니다.
세션 저장 시 임시 편집창·터미널 확대를 복원하고 보조 버퍼를 제외합니다.
Neovim 0.13의 네이티브 세션 저장 이벤트에도 같은 필터를 적용합니다.

진단 목록은 색으로 구분한 굵은 `E/W/I/H` 접두사를 사용합니다. LSP 연결이 끊겨도 진단
확인과 LSP 재시작 키를 쓸 수 있습니다. 활성 상태줄은 굵게, 비활성 상태줄은 일반 굵기로
표시합니다.

Neovim 0.13에서는 네이티브 `autoread` 파일 감시를 사용합니다. 0.12에서는 소스 버퍼로
이동할 때 그 파일만 확인하고, 터미널이나 다른 앱에서 돌아올 때 로드된 파일을 확인합니다.
커서 이동마다 검사하는 폴링은 추가하지 않으며, 저장하지 않은 편집을 덮어쓰지 않습니다.

## 파일 탐색기

[Oil](https://github.com/stevearc/oil.nvim)을 파일 탐색기로 사용합니다.
`<leader>e`로 왼쪽 40칸 사이드 창에 프로젝트 루트의 파일 목록을 열고, 다시 누르면
탐색기만 닫습니다. 편집창은 유지하며, 파일은 편집창에서 열고 폴더는 탐색기 안에서
이동합니다. 프로젝트·Python 라이브러리 루트 판정은 ***FLASH***와 같은 기준입니다.
`:e directory/`로 연 디렉터리도 Oil이 처리합니다. 펼치는 트리가 아니라 폴더별 목록입니다.

파일 이름을 직접 수정하거나 `yy` / `p`로 항목을 복제하고 `dd`로 삭제한 뒤,
`:w`로 파일시스템 변경을 확인·반영합니다. 새 항목 이름 끝에 `/`를 붙이면 폴더를 만듭니다.
아이콘·줄 번호는 표시하지 않고, 숨김·Git ignore 파일도 기본으로 보입니다.
[oil-git.nvim](https://github.com/malewicz1337/oil-git.nvim)이 파일·폴더의 Git 상태를
비동기로 조회해 고정 폭 사인 칸에 표시합니다. `+` 추가, `M` 수정, `R` 이름 변경,
`D` 삭제, `C` 복사, `U` 충돌, `?` 추적되지 않음, `!` ignore 상태입니다.
Oil 파일시스템 감시는 꺼져 있으며, 자동 세션 저장에서는 Oil 버퍼와 창을 제외합니다.

Oil에서 지원하는 탐색 동작은 ***FLASH***와 같은 키로 맞췄습니다. `<localleader>`는
`vim.g.maplocalleader`를 따로 설정하지 않으면 `\`입니다. ***FLASH***의 폴더
펼치기·접기와 Git-ignore 파일만 따로 숨기는 토글은 Oil에서 지원하지 않습니다.

| 키 | 동작 |
| ------------------------------------------------------ | ----------------------------------------------- |
| `<leader>e` | Oil 열기·닫기 |
| `Enter` | 파일은 편집창에서 열기 / 폴더는 탐색기에서 이동 |
| `Ctrl-c` | 탐색기 닫기 |
| `-` / `<localleader>w` | 상위 폴더 / 편집기 작업 디렉터리 |
| `<localleader>p` | 항목 프리뷰 토글 |
| `<localleader>v` / `<localleader>s` / `<localleader>t` | 세로 분할 / 가로 분할 / 새 탭에서 열기 |
| `<localleader>d` / `<localleader>D` | 전역 / 탭 작업 디렉터리 변경 |
| `gr` | 목록과 Git 상태 갱신 |
| `g.` | 숨김 파일 토글 |
| `gs` | 정렬 기준 선택 |
| `gx` | 외부 앱에서 열기 |
| `g?` | Oil 단축키 도움말 |
| `Ctrl-h/j/k/l` | 기존 창 이동 유지 |
| `Ctrl-s` | 목록 편집 저장 |
| `Ctrl-t` | 재사용 하단 터미널 토글 |

## 실시간 공유

Package-based Neovim은 [peerpad.nvim](https://github.com/Sunwook-Hwang/peerpad.nvim)을
`vim.pack`으로 설치하고 `init.lua`에서 직접 설정합니다.
***FLASH***의 네이티브 공유 기능과 서로 연결할 수 있습니다.
`<leader>Ps`는 공유 시작, `<leader>Pj`는 참여, `<leader>Pq`는 연결 종료,
`<leader>Pi`는 세션 정보 확인입니다.
명령어는 `:Peerpad`, `:PeerpadJoin`, `:PeerpadStop`, `:PeerpadStatus`입니다.
통신 구현은 필요할 때만 불러오며, 공유 세션 탐색은 소스 파일을 읽을 때 한 번 수행합니다.
인터넷이 없는 서버에는 다른 Package-based Neovim 플러그인과 함께 이 패키지도 복사하세요.

NFS로 같은 파일을 보더라도 참여자 사이 TCP 연결이 필요합니다.
공유 원본 파일은 호스트만 저장합니다.

## 코드 범위와 성능 측정

`mini.indentscope`는 범위 탐색 키를 누를 때만 Treesitter 없이 들여쓰기를 분석합니다.
`[i` / `]i`는 범위 양 끝으로 이동합니다.
비주얼 모드나 연산자 대기 모드에서 `ii` / `ai`로 내부 / 전체 범위를 선택합니다.
예를 들어 `vii`는 내부 범위 선택, `dai`는 전체 범위 삭제입니다.
코드 범위 강조는 비활성화되어 있습니다.

Plenary의 LuaJIT 샘플링 프로파일러는 기본적으로 꺼져 있습니다.
`<leader>Dp`는 측정 시작·종료이며 종료하면 텍스트 결과를 엽니다.
`<leader>DP`는 결과를 다시 엽니다. 측정 중에는 실행 부담이 추가됩니다.
코드 줄별 성능 강조 기능은 제공하지 않습니다.

`<leader>Ti`는 indent-blankline 가이드, `<leader>TS`는 mini.animate 스크롤,
`<leader>Tm`은 Twilight dim을 토글합니다. 스크롤과 dim은 기본 OFF입니다.
이 기능들에는 Treesitter 파서가 필요하지 않습니다. 알림은 mini.notify,
입력창은 NUI를 사용하며 완성·강조 콜백을 요청하는 입력은 기본 입력창을 유지합니다.

## 검색

`<leader>f`는 파일, `<leader>st`는 프로젝트 본문, `<leader>t`는 현재 단어 또는 Visual 선택을 검색합니다.
여러 줄 선택도 지원합니다.
숨김 파일을 포함하며 Git ignore 규칙은 유지합니다.
`<leader>sp`는 테마를 미리 보고 취소하면 이전 테마를 복원합니다.
`gd` 결과가 하나면 바로 이동하고 여러 개일 때만 같은 결과로 Telescope를 엽니다.
LSP 요청을 중복 전송하지 않습니다. 미리보기는 bat·파서 없이 Vim syntax를 사용합니다.

fzf-native는 Telescope 내부에서 실행하는 C 퍼지 정렬기입니다.
파일·본문 검색에는 `ripgrep`이 필요합니다. 컴파일된 라이브러리 없이 복사했다면
`:PackBuildFzf`로 빌드하세요. macOS·Linux는 `make`와 C 컴파일러,
Windows는 CMake와 호환 C 빌드 도구가 필요합니다. 일반 시작 시에는 빌드하지 않습니다.
라이브러리를 불러올 수 없으면 안내 후 Telescope의 Lua 정렬기로 동작합니다.

## 릴리즈로 업데이트

설정과 플러그인은 별도로 업데이트합니다. `update_vims.sh`는 편집기 설정 3개
(`~/.vimrc`, `~/.config/nvim/`, `~/.config/nvim-pack/`)를 함께 설치합니다.
`update_pack.sh`는 pvi 플러그인과 해당 버전의 `nvim-pack-lock.json`만 설치하며
편집기 설정 파일은 교체하지 않습니다.

```sh
curl -fLO https://github.com/Sunwook-Hwang/dotfiles/releases/latest/download/update_vims.sh
curl -fLO https://github.com/Sunwook-Hwang/dotfiles/releases/latest/download/update_pack.sh
sh ./update_vims.sh
sh ./update_pack.sh nvim
```

인터넷 없는 서버에는 같은 [릴리즈](https://github.com/Sunwook-Hwang/dotfiles/releases/latest)의
스크립트 두 개, **Source code (zip)**, **nvimpack.zip**을 옮깁니다.
압축을 풀어둘 디렉터리에서 실행하세요.

```sh
sh ./update_vims.sh /path/to/dotfiles-release.zip
sh ./update_pack.sh nvim /path/to/nvimpack.zip
env NVIM_APPNAME=nvim-pack nvim
```

**nvimpack.zip**에는 등록된 모든 플러그인, Git 메타데이터, 라이선스와 잠금 파일이 들어 있고
편집기 설정은 없습니다. `update_pack.sh`는
`~/.local/share/nvim-pack/site/pack/core/opt/`와
`~/.config/nvim-pack/nvim-pack-lock.json`을 백업한 뒤 교체합니다.
`XDG_DATA_HOME`·`XDG_CONFIG_HOME`을 설정했다면 해당 경로를 사용합니다.
설정 업데이트는 설치된 잠금 파일을 보존하므로 두 스크립트의 실행 순서는 상관없습니다.
둘 다 업데이트할 때는 같은 릴리즈의 ZIP을 사용하세요.

zsh·Bash·C shell 모두 `sh`로 실행하고 `source`하지 않습니다.
두 스크립트 모두 `unzip`이 필요하며 다운로드할 때만 `curl`도 필요합니다.
패키지 설치에는 `make`와 C 컴파일러가 필요합니다. 기존 플러그인을 교체하기 전에
대상 컴퓨터용 fzf-native를 빌드하며, 로컬 ZIP 설치에는 인터넷이 필요하지 않습니다.
빌드나 교체가 실패하면 기존 설치를 보존·복구합니다.

Mason 도구, 세션과 undo 기록은 보존합니다. 편집기를 종료한 뒤 업데이트하고 다시 여세요.
Vim·Neovim 자체나 셸 별칭은 설치하지 않습니다. pvi 실행에는 Neovim 0.12+와 Git이
필요하며, LSP·포매터 등 도구 바이너리는 대상 OS·아키텍처에 맞게 별도로 준비합니다.

패키지 ZIP 생성 명령은 `python3 scripts/build_pack_release.py /path/to/nvimpack.zip`입니다.
빌드에는 Python 3.9+, Neovim, Git, `zip`이 필요하며, 설치된 플러그인 버전과 로컬
잠금 파일의 일치 여부를 확인하고 원본 소스·라이선스를 함께 포함합니다.
