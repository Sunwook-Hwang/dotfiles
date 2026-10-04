# 시작 시간 측정 — 세 가지 설정

[English](startup-marker.md) | [한국어](startup-marker.ko.md) · [Raw data](startup-marker-results.json)

2026-10-04, `a19d45a` 기준 측정. Mac mini M4, Neovim 0.12.5, Vim 9.2에서 LSP를 끄고 파일별·설정별 7회씩 총 63회 실행했습니다. 중앙값이며 증감률은 소요 시간 기준입니다.

**이 실험의 PTY는 터미널 질의에 응답하지 않았습니다. 응답 조건의 비교는 [측정 결과](startup-cause.ko.md)을 참고하세요.**

| 파일 | ***FLASH*** (ms) | Package-based Neovim (ms) | Plugin-free Vim (ms) | ***FLASH*** vs package | ***FLASH*** vs Vim |
| --- | ---: | ---: | ---: | ---: | ---: |
| source_2k | 233.28 | 274.71 | 76.52 | -15.1% | +204.9% |
| tracked_git | 195.44 | 245.57 | 74.60 | -20.4% | +162.0% |
| large_60k | 234.57 | 275.36 | 71.60 | -14.8% | +227.6% |

프로세스 실행부터 초기 redraw 준비 신호 관측까지 측정했습니다. 터미널 질의 대기 시간이 포함되어 있으며, 실제 화면 표시 완료나 편집 반응 속도를 직접 측정한 값은 아닙니다.
