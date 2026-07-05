# 로드맵

이 문서는 공개 가능한 future direction만 유지함. Active work tracking은 여기서 중복 관리하지 않음.

## 가까운 후보

- Event-driven 기본 mode와 hotspot-limited endpoint watchdog을 실제 macOS network transition에서 계속 검증.
- 사용할 수 없는 dependency에 대한 diagnostics 개선.
- Menu bar companion을 실제 macOS menu bar 사용에서 계속 검증.
- 실제 사용에서 필요하면 app settings window를 추가해 start/stop, launch at login, open config 같은 제어를 GUI로 제공.

## 나중 후보

- 실제 use case가 생기면 `PROXY_TYPE` 뒤에 PAC configuration 같은 추가 backend 도입.

## 비목표

- 휴대폰 쪽 proxy server 관리.
- 구체 requirement가 생기기 전 authenticated SOCKS proxy 지원.
- Persistent shell loop 실행.
- Runtime script 안에 menu bar UI를 직접 포함.
- Public repository file에 private operator task state 저장.
