# 시작 시간 측정 — ***FLASH*** vs Plugin-free Vim

[English](startup-cause.md) | [한국어](startup-cause.ko.md) · [Raw data](startup-cause-results.json)

2026-10-04 측정. Mac mini M4, Neovim 0.12.5, Vim 9.2에서 2,000줄 Python 파일을 열었습니다. LSP는 끄고 터미널 배경색·상태 질의에는 응답하도록 했습니다. 설정별 7회 실행한 중앙값입니다.

| 설정 | 시작 시간 (ms) |
| --- | ---: |
| ***FLASH*** | **60.94** |
| Plugin-free Vim | 78.43 |

이 비교에서 ***FLASH***의 시작 시간은 **22.3% 짧았습니다**.

프로세스 실행부터 초기 redraw 준비 신호 관측까지 측정했습니다. 실제 화면 표시 완료나 편집 반응 속도를 직접 측정한 값은 아니며, 이 실험 환경의 결과입니다.
