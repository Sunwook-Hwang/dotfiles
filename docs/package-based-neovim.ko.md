# Package-based Neovim 설정 구조

[English](package-based-neovim.md) | [한국어](package-based-neovim.ko.md)

`nvim-pack/.config/nvim-pack/init.lua`는 인접한
`nvim-pack/.config/nvim-pack/lua/`에서 기능 모듈을 불러옵니다.
모듈이 토글을 등록하기 전에 Snacks를 설정합니다.
심볼릭 링크를 포함해 진입점의 실제 경로를 해석하므로, 옆에 `lua/`가 있으면
`nvim -u /path/to/init.lua`로도 실행할 수 있습니다.

***FLASH***의 `nvim/.config/nvim/init.lua`는 자신의 `lua/`만 불러오며
Package-based Neovim 모듈과 독립적입니다. 서버로 옮길 때는 해당 설정 디렉터리 전체를
가져가세요. `vi`는 항상 ***FLASH***를 실행하고, `pvi`는 `NVIM_APPNAME=nvim-pack`을
선택합니다. 플러그인과 Mason 도구는 설정 파일과 별개이므로 인터넷이 없는 서버에서는
이들도 미리 준비해야 합니다.

| 모듈 | 역할 |
| --- | --- |
| `options.lua` | 기본 기능 비활성화, 편집기 옵션, 리더 키 |
| `buffer_policy.lua` | 공통 버퍼 실행 조건, 보호된 동작, 제한 전환 이벤트 |
| `keymaps.lua` | 편집, 창 이동·크기 조절, 커서 단어 강조 |
| `bigfile.lua` | Snacks 큰 파일 설정과 편집 중 증가 검사 |
| `plugins.lua` | `vim.pack` 패키지 등록 |
| `context.lua` | 네이티브 스티키 문맥과 갱신 생명주기 |
| `ui.lua` | Snacks 대시보드, 인덴트, 검색창 스타일, 터미널 배치 |
| `git.lua` | Gitsigns, 변경 구간 동작, 인라인 blame |
| `session.lua` | 세션 저장·복원 |
| `clipboard.lua` | SSH 클립보드 복사 |
| `whichkey.lua` | 단축키 안내 |
| `pickers.lua` | 검색창 단축키 |
| `breadcrumbs.lua` | 네이티브 상태줄 문맥, 범위 이동, 토글 |
| `breadcrumb_symbols.lua` | LSP 심볼 계층 캐시와 요청 생명주기 |
| `outline.lua` | Aerial 아웃라인과 커서 추적 |
| `terminal.lua` | 하단 터미널과 lazygit 토글 |
| `format.lua` | Conform 포매터 등록과 포매팅 |
| `completion.lua` | 네이티브 자동완성과 스니펫 |
| `project.lua` | 공통 프로젝트 루트, Python 라이브러리 경계, 루트 캐시 |
| `explorer.lua` | Oil 탐색기 설정·토글과 작업 디렉터리 갱신 |
| `lsp.lua` | 네이티브 LSP, Snacks 기능별 단축키, 서버, Python, Mason |
| `buffers.lua` | 탭라인, 버퍼 선택·삭제 |
| `statusline.lua` | 상태줄 표시와 캐시 무효화 |
| `theme.lua` | 최종 편집기 명령과 색상 테마 |

`ui.lua`는 `bigfile.lua`의 설정을 Snacks에 전달합니다. `explorer.lua`는 Oil을 설정하고
탐색기 터미널 단축키를 `terminal.lua`의 토글에 연결합니다. Snacks는 LSP 기능 지원 여부에
따른 단축키, 기능 토글, 조건에 맞는 버퍼 일괄 삭제도 담당합니다.
스티키 문맥·상태줄 문맥·상태줄 표시는 자체 구현과 기본 상태를 유지합니다.
Snacks를 사용하는 모듈은 설치된 `snacks` 플러그인을 직접 불러옵니다.
설정 모듈 이름은 `snacks` 같은 플러그인 진입점과 겹치지 않게 정했습니다.

자동 편집·코드 분석 기능은 `buffer_policy.allows(buf)`를 사용합니다.
로드된 일반 버퍼는 큰 파일로 제한되지 않은 경우 실행 대상입니다.
큰 파일에서도 유지할 수동 소스 동작은 `is_source(buf)`를 사용할 수 있습니다.
이 함수는 버퍼 목록과 세션을 위해 아직 로드되지 않은 일반 버퍼도 인식합니다.
수동 포매팅은 코드 분석과 같은 보호 제한을 따릅니다.

코드 분석 단축키는 `guard(callback)`으로 보호하고, 기능 모듈마다 `large_file`
검사를 중복 구현하지 않습니다. `bigfile.lua`가 파일 크기와 편집 중 증가를 검사한 뒤
`restrict(buf)`를 한 번 호출합니다. 공통 정책은 Snacks의 버퍼 기능을 끄고
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

## 파일 탐색기

Snacks Explorer를 [Oil](https://github.com/stevearc/oil.nvim)로 교체했습니다.
`<leader>e`로 왼쪽 40칸 사이드 창에 프로젝트 루트의 파일 목록을 열고, 다시 누르면
탐색기만 닫습니다. 편집창은 유지하며, 파일은 편집창에서 열고 폴더는 탐색기 안에서
이동합니다. 프로젝트·Python 라이브러리 루트 판정은 ***FLASH***와 같은 기준입니다.
`:e directory/`로 연 디렉터리도 Oil이 처리합니다. 펼치는 트리가 아니라 폴더별 목록입니다.

파일 이름을 직접 수정하거나 `yy` / `p`로 항목을 복제하고 `dd`로 삭제한 뒤,
`:w`로 파일시스템 변경을 확인·반영합니다. 새 항목 이름 끝에 `/`를 붙이면 폴더를 만듭니다.
아이콘·줄 번호는 표시하지 않고, 숨김·Git ignore 파일도 기본으로 보입니다.
기존 Snacks Explorer의 Git 상태 표시는 Oil 기본 기능에 없습니다.
파일시스템 감시는 꺼져 있으며, 자동 세션 저장에서는 Oil 버퍼와 창을 제외합니다.

| 키 | 동작 |
| --- | --- |
| `<leader>e` | Oil 열기·닫기 |
| `Enter` | 파일은 편집창에서 열기 / 폴더는 탐색기에서 이동 |
| `Ctrl-c` | 탐색기 닫기 |
| `-` / `_` | 상위 폴더 / 편집기 작업 디렉터리 |
| `Ctrl-p` | 항목 프리뷰 |
| `gv` / `gh` / `gt` | 세로 분할 / 가로 분할 / 새 탭에서 열기 |
| `gR` | 목록 갱신 |
| `g.` | 숨김 파일 토글 |
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

Snacks Scope는 Treesitter 없이 들여쓰기로 코드 범위를 탐색합니다.
`[i` / `]i`는 범위 양 끝으로 이동합니다.
비주얼 모드나 연산자 대기 모드에서 `ii` / `ai`로 내부 / 전체 범위를 선택합니다.
예를 들어 `vii`는 내부 범위 선택, `dai`는 전체 범위 삭제입니다.
코드 범위 강조는 비활성화되어 있습니다.

Lua Profiler는 기본적으로 꺼져 있습니다.
`<leader>Dp`는 측정 시작·종료이며, 종료하면 결과를 엽니다.
`<leader>DP`는 결과 다시 열기, `<leader>Dh`는 측정 결과 강조 토글입니다.
측정 중에는 실행 부담이 추가되며, 지원하는 Lua 호출만 기록합니다.
측정 중 등록한 Lua 자동 명령 콜백도 기록 대상입니다.
