# 프로젝트 지침

이 저장소는 public macOS 유틸리티 저장소임. Public 파일에는 개인 Todoist ID, Codex thread ID, private absolute path, 로컬 router 주소, SSID, 로그, operator-only note를 넣지 않음.

## 기준 문서

- `docs/REQUIREMENTS.md`: RDD root goal, requirement, rationale, failure-prevented statement, loop boundary.
- `docs/SPEC.md`: 현재 public 동작과 구현 contract.
- `docs/ROADMAP.md`: 공개 가능한 future direction과 non-goal.
- `README.md`: 사용자-facing 설치와 사용 가이드.

## 구현 규칙

- runtime command는 single-shot reconciler로 유지함. 현재 network/proxy state를 inspect하고, 필요한 최소 macOS proxy 변경만 적용한 뒤 종료해야 함.
- 설치, LaunchAgent templating, uninstall 로직은 `bin/hotspot-proxy-toggle` 밖에 둠.
- generic proxy 프로젝트 naming을 유지함. 현재 구현은 SOCKS5만 지원할 수 있지만, 새 proxy type은 명시적인 `PROXY_TYPE` backend로 추가해야 함.
- event-driven helper를 의도적으로 도입하고 문서화하기 전에는 long-running daemon을 추가하지 않음.
- generated local config, log, LaunchAgent output, `.private/` 파일을 commit하지 않음.
- 이 프로젝트의 durable 문서 기본 언어는 한국어임. 외부 사용자-facing artifact를 영어로 만들 필요가 있으면 먼저 maintainer에게 확인함.

## 검증

Script-only 변경에서는 아래를 실행함:

```bash
bash -n bin/hotspot-proxy-toggle install.sh uninstall.sh
```

동작이 바뀌면 host macOS 환경에 맞는 dry-run 또는 status check도 실행하고, 수행하지 못한 check가 있으면 명시함.
