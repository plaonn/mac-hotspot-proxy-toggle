# 요구사항

이 문서는 이 프로젝트의 RDD source of truth임.

## R0: 루트 목표

- 요구사항: 고정된 핫스팟 라우터 IP나 수동 프록시 토글 없이, macOS 프록시 설정을 현재 휴대폰 핫스팟 context와 일치시킴.
- 근거: macOS는 프록시 설정을 network service 단위로 적용하지만, 휴대폰 핫스팟은 연결마다 라우터 IP가 바뀔 수 있음.
- 방지 실패: 사용자가 일반 Wi-Fi에서 stale proxy를 켜 둔 채로 두거나, 휴대폰 핫스팟 라우터 IP가 바뀔 때마다 proxy host를 수동 수정해야 하는 상황을 막음.
- 자동화 경계: 이 유틸리티는 설정된 network service의 macOS proxy setting을 변경할 수 있음. 휴대폰 설정, 휴대폰 위 proxy server 시작, credential 추론은 하지 않음.
- 비목표: 휴대폰 쪽 proxy server 관리, 구체 requirement 없는 authenticated SOCKS proxy 지원, persistent shell loop 실행, public repository file에 private operator task state 저장.

## R1: 핫스팟 범위의 프록시 활성화

- 요구사항: 현재 default route가 Wi-Fi이고 Wi-Fi network가 설정된 hotspot 조건과 일치할 때만 macOS proxy setting을 켬.
- 근거: macOS network service는 단일 SSID보다 넓은 범위이므로, 관련 없는 네트워크에서 proxy setting이 켜지면 안 됨.
- 방지 실패: 일반 Wi-Fi traffic이 휴대폰 전용 proxy 설정으로 routing되는 일을 막음.
- 명세: `WIFI_DEVICE` override가 없으면 macOS hardware port discovery로 Wi-Fi interface를 찾음. `HOTSPOT_SSIDS`는 exact match로 판단함. `STRICT_SSID=0`이면 `ANDROID_METERED` 같은 DHCP marker match를 허용함.
- 테스트: `hotspot-proxy-toggle evaluate`는 default route가 Wi-Fi device이고 hotspot 조건이 일치할 때만 `status=hotspot`을 보고함.
- 자동 테스트: `./tests/run.sh`는 exact SSID match, non-Wi-Fi default route, strict SSID mode의 DHCP marker fallback 차단을 검증함.

## R2: 동적 라우터 IP 해석

- 요구사항: 고정 host가 아니라 현재 Wi-Fi DHCP router IP를 proxy host로 사용함.
- 근거: 휴대폰 핫스팟 라우터 IP는 연결마다 바뀔 수 있음.
- 방지 실패: 같은 휴대폰 핫스팟에 다시 연결한 뒤 stale proxy host 설정이 남는 일을 막음.
- 명세: 매 reconciliation마다 `ipconfig getsummary <wifi-device>`의 `Router`를 읽음.
- 테스트: `hotspot-proxy-toggle status`는 hotspot candidate에서 감지된 `router=<ip>`를 포함함.
- 자동 테스트: `./tests/run.sh`는 감지된 router IP가 reconcile decision에 전달되는지 검증함.

## R3: Endpoint 확인 기반 프록시 상태

- 요구사항: 현재 핫스팟 라우터에서 설정된 proxy endpoint가 실제로 사용 가능할 때만 macOS proxy setting을 켬.
- 근거: 핫스팟에는 연결되어 있어도 휴대폰의 proxy server가 꺼져 있을 수 있음.
- 방지 실패: 사용할 수 없는 system-wide proxy를 켜서 애플리케이션 네트워크 연결이 깨지는 일을 막음.
- 명세: `PROXY_TYPE=socks5`와 `REQUIRE_PROXY_CHECK=1`일 때 `router:PROXY_PORT`로 SOCKS5 no-auth greeting을 보내고, proxy setting을 켜기 전에 `0500` 응답을 요구함. `PROXY_TYPE=http`에서는 proxy에 절대 URI 형식의 HTTP request를 보내고 `HTTP/` response line을 요구함. `407 Proxy Authentication Required`는 현재 auth 미지원이므로 실패로 처리함.
- 테스트: endpoint가 없으면 `run`은 `status=proxy-unavailable proxy_type=... action=off`를 보고하고 macOS proxy state를 끔.
- 자동 테스트: `./tests/run.sh`는 endpoint unavailable이면 off decision, available이면 current router로 on decision을 검증함.

## R4: 유지보수 가능한 자동화 경계

- 요구사항: 기본 자동화 trigger는 event-driven network-change helper로 두되, hotspot 상태에서만 endpoint watchdog을 저빈도로 실행함. Helper를 설치할 수 없거나 polling을 명시한 경우 polling LaunchAgent로 fallback함.
- 근거: event-driven helper는 불필요한 wakeup을 줄이고 반응 시간을 개선할 수 있음. Hotspot 연결은 유지되지만 휴대폰 쪽 proxy server만 중간에 on/off 되는 변화는 macOS network event로 관찰되지 않으므로 hotspot 상태에 한정한 endpoint watchdog이 필요함. polling fallback은 helper build dependency나 launchd helper lifecycle 문제가 있을 때 단순한 복구 경로를 제공함.
- 방지 실패: install-time 또는 daemon lifecycle 가정을 runtime reconciliation logic에 박아 넣는 일을 막음.
- 명세: `bin/hotspot-proxy-toggle run`은 정확히 한 번 reconcile하고 종료함. event helper는 network change event를 debounce하고 `hotspot-proxy-toggle run`을 child process로 호출함. Child output이 hotspot 상태이면 endpoint watchdog을 켜고, non-hotspot 상태이면 끔. polling LaunchAgent는 fallback 또는 명시적 `HOTSPOT_TRIGGER_MODE=polling` 경로에서 runtime command 밖에 설정함.
- 테스트: helper LaunchAgent는 helper를 호출하고, helper는 child process로 `hotspot-proxy-toggle run`을 호출함. polling fallback LaunchAgent `ProgramArguments`는 `hotspot-proxy-toggle run`을 호출함. `bin/hotspot-proxy-toggle`에는 persistent loop가 없음.

## R5: Public Utility 위생

- 요구사항: Public repository file은 private operator state를 노출하지 않음.
- 근거: 이 유틸리티는 public macOS project로 재사용될 수 있어야 함.
- 방지 실패: private Todoist ID, Codex thread ID, SSID, log, local absolute path, personal runtime state가 유출되는 일을 막음.
- 명세: Public docs는 동작과 사용법을 generic하게 설명함. Private planning과 Todoist mapping은 Git에서 ignore되는 `.private/` 아래에 둠.
- 테스트: `git status --short`에 `.private/` 내용, log, local config, generated plist file이 나오면 안 됨.

## R6: 명시적 Proxy Backend

- 요구사항: 지원하는 proxy backend는 `PROXY_TYPE`으로 명시하고, backend별 macOS proxy setting을 서로 섞지 않음.
- 근거: SOCKS5, HTTP Web Proxy, PAC은 macOS `networksetup` command와 endpoint semantics가 다름.
- 방지 실패: 새 proxy type을 추가하면서 SOCKS 전용 설정이나 검증을 잘못 재사용하는 일을 막음.
- 명세: `PROXY_TYPE=socks5`는 SOCKS firewall proxy를 desired backend로 보고 Web Proxy와 Secure Web Proxy를 끔. `PROXY_TYPE=http`는 Web Proxy와 Secure Web Proxy를 desired backend로 보고 SOCKS firewall proxy를 끔. Hotspot이 아니거나 endpoint를 사용할 수 없으면 지원하는 backend 전체를 끔. 지원하지 않는 값은 supported list와 함께 거부함.
- 테스트: `./tests/run.sh`는 `http` backend on decision, opposite backend off decision, unsupported `PROXY_TYPE` rejection을 검증함.

## R7: 상태 변경 Notification

- 요구사항: 사용자가 명시적으로 켠 경우, `run`은 실제 macOS proxy setting 변경이나 최종 reconciliation state 변경을 macOS notification으로 안내함.
- 근거: LaunchAgent 기반 자동 실행은 background에서 일어나므로 사용자는 proxy가 켜졌는지, 꺼졌는지, 또는 현재 Wi-Fi/SSID가 조건과 맞지 않아 동작하지 않는지 즉시 알기 어려움.
- 방지 실패: SSID나 network context가 바뀌었지만 proxy setting은 이미 꺼져 있어 write가 발생하지 않은 경우를 사용자가 놓치는 일을 막음.
- 명세: `NOTIFY_ON_CHANGE=1`이면 `run`당 최대 한 번 notification을 표시함. 실제 proxy setting 변경이 있거나, SSID/default route/hotspot match/endpoint availability를 반영한 state key가 이전 `run`과 달라졌을 때 표시함. 같은 state가 유지되거나 `DRY_RUN=1`이면 표시하지 않음. Notification message에는 SSID, router IP, local path 같은 환경별 값을 포함하지 않음. Notification 실패는 reconciliation 실패로 취급하지 않음.
- 테스트: `./tests/run.sh`는 notification이 opt-in이고, proxy enable, endpoint unavailable, proxy write 없는 SSID context 변경에서 최종 상태 notification이 생성되는지 검증함.
