# 명세

이 문서는 현재 동작을 설명함. 미래 아이디어는 `docs/ROADMAP.md`에 둠.

## 범위

`hotspot-proxy-toggle`은 현재 휴대폰 핫스팟 context에 맞춰 system proxy setting을 reconcile하는 macOS 유틸리티임.

현재 backend support:

- `PROXY_TYPE=socks5`
- `PROXY_TYPE=http`

현재 network service support:

- 하나의 설정된 network service에 대한 macOS `networksetup` proxy setting. 기본값은 `Wi-Fi`.
- `socks5`: SOCKS firewall proxy.
- `http`: Web Proxy와 Secure Web Proxy를 같은 host/port로 함께 설정.

## Runtime Command 동작

`bin/hotspot-proxy-toggle`은 아래 command를 지원함:

- `evaluate`: hotspot detection 결과만 출력함.
- `status`: hotspot detection 결과, optional proxy endpoint check, 현재 macOS SOCKS proxy state를 출력함.
- `run`: 한 번 reconcile하고 종료함.

Runtime command는 파일 설치, LaunchAgent 생성, persistent loop 실행을 하지 않음.

## Event-driven helper

`Sources/hotspot-proxy-toggle-helper/main.swift`에는 event-driven helper가 있음.

helper는 아래 역할만 함:

- SystemConfiguration dynamic store network change notification을 관찰함.
- event burst를 debounce함.
- child process로 기존 `hotspot-proxy-toggle run`을 호출함.
- `run` 출력이 hotspot 상태를 나타내면 endpoint watchdog timer를 켬.
- `run` 출력이 non-hotspot 상태를 나타내면 endpoint watchdog timer를 끔.
- `--dry-run`이면 child command에 `DRY_RUN=1`을 전달함.
- `--once`이면 event loop 없이 child command를 한 번 실행하고 종료함.

helper는 macOS proxy setting을 직접 변경하지 않고, hotspot/proxy decision을 재구현하지 않음. Hotspot 여부도 별도로 재판정하지 않고 `hotspot-proxy-toggle run`의 status output을 사용함.

설치 기본값은 event-driven helper LaunchAgent임. helper build 또는 helper LaunchAgent 설치가 실패하면 `install.sh`는 polling LaunchAgent로 fallback함. `HOTSPOT_TRIGGER_MODE=polling`을 명시하면 polling LaunchAgent를 강제로 설치함.

## 설정

기본 config path:

```text
~/.config/hotspot-proxy-toggle.conf
```

지원 key:

```bash
NETWORK_SERVICE='Wi-Fi'
WIFI_DEVICE=''
PROXY_TYPE=socks5
PROXY_PORT=1080
HOTSPOT_SSIDS=''
HOTSPOT_DHCP_MARKERS='ANDROID_METERED'
STRICT_SSID=0
REQUIRE_PROXY_CHECK=1
PROXY_CHECK_TIMEOUT=1
DRY_RUN=0
NOTIFY_ON_CHANGE=0
NOTIFICATION_LOCALE=auto
```

Notification 상태 파일 기본 경로:

```text
~/Library/Application Support/hotspot-proxy-toggle/state
```

`socks5` 또는 `http`가 아닌 `PROXY_TYPE` 값은 거부함.

## 감지

유틸리티는 아래 순서로 판단함:

1. `WIFI_DEVICE`가 설정되어 있지 않으면 `networksetup -listallhardwareports`로 Wi-Fi device를 찾음.
2. `route -n get default`에서 default route interface를 읽음.
3. default interface가 Wi-Fi device가 아니면 hotspot path를 종료함.
4. `ipconfig getsummary <wifi-device>`에서 DHCP summary를 읽음.
5. `Router`와 `SSID`를 추출함.
6. 설정에 따라 exact SSID allow-list 또는 DHCP marker로 hotspot status를 판단함.

`STRICT_SSID=1`이면 DHCP marker fallback을 비활성화함.

## 프록시 확인

`REQUIRE_PROXY_CHECK=1`이면 `socks5` backend는 아래 SOCKS5 no-auth greeting을 보냄:

```text
05 01 00
```

macOS proxy setting을 켜기 전에 아래 응답을 요구함:

```text
05 00
```

이 확인은 단순히 TCP port가 열려 있는지가 아니라 해당 port가 SOCKS5 no-auth proxy인지 검증함.

`http` backend는 `REQUIRE_PROXY_CHECK=1`일 때 `router:PROXY_PORT`로 절대 URI 형식의 HTTP request를 보내고 `HTTP/` response line을 요구함. `407 Proxy Authentication Required`는 현재 auth 미지원이므로 실패로 처리함. PAC 처리는 현재 범위가 아님.

## Reconciliation 규칙

`run`은 아래 규칙을 적용함:

- Wi-Fi가 아니거나, router가 없거나, hotspot이 아니면 설정된 network service의 backend proxy state를 끔.
- Hotspot candidate지만 proxy endpoint를 사용할 수 없으면 backend proxy state를 끔.
- Hotspot candidate이고 endpoint를 사용할 수 있으면 backend별 host를 현재 router IP로, port를 `PROXY_PORT`로 설정하고 proxy state를 켬.
- `socks5` backend는 SOCKS firewall proxy state를 켜고 Web Proxy와 Secure Web Proxy state를 끔.
- `http` backend는 Web Proxy와 Secure Web Proxy state를 함께 켜고 SOCKS firewall proxy state를 끔.
- Hotspot이 아니거나 endpoint를 사용할 수 없으면 지원하는 backend 전체를 끔.
- 현재 macOS proxy state가 이미 desired state와 일치하면 가능한 한 불필요한 `networksetup` write를 피함.
- `NOTIFY_ON_CHANGE=1`이면 최종 reconciliation state가 이전 `run`과 달라졌거나 실제 macOS proxy setting 변경이 있었던 `run`에서 macOS notification을 한 번 표시함. 같은 state가 유지되거나 `DRY_RUN=1`이면 notification을 표시하지 않음.

## Notification

Notification은 runtime command의 부가 출력 경로임. `bin/hotspot-proxy-toggle run`은 `NOTIFY_ON_CHANGE=1`일 때 macOS `/usr/bin/osascript`의 `display notification`을 사용해 최종 proxy state를 표시함.

Notification은 아래 원칙을 따름:

- 최종 상태 기준으로 `run`당 최대 한 번 표시함.
- 실제 proxy setting 변경이 있으면 표시함.
- proxy setting 변경이 없어도 active Wi-Fi가 설정한 hotspot이 아니거나 endpoint availability가 이전 `run`과 달라지면 표시함.
- default route가 Wi-Fi가 아니거나 Wi-Fi router가 아직 확인되지 않은 상태에서는 notification을 표시하지 않고 state file만 갱신함.
- 중복 알림을 막기 위해 마지막 notification state를 local state file에 저장함. `HOTSPOT_PROXY_STATE`로 경로를 override할 수 있음.
- `NOTIFICATION_LOCALE=auto`이면 macOS 언어 설정을 읽어 한국어 환경에서는 한국어 문구를 사용하고, 그 외에는 영어 문구를 사용함. `en` 또는 `ko`로 고정할 수 있음.
- Notification title은 3개 상태로 나뉨: hotspot proxy active는 `✅ Hotspot Proxy On`, hotspot은 맞지만 endpoint가 unavailable이면 `⚠️ Hotspot Proxy Unavailable`, active Wi-Fi가 설정한 hotspot이 아니면 `ℹ️ Hotspot Proxy Idle`. 한국어 locale에서는 각각 `✅ 핫스팟 프록시 켜짐`, `⚠️ 핫스팟 프록시 사용 불가`, `ℹ️ 핫스팟 프록시 대기`를 사용함.
- 라우터 IP, SSID, local path 같은 환경별 값을 message에 포함하지 않음.
- `osascript` 실행에 실패해도 reconciliation 자체는 실패시키지 않고 log에만 남김.

## 설치

기본 `install.sh`는 아래 공통 파일을 설치함:

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
```

설치 시작 시 installer는 helper/polling LaunchAgent를 모두 unload하고 generated plist를 삭제함. 이후 binary와 선택된 LaunchAgent를 갱신함. Config file과 log file은 upgrade 중 유지함.

event helper 설치가 가능하면 기본값으로 아래 helper 파일과 helper LaunchAgent를 설치함:

```text
~/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-helper
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.helper.plist
```

helper LaunchAgent는 `hotspot-proxy-toggle-helper --command <installed-command>`를 실행함. helper는 시작 시 한 번 reconcile하고, 이후 SystemConfiguration network change event를 debounce해서 `hotspot-proxy-toggle run`을 호출함. Hotspot 상태에서는 endpoint watchdog이 낮은 빈도로 `hotspot-proxy-toggle run`을 다시 호출해 프록시 서버 on/off 변화를 보정함. Hotspot이 아니면 watchdog은 꺼짐.

event helper tuning key:

```bash
HELPER_DEBOUNCE_SECONDS=1
HELPER_MAX_RUNS=3
HELPER_WINDOW_SECONDS=10
HELPER_WATCHDOG_SECONDS=60
```

`HELPER_WATCHDOG_SECONDS=0`이면 endpoint watchdog을 비활성화함.

helper build, helper LaunchAgent plist 생성, helper LaunchAgent load 중 하나가 실패하면 installer는 실패 단계와 확인 힌트를 출력한 뒤 아래 polling LaunchAgent를 설치함. `HOTSPOT_TRIGGER_MODE=polling`을 명시한 경우에도 polling LaunchAgent를 설치하고 helper LaunchAgent는 제거함:

```text
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

polling LaunchAgent는 아래 command를 호출함:

```text
hotspot-proxy-toggle run
```

기본 polling interval은 60초임. 기본 `./install.sh`를 다시 실행하면 event helper 설치를 다시 시도함.

## 제거

`uninstall.sh`는 polling/helper LaunchAgent를 모두 unload하고, 설치된 binary tree와 command symlink를 제거하며, config file은 유지함.
