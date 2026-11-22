# 요구사항

이 문서는 이 프로젝트의 RDD source of truth임.

## R0: 루트 목표

- 요구사항: 한 번 설정하면 사용자는 휴대폰 핫스팟을 오갈 때 프록시를 조작할 필요가 없어야 함. 기대한 연결이 이루어지지 않으면 메뉴에서 Mac이 확인한 상태와 이유를 알 수 있어야 함.
- 근거: macOS는 프록시 설정을 network service 단위로 적용하지만, 휴대폰 핫스팟은 연결마다 라우터 IP가 바뀔 수 있음.
- 방지 실패: 사용자가 일반 Wi-Fi에서 stale proxy를 켜 둔 채로 두거나, 휴대폰 핫스팟 라우터 IP가 바뀔 때마다 proxy host를 수동 수정해야 하는 상황을 막음.
- 자동화 경계: 이 유틸리티는 설정된 network service의 macOS proxy setting을 변경할 수 있음. 휴대폰 설정, 휴대폰 위 proxy server 시작, credential 추론은 하지 않음.
- 비목표: 휴대폰 쪽 proxy server 관리, 구체 requirement 없는 authenticated SOCKS proxy 지원, persistent shell loop 실행, public repository file에 private operator task state 저장.

## R1: 핫스팟 범위의 프록시 활성화

- 요구사항: 현재 default route가 Wi-Fi이고 Wi-Fi network가 설정된 hotspot 조건과 일치할 때만 macOS proxy setting을 켬.
- 근거: macOS network service는 단일 SSID보다 넓은 범위이므로, 관련 없는 네트워크에서 proxy setting이 켜지면 안 됨.
- 방지 실패: 일반 Wi-Fi traffic이 휴대폰 전용 proxy 설정으로 routing되는 일을 막음.
- 명세: `WIFI_DEVICE` override가 없으면 macOS hardware port discovery로 Wi-Fi interface를 찾음. `NETWORK_SERVICE` override가 없으면 Wi-Fi device에 대응하는 macOS network service를 자동으로 찾음. `HOTSPOT_SSID`는 단일 exact match로 판단함. macOS가 command-line SSID를 `<redacted>`로 반환하면 app bundle이 위치 권한 하에서 CoreWLAN으로 읽은 SSID를 private cache에 기록하고, runtime은 cache의 Wi-Fi device와 `ConnectionID`가 현재 connection과 모두 같을 때만 이를 사용함.
- 테스트: `hotspot-proxy-toggle evaluate`는 default route가 Wi-Fi device이고, current 또는 connection-bound cached SSID가 hotspot 조건과 일치할 때만 `status=hotspot`을 보고함.
- 자동 테스트: `./tests/run.sh`는 exact SSID match, redacted SSID의 current/stale connection cache, missing SSID, non-Wi-Fi default route, SSID mismatch를 검증함.

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
- 명세: endpoint check는 기본 안전장치임. `PROXY_TYPE=socks5`와 `REQUIRE_PROXY_CHECK=1`일 때 `router:PROXY_PORT`로 SOCKS5 no-auth greeting을 보내고, proxy setting을 켜기 전에 `0500` 응답을 요구함. `PROXY_TYPE=http`에서는 proxy에 절대 URI 형식의 HTTP request를 보내고 `HTTP/` response line을 요구함. `407 Proxy Authentication Required`는 현재 auth 미지원이므로 실패로 처리함.
- 합격 기준은 휴대폰 서버를 뒤늦게 켜는 상황임. 같은 핫스팟에서 다음 자동 검사까지 기다리거나 메뉴의 수동 재연결을 선택하면 Mac에 현재 주소와 포트가 적용되어야 함. 두 경로 모두 적용 결과를 읽어 확인한 뒤 연결됨을 표시함.
- 서버 응답이 나뉘어 도착해도 제한 시간 안에 프로토콜 응답이 완성되면 인식해야 함. Mac에서 확인한 인증 요구, 시간 초과, 예상 밖 응답을 구분해 전달함.
- 핫스팟 이탈 또는 종료 뒤에는 앞서 시작한 검사로 이전 연결이 다시 켜지면 안 됨. 실행 횟수 제한 중에 받은 마지막 네트워크 변경도 처리해야 함.
- 검증은 `tests/proxy.rb`, `tests/reconnect.rb`, `tests/helper.sh`에서 로컬 서버, 실제 helper, 격리된 설정으로 수행함. 휴대폰과 macOS 설정을 사용하는 현장 확인은 별도임.

## R4: 유지보수 가능한 자동화 경계

- 요구사항: 기본 자동화 trigger는 event-driven network-change helper로 두되, hotspot 상태에서만 endpoint watchdog을 저빈도로 실행함. Helper를 설치할 수 없거나 polling을 명시한 경우 polling LaunchAgent로 fallback함.
- 근거: event-driven helper는 불필요한 wakeup을 줄이고 반응 시간을 개선할 수 있음. Hotspot 연결은 유지되지만 휴대폰 쪽 proxy server만 중간에 on/off 되는 변화는 macOS network event로 관찰되지 않으므로 hotspot 상태에 한정한 endpoint watchdog이 필요함. polling fallback은 helper build dependency나 launchd helper lifecycle 문제가 있을 때 단순한 복구 경로를 제공함.
- 방지 실패: install-time 또는 daemon lifecycle 가정을 runtime reconciliation logic에 박아 넣는 일을 막음.
- 명세: `bin/hotspot-proxy-toggle run`은 정확히 한 번 reconcile하고 종료함. event helper는 network change와 connection-bound Wi-Fi identity cache 변경을 하나의 serial scheduler에서 debounce하고 `hotspot-proxy-toggle run`을 child process로 호출함. Child output이 hotspot 상태이면 endpoint watchdog을 켜고, non-hotspot 상태이면 끔. Menu companion은 identity cache를 갱신하지만 자동 reconciliation을 직접 실행하지 않음. polling LaunchAgent는 fallback 또는 명시적 `HOTSPOT_TRIGGER_MODE=polling` 경로에서 runtime command 밖에 설정함.
- 테스트: helper LaunchAgent는 helper를 호출하고 identity cache path를 전달함. Helper lifecycle test는 identity cache 변경이 reconcile scheduler에 들어가고 같은 directory의 무관한 state file 변경은 trigger하지 않는지 검증함. polling fallback LaunchAgent `ProgramArguments`는 `hotspot-proxy-toggle run`을 호출함. `bin/hotspot-proxy-toggle`에는 persistent loop가 없음.

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
- 합격 기준은 핫스팟을 떠났을 때 다른 네트워크에서 쓰던 설정으로 다시 연결되는 것임. 앱이 바꾸지 않은 설정과 사용자가 중간에 직접 변경한 값을 보존함. 원래 프록시를 사용하지 않았다면 비활성 상태로 돌아감.
- 활성화 중에는 선택한 backend만 사용함. 각 backend의 변경 전 값과 앱의 변경 내역은 로컬에 보관함. 인증 정보를 새로 입력해야 하는 기존 주소의 교체는 중단함.
- 반복 검사, 다른 라우터로 재연결, 프로세스 재시작, 쓰기 중단, 사용자 변경은 `tests/proxy.rb`에서 검증함.

## R7: 상태 변경 Notification

- 요구사항: 사용자가 명시적으로 켠 경우, `run`은 실제 macOS proxy setting 변경이나 최종 reconciliation state 변경을 macOS notification으로 안내함.
- 근거: LaunchAgent 기반 자동 실행은 background에서 일어나므로 사용자는 proxy가 켜졌는지, 꺼졌는지, 또는 현재 Wi-Fi가 설정한 hotspot이 아니라 동작하지 않는지 즉시 알기 어려움.
- 방지 실패: active Wi-Fi가 바뀌었지만 proxy setting은 이미 꺼져 있어 write가 발생하지 않은 경우를 사용자가 놓치는 일을 막음. 반면 Wi-Fi가 active route가 아니거나 router가 아직 없는 transient 상태의 불필요한 알림은 피함.
- 명세: `NOTIFY_ON_CHANGE=1`이면 `run`당 최대 한 번 notification을 표시함. 실제 proxy setting 변경이 있거나, hotspot match/endpoint availability를 반영한 state key가 이전 `run`과 달라졌을 때 표시함. default route가 Wi-Fi가 아니거나 Wi-Fi router가 아직 확인되지 않은 상태에서는 notification을 표시하지 않고 state file만 갱신함. 같은 state가 유지되거나 `DRY_RUN=1`이면 표시하지 않음. Notification은 hotspot proxy active, hotspot-but-proxy-unavailable, active-Wi-Fi-but-not-configured-hotspot을 서로 다른 title과 emoji로 구분함. 설치된 `Mac Hotspot Proxy Toggle.app`은 UserNotifications authorization을 관리하고 foreground에서도 banner/list presentation을 허용함. App sender가 authorization 또는 delivery request를 완료하지 못하면 `osascript` notification으로 fallback함. `LANGUAGE=auto`는 macOS 언어 설정을 읽고, `en` 또는 `ko` override를 지원함. Notification message에는 SSID, router IP, local path 같은 환경별 값을 포함하지 않음. Notification 실패는 reconciliation 실패로 취급하지 않음.
- 테스트: `./tests/run.sh`는 notification이 opt-in이고, proxy enable, endpoint unavailable, proxy write 없는 SSID context 변경에서 최종 상태 notification이 생성되는지, not-Wi-Fi/no-router에서는 notification 없이 state만 기록되는지, 한국어 locale override를 검증함. Notification presentation test는 foreground options에 banner와 list가 모두 포함되는지 검증함.

## R8: Menu Bar Companion

- 요구사항: 사용자가 명시적으로 켠 경우, macOS menu bar status area에 Mac Hotspot Proxy Toggle 상태 항목을 표시함.
- 근거: background helper와 notification만으로는 현재 상태를 상시 확인하거나 즉시 수동 reconcile을 실행하기 어려움.
- 방지 실패: 상태 표시 요구를 runtime script 안의 persistent UI loop로 구현해 single-shot reconciliation 경계를 깨는 일을 막음.
- 합격 기준은 메뉴를 열었을 때 실제 적용 상태를 알 수 있고, 핫스팟에서 연결 대기 중이면 한 번의 조작으로 다시 시도할 수 있는 것임. 자동 복구가 정상일 때에는 사용자 조작이 필요하지 않음.
- 현재 메뉴와 아이콘, 상태 파일 형식은 [UI](UI.md)와 [명세](SPEC.md)에 둠. UI와 helper는 같은 일회성 실행 명령을 사용함. 종료하면 진행 중인 실행을 정리하고 앱이 관리하던 설정을 복원함.

## R9: Finder 실행 가능한 App Bundle

- 요구사항: source install은 사용자가 Finder, Spotlight, Launchpad에서 실행할 수 있는 `Mac Hotspot Proxy Toggle.app`을 설치함.
- 근거: `Quit Mac Hotspot Proxy Toggle`로 menu/helper LaunchAgent를 내린 뒤 terminal command를 기억하지 않아도 쉽게 다시 시작할 수 있어야 함.
- 방지 실패: menu bar companion을 끈 사용자가 재시작하려면 launchctl 또는 installer를 다시 실행해야 하는 상황을 막음.
- 명세: `Mac Hotspot Proxy Toggle.app`은 기존 menu bar companion binary를 app bundle로 포장한 LSUIElement 앱임. 앱은 Dock icon을 표시하지 않고 menu bar item만 표시하며, display name과 bundle file name 모두 `Mac Hotspot Proxy Toggle`임. App bundle은 핫스팟 프록시 켜짐 상태 glyph를 기반으로 한 `MacHotspotProxyToggle.icns`를 포함하고 local source build에서는 bundle 전체를 ad-hoc sign함. Finder에서 앱을 실행하면 기존 helper 또는 polling LaunchAgent plist가 있는 경우 이를 다시 bootstrap/kickstart하고, 상태 menu를 표시함. App bundle은 hotspot/proxy decision이나 macOS proxy write policy를 재구현하지 않음. Source installer는 기본적으로 `~/Applications/Mac Hotspot Proxy Toggle.app`을 설치하고 이전 `~/Applications/MHP.app`을 제거하며, `HOTSPOT_APP=0`으로 생략할 수 있음.
- 테스트: `scripts/validate.sh`는 AppKit을 사용할 수 있는 macOS 환경에서 app bundle build를 검증함. `./tests/install.sh`는 app build 실패가 core install을 중단하지 않는지 검증함.

## R10: Settings Window

- 요구사항: `Mac Hotspot Proxy Toggle.app`은 사용자가 terminal config 편집 없이 필수 설정과 자동 시작 상태를 관리할 수 있는 Settings window를 제공함.
- 근거: 초기 설정에 필요한 값은 소수이며, background helper와 menu bar app은 사용자 관점에서 하나의 자동 실행 기능으로 동작해야 함.
- 방지 실패: 사용자가 proxy hotspot과 관련 없는 DHCP marker, Wi-Fi device, network service 같은 내부 knob를 잘못 설정하거나, background helper만 켜지고 front UI가 꺼지는 분리 상태를 일반 설정으로 만들게 되는 일을 막음.
- 명세: Settings main surface는 `Hotspot SSID`, `Proxy Type`, `Proxy Port`, `Language`, `Start Automatically`만 제공함. `Language` 선택은 Settings window UI에도 즉시 반영함. `Start Automatically`를 켜면 helper LaunchAgent와 menu LaunchAgent를 함께 생성/load하고, 끄면 자동 시작 plist를 제거함. Settings 저장은 config write 성공까지만 기다리고, LaunchAgent 반영과 reconcile 호출은 저장창을 닫은 뒤 비동기로 수행함. 설정값이 실제로 바뀌지 않은 저장은 config file rewrite, LaunchAgent reload, reconcile을 생략함. Settings 저장 중 현재 실행 중인 menu app은 종료하지 않음. Advanced에는 troubleshooting용 초 단위 `Proxy Check Timeout`, `Helper Watchdog Interval`만 둠. 저장 후 config가 변경된 경우 한 번 `hotspot-proxy-toggle run`을 호출함.
- 테스트: `scripts/validate.sh`는 AppKit build로 Settings code를 컴파일함.
