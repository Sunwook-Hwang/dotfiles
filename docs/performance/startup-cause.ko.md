# 시작 지연 원인 분석과 수정

[English](startup-cause.md) | [한국어](startup-cause.ko.md) · [Raw data](startup-cause-results.json)

2026-10-04, main `a19d45a`를 기준으로 2,000줄 Python 파일의 시작 구간을 분석했습니다.
수정 후 결과는 raw data에 포함한 미커밋 `options.lua` 패치를 적용한 상태입니다.
이전 실험의 큰 격차를 Neovim 자체의 근본적인 성능 한계라고 해석할 근거는 없습니다.

## 확인한 원인

1. **테스트 환경의 터미널 무응답.** Neovim 0.12.5는 사용자 설정 전에 OSC11/DSR 질의로
   배경색 지원을 확인하며 최대 100 ms의 `vim.wait`를 실행합니다. 무응답 PTY의 시작 로그에서
   `vim._core.defaults`가 약 114–116 ms였고, 모든 배경색/DSR 질의에 응답하자 대표 로그에서
   약 1.5–1.6 ms로 줄었습니다. Lua 인터프리터 초기화 자체는 해당 로그에서 약 0.2–0.3 ms였습니다.
2. **사용하지 않는 Python 호스트 탐색.** 내장 Python ftplugin의 `has('python3')`가
   `pynvim`용 인터프리터를 동기식으로 찾습니다. 수정 전 대표 로그에서 `provider/python3.vim`은
   약 46–49 ms를 소비했습니다. FLASH는 Python 호스트 기반 완성을 사용하지 않으므로,
   기본 자동 탐색을 끄고 사용자가 `python3_host_prog`를 지정하면 활성화하도록 했습니다.

터미널 프로토콜이나 `ttyfast`를 설정에서 억지로 끄지 않았습니다. 첫 원인은 측정 환경을
바로잡아 분리했고, 두 번째 원인만 FLASH 코드에서 수정했습니다.

## 터미널 응답을 제공한 결과

아래 값은 프로세스 실행부터 초기 redraw 준비 신호 관측까지의 중앙값입니다.
각 행의 FLASH·Vim은 같은 회차 묶음에서 순서를 순환해 각각 7회 실행했습니다.
Vim 설정은 변경하지 않았으며 두 묶음의 Vim 수치 차이는 실행 변동입니다.

| 상태 | FLASH (ms) | Plugin-free Vim (ms) |
| --- | ---: | ---: |
| Python 호스트 탐색 수정 전 | 102.13 | 71.73 |
| Python 호스트 탐색 수정 후 | 60.94 | 78.43 |

FLASH의 전후 중앙값 차이는 **40.3% 감소**입니다. 수정 후 묶음에서는
FLASH가 Vim 설정보다 **22.3% 적은 시간**이 걸렸습니다. 실제 화면 표시·입력 반응 속도나
다른 언어·서버에서의 우위를 보장하는 결과는 아닙니다.

## 최소 런타임 비교

filetype plugin·indent·syntax를 양쪽에서 켜고, Neovim의 Python 호스트 탐색과 터미널 무응답을
제거한 최소 설정을 각각 7회 실행했습니다. 공통 하네스의 Neovim LSP 차단 코드도 포함하므로
완전한 `nvim -u NONE` 실험은 아닙니다.

| 구간 | 최소 Neovim (ms) | 최소 Vim (ms) |
| --- | ---: | ---: |
| 프로세스 실행 → 준비 신호 | 45.59 | 38.31 |
| 설정 진입 → 첫 redraw | 13.19 | 15.67 |

전체 시간에는 약 7 ms 차이가 남지만 내부 구간에서는 Neovim이 짧았습니다.
특정 빌드·프로세스 초기화·측정 변동을 포함한 차이를 언어나 구조의 피할 수 없는 한계로
단정하지 않습니다. 초기의 150 ms 이상 격차 대부분은 별도의 확인된 원인이었습니다.

## 기능 확인과 한계

- Neovim 0.12.5와 0.13 개발 버전에서 Python syntax·indent, 실제 ty 연결·정의 탐색·완성을 확인했습니다.
- Python 실행 파일, ty/Pyright, 포매터는 끄지 않았습니다. 별도 `:python3`/pynvim 인터페이스만 기본 비활성화하며 명시적 호스트 지정으로 사용할 수 있습니다.
- Mac mini M4, 동일한 격리 경로·PTY·생성 파일을 사용했습니다. 최소 설정 탐색 21회, 응답 조건 수정 전 28회, 수정 후 28회, 최소 조건 통제 14회입니다. 불완전한 최초 터미널 응답 시도와 단발 진단 로그는 순위 데이터에서 제외했습니다.
- 통제 장치는 OSC11 검정 배경색과 DSR 정상 응답만 제공합니다. 실제 터미널 에뮬레이터가 아니며 모든 프로토콜을 재현하지 않습니다.
- 원본 측정과의 경계·터미널 조건 차이를 구분해야 합니다. 실제 SSH·NFS·낮은 성능 서버의 지연을 직접 측정하지 않았습니다.

## Sources

- [Neovim 0.12.5 defaults: background-query wait](https://github.com/neovim/neovim/blob/v0.12.5/runtime/lua/vim/_core/defaults.lua)
- [Neovim 0.12.5 Python ftplugin: provider capability probe](https://github.com/neovim/neovim/blob/v0.12.5/runtime/ftplugin/python.vim)
- [Neovim Python provider](https://github.com/neovim/neovim/blob/v0.12.5/runtime/lua/vim/provider/python.lua)
