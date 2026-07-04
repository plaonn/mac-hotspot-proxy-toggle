# 로드맵

이 문서는 공개 가능한 future direction만 유지함. Active work tracking은 여기서 중복 관리하지 않음.

## 가까운 후보

- Event-driven helper opt-in mode를 실제 macOS network transition에서 검증하고, 문제가 없으면 기본 trigger mode 전환 여부를 검토.
- 사용할 수 없는 dependency에 대한 diagnostics 개선.

## 나중 후보

- 실제 use case가 생기면 `PROXY_TYPE` 뒤에 PAC configuration 같은 추가 backend 도입.
- Homebrew formula 같은 packaging option 검토.

## 비목표

- 휴대폰 쪽 proxy server 관리.
- 구체 requirement가 생기기 전 authenticated SOCKS proxy 지원.
- Persistent shell loop 실행.
- Public repository file에 private operator task state 저장.
