# Event-driven macOS helper 제안

## 상태

제안은 승인됐고, `Sources/hotspot-proxy-toggle-helper/main.swift`에 helper를 추가함. 현재 설치 기본값은 event-driven helper이며, helper 설치 실패 또는 `HOTSPOT_TRIGGER_MODE=polling` 명시 시 polling LaunchAgent로 fallback함.

## Root goal

Polling wakeup을 줄이면서도 `hotspot-proxy-toggle run`의 single-shot reconciliation 경계를 유지함.

## 요구사항

- network state change가 감지되면 기존 runtime command인 `hotspot-proxy-toggle run`을 호출함.
- runtime command는 계속 한 번 reconcile하고 종료함.
- helper는 proxy host 계산, hotspot 판정, macOS proxy write policy를 재구현하지 않음.
- helper는 설치 기본 trigger로 동작함.
- helper는 hotspot 상태에서만 endpoint watchdog을 켜서 proxy server on/off 변화를 저빈도로 보정함.
- helper 설치가 실패해도 기존 polling LaunchAgent로 되돌릴 수 있어야 함.

## 배경

현재 LaunchAgent는 `RunAtLoad`와 `StartInterval`로 주기적으로 `hotspot-proxy-toggle run`을 호출함. 이 구조는 단순하고 복구가 쉽지만, 네트워크가 바뀌지 않아도 정해진 간격마다 wakeup이 발생함.

Apple의 launchd 문서는 network availability가 launchd dependency만으로 해결되지 않는다고 설명하며, network reachability 또는 System Configuration dynamic store를 사용하라고 안내함. `launchd.plist` man page도 `KeepAlive`의 `NetworkState`가 더 이상 구현되어 있지 않고 기대와 다르게 동작했다고 설명함.

따라서 event-driven 전환은 launchd plist 키만 바꾸는 작업이 아니라, macOS network change API를 관찰하는 작은 helper를 추가하는 작업으로 보는 편이 안전함.

## 후보

### 후보 A: SCDynamicStore 기반 helper

작은 Swift 또는 Objective-C helper가 SystemConfiguration의 `SCDynamicStore` notification을 구독함.

관찰 후보:

- IPv4 default route 변화
- Wi-Fi interface IPv4/DHCP state 변화
- network service state 변화

동작:

1. helper가 LaunchAgent로 시작됨.
2. `SCDynamicStoreSetNotificationKeys`로 관련 key pattern을 등록함.
3. 변경 event가 오면 짧은 debounce window를 둠.
4. debounce 뒤 `hotspot-proxy-toggle run`을 child process로 한 번 실행함.
5. 실행 중 추가 event가 오면 pending flag만 세우고, 현재 실행이 끝난 뒤 한 번 더 실행함.

장점:

- default route, DHCP router, interface state 같은 현재 runtime decision input과 가장 직접적으로 맞음.
- CoreWLAN만 보는 방식보다 Ethernet, VPN, sleep/wake, route 변화 같은 false negative가 적음.
- helper가 proxy decision을 몰라도 됨.

단점:

- SystemConfiguration dynamic store key pattern은 OS별 세부 key 차이를 검증해야 함.
- event가 여러 번 연속 발생할 수 있어 debounce와 coalescing이 필요함.
- 장시간 실행되는 helper가 추가되므로 lifecycle, logging, crash behavior를 별도로 관리해야 함.

추천: 1차 구현 후보.

### 후보 B: CoreWLAN notification 기반 helper

CoreWLAN의 SSID/link 관련 notification을 구독해서 Wi-Fi 변화만 감지함.

장점:

- “핫스팟 SSID 변화”라는 사용자 관점의 event와 잘 맞음.
- Wi-Fi 중심 기능임이 명확함.

단점:

- default route가 Wi-Fi인지, DHCP router가 바뀌었는지, VPN이나 다른 interface가 route를 가져갔는지 직접 알 수 없음.
- SSID가 같아도 DHCP router만 바뀌는 경우를 놓칠 수 있음.
- Wi-Fi가 아닌 route 변화 때문에 proxy를 꺼야 하는 상황을 놓칠 수 있음.

추천: SCDynamicStore helper의 보조 signal로만 검토함.

### 후보 C: SCNetworkReachability callback 기반 helper

특정 host 또는 address reachability 변화를 구독함.

장점:

- Apple이 network availability 판단에 제시하는 공식 SystemConfiguration 계열 API임.
- proxy endpoint reachability 변화를 관찰하는 실험에는 쓸 수 있음.

단점:

- 이 프로젝트의 핵심 input은 “현재 default route, Wi-Fi DHCP router, hotspot marker”임.
- 특정 외부 host reachability 변화는 hotspot context 변화와 일치하지 않을 수 있음.
- proxy endpoint host가 동적 router IP라서, reachability target을 정하려면 먼저 evaluate가 필요함.

추천: 주 trigger로는 부적합함. endpoint check retry나 diagnostics 실험에만 적합함.

### 후보 D: launchd plist key만으로 event-driven 전환

`KeepAlive`, `WatchPaths`, `LaunchEvents` 같은 launchd key만으로 network change를 trigger하려는 방식임.

장점:

- 별도 helper binary를 줄일 수 있음.
- 기존 LaunchAgent 설치 구조와 비슷함.

단점:

- `NetworkState`는 현재 사용할 수 있는 신뢰 가능한 trigger가 아님.
- `WatchPaths`는 filesystem 변화용이며 network state consistency를 보장하지 않음.
- `LaunchEvents`는 event subsystem 설계가 필요하고, network dynamic store change를 직접 표현하는 단순 plist 설정으로 보기 어려움.

추천: 단독 접근은 배제함.

## 권장 설계

event-driven 설계는 `SCDynamicStore` 기반 helper를 기본 trigger로 둠.

구성:

```text
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.helper.plist
  -> hotspot-proxy-toggle-helper
       -> observes SystemConfiguration dynamic store
       -> debounces network changes
       -> runs hotspot-proxy-toggle run
```

기존 polling plist는 fallback으로 유지함. 설치 단계에서는 아래 중 하나가 적용됨.

- 기본값: event-driven helper LaunchAgent
- fallback: helper install 실패 시 polling LaunchAgent
- 강제 polling: `HOTSPOT_TRIGGER_MODE=polling`

helper는 아래 invariant를 지켜야 함.

- proxy setting을 직접 쓰지 않음.
- config parsing을 중복 구현하지 않음.
- `hotspot-proxy-toggle run`의 exit code와 stdout/stderr를 log에 남김.
- `hotspot-proxy-toggle run`의 status output으로 endpoint watchdog on/off를 결정함.
- event burst를 1회 reconcile로 합침.
- helper 시작 시 한 번 reconcile함.
- hotspot 상태에서만 endpoint watchdog을 실행함.
- sleep/wake 직후 event 누락 가능성을 고려해 wake 후 한 번 reconcile할 수 있는지 검토함.

## Debounce 정책

초기값:

- event 수신 후 1초 대기
- 실행 중 event가 오면 pending flag만 기록
- 실행이 끝난 뒤 pending flag가 있으면 1초 뒤 한 번 더 실행
- 동일한 10초 window 안에서 최대 3회 실행 후 다음 event까지 대기
- hotspot 상태에서는 60초마다 endpoint watchdog 실행
- non-hotspot 상태에서는 endpoint watchdog 중지

근거:

- DHCP, route, SSID event는 한 번의 사용자 동작에서 여러 개가 이어질 수 있음.
- 즉시 여러 번 `networksetup` write를 시도하면 불필요한 로그와 transient state가 늘어남.
- 최종 decision은 runtime command가 현재 상태를 다시 inspect하므로 helper는 빠른 반응보다 안정적인 coalescing을 우선함.
- 휴대폰 쪽 proxy server on/off는 macOS network event를 만들지 않으므로 hotspot 상태에 한정한 endpoint watchdog으로 보정함.

## 설치/마이그레이션 경로

### Phase 0: 기존 polling 기본값

- 완료됨.
- polling LaunchAgent를 기본값으로 유지함.
- `StartInterval` 기반 behavior를 public spec에 계속 현재 truth로 둠.

### Phase 1: helper spike

- 완료됨.
- `hotspot-proxy-toggle-helper` prototype을 별도 파일로 추가함.
- installer 기본 동작은 바꾸지 않음.
- 수동 실행 또는 별도 실험 install flag로만 helper plist를 생성함.
- dry-run 또는 log-only mode로 event coalescing을 검증함.

현재 helper:

- `SCDynamicStoreSetNotificationKeys`로 network dynamic store 변화 key pattern을 관찰함.
- event burst를 debounce하고, child process로 `hotspot-proxy-toggle run`을 호출함.
- `--dry-run`을 주면 child command에 `DRY_RUN=1`을 전달함.
- `--once`를 주면 event loop 없이 child command를 한 번 실행하고 종료함.
- 설치 기본값은 event helper이며, helper install 실패 시 polling LaunchAgent로 fallback함.

수동 빌드:

```bash
./scripts/build-helper.sh
.build/hotspot-proxy-toggle-helper --command ./bin/hotspot-proxy-toggle --dry-run --once
```

### Phase 2: opt-in install option

- 완료됨.
- 이 단계에서는 `HOTSPOT_TRIGGER_MODE=event ./install.sh`가 helper binary를 빌드하고 helper LaunchAgent를 설치했음.
- 이 단계에서는 기본값을 `polling`으로 유지했음.
- 이 단계에서는 기본 `./install.sh`를 다시 실행하면 polling LaunchAgent로 되돌렸음.
- `uninstall.sh`는 helper LaunchAgent와 polling LaunchAgent를 모두 정리함.

### Phase 3: 기본값 전환

- 완료됨.
- 기본 `./install.sh`는 event helper 설치를 시도함.
- helper build 또는 helper LaunchAgent 설치가 실패하면 polling LaunchAgent로 fallback함.
- `HOTSPOT_TRIGGER_MODE=polling ./install.sh`는 polling LaunchAgent를 강제로 설치함.
- `uninstall.sh`는 helper LaunchAgent와 polling LaunchAgent를 모두 정리함.

### Phase 4: hotspot-limited endpoint watchdog

- 완료됨.
- helper는 `hotspot-proxy-toggle run` output이 hotspot 상태이면 endpoint watchdog을 시작함.
- helper는 non-hotspot 상태이면 endpoint watchdog을 중지함.
- 기본 watchdog interval은 60초이고, `HELPER_WATCHDOG_SECONDS=0`으로 비활성화할 수 있음.

### Phase 5: 운영 검증

아래 조건은 event-driven 기본 mode의 운영 신뢰도 개선 대상으로 유지함.

- sleep/wake, Wi-Fi 전환, 같은 SSID 재연결, hotspot router IP 변경, proxy server off/on case가 검증됨.
- helper crash/restart behavior가 launchd 아래에서 안정적임.
- polling fallback 문서와 uninstall path가 검증됨.
- public issue나 실제 사용에서 event-driven mode가 polling보다 확실히 낫다는 근거가 생김.

## 테스트 계획

Unit 수준:

- debounce state machine test
- “실행 중 event” coalescing test
- child process failure logging test
- max-run window test

Manual macOS 검증:

- 일반 Wi-Fi 연결
- 휴대폰 핫스팟 연결
- 같은 핫스팟 재연결 후 router IP 변경
- proxy endpoint off/on
- sleep/wake
- VPN 또는 다른 interface가 default route를 가져가는 경우

Acceptance:

- event-driven mode에서도 `hotspot-proxy-toggle run`은 single-shot으로 유지됨.
- hotspot 상태에서만 endpoint watchdog이 동작함.
- helper 설치가 실패해도 polling 설치가 계속 동작함.
- `HOTSPOT_TRIGGER_MODE=polling`으로 polling mode를 강제할 수 있음.
- public docs에 default mode와 fallback이 명확히 구분됨.

## 현재 결론

현재는 event-driven helper가 기본 설치 경로이고 polling LaunchAgent가 fallback임. Hotspot 상태에서는 endpoint watchdog이 proxy server on/off 변화를 보정함. Event helper 설치 실패 시에는 단계별 diagnostic을 출력함. 다음 구현 task를 만든다면 실제 macOS network transition 검증이 적절함.

그 task의 경계:

- 실제 핫스팟 연결/해제, sleep/wake, proxy endpoint off/on 전환을 검증함.
- polling LaunchAgent fallback을 유지함.
- helper가 실제 proxy write를 직접 수행하지 않음.

## 참고 자료

- Apple Developer Documentation: `SCDynamicStore`
  <https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2>
- Apple Developer Documentation: `SCDynamicStoreSetNotificationKeys`
  <https://developer.apple.com/documentation/systemconfiguration/scdynamicstoresetnotificationkeys%28_%3A_%3A_%3A%29>
- Apple Developer Documentation: `CWSSIDDidChangeNotification`
  <https://developer.apple.com/documentation/corewlan/cwssiddidchangenotification>
- Apple Developer Documentation: `SCNetworkReachabilitySetDispatchQueue`
  <https://developer.apple.com/documentation/systemconfiguration/scnetworkreachabilitysetdispatchqueue%28_%3A_%3A%29>
- Apple Documentation Archive: Creating Launch Daemons and Agents
  <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html>
- Local macOS manual page: `launchd.plist(5)`
