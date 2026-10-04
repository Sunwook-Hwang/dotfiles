# 시작 시간 측정

[English](startup-cause.md) | [한국어](startup-cause.ko.md) · [Raw data](startup-cause-results.json)

2026-10-04, 커밋 `a9ec0d0`. Mac mini M4, Neovim 0.12.5, Vim 9.2에서 동일한 2,000줄 Python 파일을 열었습니다. LSP는 끄고 터미널 배경색·상태 질의에는 응답했습니다. 설정별 7회, 총 21회 실행한 중앙값입니다.

| 설정 | 시작 시간 (ms) | FLASH의 시간 증감률 |
| --- | ---: | ---: |
| ***FLASH*** | **52.69** | — |
| Package-based Neovim | 153.43 | -65.7% |
| Plugin-free Vim | 78.37 | -32.8% |

***FLASH***의 시작 시간은 Package-based Neovim보다 **65.7%**, Plugin-free Vim보다 **32.8% 짧았습니다**.

프로세스 실행부터 초기 redraw 준비 신호 관측까지 측정했습니다. 이 환경의 시작 시간이며, 전체 편집 속도나 실제 화면 표시 완료를 직접 측정한 결과는 아닙니다.
