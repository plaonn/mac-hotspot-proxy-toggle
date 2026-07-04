# 로드맵

이 문서는 공개 가능한 future direction만 유지함. Active work tracking은 여기서 중복 관리하지 않음.

## 가까운 후보

- Parser와 decision logic을 위한 작은 shell-based test harness 추가.
- 지원하지 않는 proxy type과 사용할 수 없는 dependency에 대한 diagnostics 개선.
- 프로젝트에 development setup이 문서화되면 `shellcheck` validation 추가.

## 나중 후보

- Polling 대신 network state change 시 `hotspot-proxy-toggle run`을 trigger하는 event-driven macOS helper 추가.
- 실제 use case가 생기면 `PROXY_TYPE` 뒤에 HTTP proxy, PAC configuration 같은 추가 backend 도입.
- Homebrew formula 같은 packaging option 검토.

## 비목표

- 휴대폰 쪽 proxy server 관리.
- 구체 requirement가 생기기 전 authenticated SOCKS proxy 지원.
- Persistent shell loop 실행.
- Public repository file에 private operator task state 저장.
