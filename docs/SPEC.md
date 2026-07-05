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

## Menu Bar Companion

`Sources/hotspot-proxy-toggle-menu/main.swift`에는 opt-in menu bar companion이 있음.

Companion은 아래 역할만 함:

- macOS menu bar status area에 기본적으로 icon-only status item을 표시함.
- `hotspot-proxy-toggle run`/`off`가 쓰는 UI state JSON을 watch해 상태 menu를 갱신함.
- UI state JSON이 아직 없거나 읽을 수 없으면 `hotspot-proxy-toggle status`를 child process로 호출해 상태 menu를 갱신함.
- 사용자가 menu에서 `Reconcile Now`를 선택하면 `hotspot-proxy-toggle run`을 한 번 호출함.
- `Refresh Status`는 proxy setting을 변경하지 않고 `status`만 다시 호출함.
- `Quit MHP`는 `hotspot-proxy-toggle off`를 호출해 proxy setting을 끄고, helper LaunchAgent와 menu LaunchAgent를 unload함.

Companion은 macOS proxy setting을 직접 변경하지 않고, hotspot/proxy decision을 재구현하지 않음. Primary 상태 표시는 UI state JSON에서 파생함. Fallback 상태 표시는 `status=hotspot`, `status=not-hotspot`, `status=not-wifi`, `status=no-router`, `proxy_check=...-missing` 같은 runtime command output에서 파생함.

UI state JSON 기본 경로:

```text
~/Library/Application Support/hotspot-proxy-toggle/status.json
```

UI state JSON은 menu 표시용 machine-readable state임. Notification 중복 방지용 `HOTSPOT_PROXY_STATE`와 역할이 다르며, SSID, router IP, local path를 포함하지 않음.

현재 key:

```json
{
  "version": 1,
  "kind": "on",
  "proxy_type": "socks5",
  "detail": "",
  "updated_at": "2026-07-05T00:00:00Z"
}
```

`kind` 값:

- `on`
- `unavailable`
- `idle`
- `not_wifi`
- `off`
- `error`

상태 menu 문구는 아래 5상태임:

- `Hotspot Proxy On` / `핫스팟 프록시 켜짐`
- `Hotspot Proxy Unavailable` / `핫스팟 프록시 사용 불가`
- `Hotspot Proxy Idle` / `핫스팟 대기`
- `Wi-Fi Not Ready` / `Wi-Fi 준비 안 됨`
- `MHP Error` / `MHP 오류`

Status item은 기본적으로 template image icon만 표시함. `MENU_BAR_TITLE`을 지정하면 title 옆에 icon을 표시함. Icon은 binary 내부에서 AppKit vector drawing으로 생성하며 외부 asset file에 의존하지 않음. macOS light/dark menu bar tint와 맞추기 위해 template image로 설정함.

Icon shape은 세 가지 시각 상태를 사용함:

- `hotspot + proxy on`: 채워진 휴대폰 사각형 안에 hotspot arc를 투명 knockout으로 표시함.
- `non-hotspot`: 같은 geometry의 휴대폰 외곽선과 hotspot arc를 표시함. `idle`, `off`, `not_wifi`, `checking`은 이 시각 상태를 사용함.
- `hotspot + proxy off`: 채워진 휴대폰 사각형과 hotspot arc 위에 휴대폰 전체를 가로지르는 대각선 knockout을 표시함. `unavailable`과 `error`는 이 시각 상태를 사용함.

Companion LaunchAgent는 opt-in임. Source installer에서 `HOTSPOT_MENU_BAR=1`을 지정한 경우에만 아래 LaunchAgent를 생성하고 load함:

```text
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.menu.plist
```

Companion tuning key:

```bash
MENU_BAR_REFRESH_SECONDS=30
MENU_BAR_TITLE=
MENU_BAR_LOCALE=auto
HOTSPOT_PROXY_UI_STATE=~/Library/Application Support/hotspot-proxy-toggle/status.json
```

Companion LaunchAgent는 `KeepAlive`를 사용하지 않음. 사용자가 menu에서 `Quit MHP`를 선택하면 launchd가 즉시 재시작하지 않아야 함. `MENU_BAR_REFRESH_SECONDS`는 UI state file watch 누락이나 sleep/wake 이후 stale UI를 보정하는 fallback refresh 간격임.

## MHP.app

`scripts/build-app.sh`는 menu bar companion binary를 `MHP.app` bundle로 포장함.

App bundle 원칙:

- `LSUIElement=true`로 Dock icon 없이 menu bar item만 표시함.
- App bundle executable은 `hotspot-proxy-toggle-menu`임.
- App bundle은 `MHP.icns`를 포함하고 `CFBundleIconFile`/`CFBundleIconName`으로 참조함.
- App icon은 핫스팟 프록시 켜짐 상태 glyph를 기반으로 한 컬러 icon임.
- Finder, Spotlight, Launchpad에서 실행 가능해야 함.
- 기존 menu companion instance가 이미 실행 중이면 새 instance는 status item을 만들지 않고 종료함.
- app launch 시 helper LaunchAgent plist가 있으면 helper를 다시 bootstrap/kickstart함.
- helper plist가 없고 polling LaunchAgent plist가 있으면 polling LaunchAgent를 다시 bootstrap/kickstart함.
- app launch가 hotspot/proxy decision이나 macOS proxy write policy를 직접 구현하지 않음.

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

Notification은 runtime command의 부가 출력 경로임. `bin/hotspot-proxy-toggle run`은 `NOTIFY_ON_CHANGE=1`일 때 설치된 `MHP.app/Contents/MacOS/hotspot-proxy-toggle-menu --notify`를 우선 호출해 최종 proxy state를 표시함. App sender를 사용할 수 없거나 실패하면 macOS `/usr/bin/osascript`의 `display notification`으로 fallback함.

Notification은 아래 원칙을 따름:

- 최종 상태 기준으로 `run`당 최대 한 번 표시함.
- 실제 proxy setting 변경이 있으면 표시함.
- proxy setting 변경이 없어도 active Wi-Fi가 설정한 hotspot이 아니거나 endpoint availability가 이전 `run`과 달라지면 표시함.
- default route가 Wi-Fi가 아니거나 Wi-Fi router가 아직 확인되지 않은 상태에서는 notification을 표시하지 않고 state file만 갱신함.
- 중복 알림을 막기 위해 마지막 notification state를 local state file에 저장함. `HOTSPOT_PROXY_STATE`로 경로를 override할 수 있음.
- `NOTIFICATION_LOCALE=auto`이면 macOS 언어 설정을 읽어 한국어 환경에서는 한국어 문구를 사용하고, 그 외에는 영어 문구를 사용함. `en` 또는 `ko`로 고정할 수 있음.
- Notification title은 3개 상태로 나뉨: hotspot proxy active는 `✅ Hotspot Proxy On`, hotspot은 맞지만 endpoint가 unavailable이면 `⚠️ Hotspot Proxy Unavailable`, active Wi-Fi가 설정한 hotspot이 아니면 `ℹ️ Hotspot Proxy Idle`. 한국어 locale에서는 각각 `✅ 핫스팟 프록시 켜짐`, `⚠️ 핫스팟 프록시 사용 불가`, `ℹ️ 핫스팟 대기`를 사용함.
- Notification sender는 가능한 경우 `MHP.app` bundle executable이므로 notification은 고정 MHP app icon으로 표시될 수 있음. 상태별 custom notification icon은 지정하지 않음. Notification title의 emoji는 상태 구분 보조 신호로 유지함.
- 라우터 IP, SSID, local path 같은 환경별 값을 message에 포함하지 않음.
- `osascript` 실행에 실패해도 reconciliation 자체는 실패시키지 않고 log에만 남김.

## 설치

기본 source installer인 `install.sh`는 아래 공통 파일을 설치함:

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

menu bar companion을 같이 시작하려면 source install 시 `HOTSPOT_MENU_BAR=1`을 지정함:

```bash
HOTSPOT_MENU_BAR=1 PROXY_PORT=1080 ./install.sh
```

이 경우 아래 파일과 LaunchAgent를 추가로 설치함:

```text
~/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-menu
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.menu.plist
```

`MENU_BAR_REFRESH_SECONDS`로 상태 refresh 간격을, `MENU_BAR_TITLE`로 menu bar title을, `MENU_BAR_LOCALE=auto|en|ko`로 menu language를 바꿀 수 있음. `MENU_BAR_TITLE` 기본값은 빈 문자열이며 이 경우 status item은 icon-only로 표시됨.

`HOTSPOT_NOTIFICATION_SENDER`로 notification sender executable path를 override할 수 있음. 기본값은 `~/Applications/MHP.app/Contents/MacOS/hotspot-proxy-toggle-menu`임.

source installer는 기본적으로 Finder 실행용 app bundle도 설치함:

```text
~/Applications/MHP.app
```

`HOTSPOT_APP=0`이면 app bundle 설치를 생략함. `HOTSPOT_APP_INSTALL_DIR`로 설치 directory를 바꿀 수 있음.

helper build, helper LaunchAgent plist 생성, helper LaunchAgent load 중 하나가 실패하면 installer는 실패 단계와 확인 힌트를 출력한 뒤 아래 polling LaunchAgent를 설치함. `HOTSPOT_TRIGGER_MODE=polling`을 명시한 경우에도 polling LaunchAgent를 설치하고 helper LaunchAgent는 제거함:

```text
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

polling LaunchAgent는 아래 command를 호출함:

```text
hotspot-proxy-toggle run
```

기본 polling interval은 60초임. 기본 `./install.sh`를 다시 실행하면 event helper 설치를 다시 시도함.

패키지 매니저용 `make install PREFIX=<prefix>`는 사용자 home directory를 직접 변경하지 않고 아래 파일만 설치함:

```text
<prefix>/bin/hotspot-proxy-toggle
<prefix>/libexec/hotspot-proxy-toggle-helper
<prefix>/libexec/hotspot-proxy-toggle-menu
<prefix>/libexec/MHP.app
<prefix>/etc/hotspot-proxy-toggle.conf.example
```

이 prefix install 경로는 config 생성, LaunchAgent 생성, `launchctl` load를 수행하지 않음. Homebrew 같은 패키지 매니저는 service definition 또는 caveats에서 사용자별 config와 service activation을 안내해야 함.

## 제거

`uninstall.sh`는 polling/helper/menu LaunchAgent를 모두 unload하고, 설치된 binary tree, command symlink, `~/Applications/MHP.app`을 제거하며, config file은 유지함.
