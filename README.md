# mac-hotspot-proxy-toggle

일치하는 휴대폰 핫스팟과 프록시 endpoint가 있을 때만 macOS 프록시 설정을 켜는 작은 macOS 유틸리티입니다.

현재 release는 현재 핫스팟 라우터 IP 위의 SOCKS5와 HTTP Web Proxy를 지원합니다. `PROXY_TYPE=http`는 macOS Web Proxy와 Secure Web Proxy를 같은 host/port로 함께 설정합니다.

## 왜 필요한가

macOS 프록시 설정은 Wi-Fi SSID별이 아니라 `Wi-Fi` 같은 network service 단위로 적용됩니다. 또한 휴대폰 핫스팟은 연결할 때마다 라우터 IP가 바뀔 수 있습니다.

이 유틸리티는 다음 상태를 reconcile합니다.

1. 기본 route가 Wi-Fi인지 확인합니다.
2. 현재 Wi-Fi 라우터 IP를 DHCP 상태에서 읽습니다.
3. 현재 Wi-Fi가 설정된 휴대폰 핫스팟처럼 보이는지 판단합니다.
4. `router:PROXY_PORT`의 프록시 endpoint를 확인합니다.
5. endpoint가 사용 가능할 때만 macOS 프록시 설정을 켜고, 그렇지 않으면 끕니다.

## 설치

### Homebrew

```bash
brew install plaonn/tap/hotspot-proxy-toggle
```

설정 파일을 만든 뒤 `PROXY_PORT`와 필요한 hotspot 식별 값을 수정합니다.

```bash
mkdir -p ~/.config
cp "$(brew --prefix)/etc/hotspot-proxy-toggle.conf.example" ~/.config/hotspot-proxy-toggle.conf
${EDITOR:-vi} ~/.config/hotspot-proxy-toggle.conf
```

event helper를 LaunchAgent로 실행하려면 다음 명령을 사용합니다.

```bash
brew services start plaonn/tap/hotspot-proxy-toggle
```

즉시 한 번 reconcile하려면 다음 명령을 실행합니다.

```bash
hotspot-proxy-toggle run
```

### Source Install

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 ./install.sh
```

SSID를 정확히 지정하려면 다음처럼 설치합니다.

```bash
PROXY_PORT=1080 HOTSPOT_SSIDS='My Phone Hotspot' ./install.sh
```

기본 event 설치에서 생성되는 파일은 다음과 같습니다.

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-helper
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.helper.plist
```

기본 설치는 네트워크 변경 event에 반응하는 helper LaunchAgent를 사용합니다. helper는 Swift로 빌드되며, macOS network change event를 debounce한 뒤 기존 `hotspot-proxy-toggle run`을 호출합니다. 프록시 판단과 설정 변경은 계속 single-shot runtime command가 담당합니다.

핫스팟 상태에서는 helper가 endpoint watchdog을 켭니다. 기본값은 60초마다 한 번 `hotspot-proxy-toggle run`을 호출하는 방식이며, 휴대폰 쪽 프록시 서버만 중간에 켜지거나 꺼지는 경우를 보정합니다. 일반 Wi-Fi처럼 hotspot이 아닌 상태에서는 watchdog을 끕니다.

```bash
HELPER_WATCHDOG_SECONDS=120 PROXY_PORT=1080 ./install.sh
```

watchdog을 끄려면 `HELPER_WATCHDOG_SECONDS=0`으로 설치합니다.

설치를 다시 실행하면 기존 helper/polling LaunchAgent를 먼저 멈추고 generated plist를 삭제한 뒤 설치 파일을 갱신합니다. 설정 파일과 로그는 유지합니다.

event helper를 설치할 수 없으면 installer는 실패한 단계와 확인 힌트를 출력한 뒤 polling LaunchAgent로 되돌아갑니다. polling fallback은 아래 파일을 사용합니다.

```text
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

polling fallback은 기본적으로 60초마다 실행됩니다. polling을 명시적으로 사용하려면 다음처럼 설치합니다.

```bash
HOTSPOT_TRIGGER_MODE=polling PROXY_PORT=1080 ./install.sh
```

polling interval을 바꾸려면 다음처럼 설치합니다.

```bash
HOTSPOT_TRIGGER_MODE=polling CHECK_INTERVAL_SECONDS=30 PROXY_PORT=1080 ./install.sh
```

event helper를 다시 기본값으로 설치하려면 다음처럼 실행합니다.

```bash
PROXY_PORT=1080 ./install.sh
```

event helper 설치에는 macOS Swift compiler가 필요합니다. Xcode Command Line Tools가 설치된 환경이면 보통 사용할 수 있습니다. Swift compiler가 없거나 helper 설치가 실패하면 polling fallback이 설치됩니다.

시계 옆 menu bar status area에 `MHP` 항목을 표시하려면 source install 시 `HOTSPOT_MENU_BAR=1`을 지정합니다.

```bash
HOTSPOT_MENU_BAR=1 PROXY_PORT=1080 ./install.sh
```

Menu bar companion은 `hotspot-proxy-toggle run`/`off`가 쓰는 UI state JSON을 watch해 상태를 갱신합니다. 메뉴에서 `Refresh Status`를 선택하면 상태만 다시 확인하고, `Reconcile Now`를 선택하면 `hotspot-proxy-toggle run`을 한 번 실행합니다. `Quit MHP`는 `hotspot-proxy-toggle off`로 proxy setting을 끄고 helper/menu LaunchAgent를 내립니다. Companion은 프록시 판단이나 설정 변경 로직을 직접 구현하지 않습니다.

Menu status는 notification 문맥과 맞춘 5상태를 사용합니다.

- `Hotspot Proxy On`: 핫스팟 프록시를 사용 중입니다.
- `Hotspot Proxy Unavailable`: 핫스팟은 감지됐지만 프록시 서버가 응답하지 않습니다.
- `Hotspot Proxy Idle`: 현재 Wi-Fi가 설정한 핫스팟이 아니어서 프록시를 사용하지 않습니다.
- `Wi-Fi Not Ready`: Wi-Fi route 또는 router가 아직 준비되지 않았습니다.
- `MHP Error`: 상태를 읽거나 해석하지 못했습니다.

UI state JSON 기본 경로는 다음과 같습니다. 이 파일에는 SSID, router IP, local path를 넣지 않습니다.

```text
~/Library/Application Support/hotspot-proxy-toggle/status.json
```

기본 menu bar item은 아이콘만 표시합니다. 표시 title과 refresh 간격은 다음처럼 바꿀 수 있습니다.

```bash
HOTSPOT_MENU_BAR=1 MENU_BAR_TITLE=MHP MENU_BAR_REFRESH_SECONDS=60 MENU_BAR_LOCALE=ko PROXY_PORT=1080 ./install.sh
```

Menu bar companion이 켜지면 아래 파일이 추가됩니다.

```text
~/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-menu
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.menu.plist
```

Menu bar status item은 기본적으로 상태 아이콘만 표시합니다. `MENU_BAR_TITLE`을 지정하면 title 옆에 아이콘을 표시합니다. 아이콘은 같은 휴대폰 핫스팟 glyph를 세 가지 형태로 구분합니다.

- 채워진 휴대폰: 핫스팟 프록시를 사용 중입니다.
- 외곽선 휴대폰: 현재 Wi-Fi가 설정한 핫스팟이 아니거나 MHP가 대기 중입니다.
- 대각선이 있는 채워진 휴대폰: 핫스팟은 감지됐지만 프록시를 사용할 수 없습니다.

Source install은 Finder와 Spotlight에서 실행할 수 있는 `MHP.app`도 설치합니다.

```text
~/Applications/MHP.app
```

`Quit MHP`로 menu bar item과 helper를 내린 뒤에는 Finder, Spotlight, Launchpad에서 `MHP`를 실행해 다시 올릴 수 있습니다. 앱은 Dock icon을 띄우지 않고 menu bar item만 표시합니다. App bundle은 핫스팟 프록시 켜짐 상태 glyph를 기반으로 한 아이콘을 사용합니다.

App bundle 설치를 생략하려면 다음처럼 실행합니다.

```bash
HOTSPOT_APP=0 PROXY_PORT=1080 ./install.sh
```

## 확인

```bash
~/.local/bin/hotspot-proxy-toggle status
/usr/sbin/networksetup -getsocksfirewallproxy Wi-Fi
```

즉시 한 번 reconcile하려면 다음 명령을 실행합니다.

```bash
~/.local/bin/hotspot-proxy-toggle run
```

macOS 프록시 설정을 바꾸지 않고 dry-run으로 확인할 수도 있습니다.

```bash
PROXY_PORT=1080 DRY_RUN=1 ./bin/hotspot-proxy-toggle run
```

## 설정

설정 파일은 다음 경로에 있습니다.

```text
~/.config/hotspot-proxy-toggle.conf
```

예시:

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
NOTIFY_ON_CHANGE=0
NOTIFICATION_LOCALE=auto
```

지원하는 backend는 다음과 같습니다.

- `PROXY_TYPE=socks5`: macOS SOCKS firewall proxy를 설정합니다.
- `PROXY_TYPE=http`: macOS Web Proxy와 Secure Web Proxy를 함께 설정합니다.

선택한 backend만 desired state로 취급합니다. `socks5`를 켜면 Web/Secure Web Proxy를 끄고, `http`를 켜면 SOCKS firewall proxy를 끕니다.

`REQUIRE_PROXY_CHECK=1`이면 핫스팟 라우터가 `PROXY_PORT`에서 SOCKS5 no-auth greeting에 응답할 때만 macOS 프록시 설정을 켭니다.
`PROXY_TYPE=http`에서는 같은 설정이 `router:PROXY_PORT`가 HTTP proxy처럼 응답하는지 확인합니다.

`NOTIFY_ON_CHANGE=1`이면 `run`의 최종 reconciliation state가 바뀌거나 실제 macOS 프록시 설정 변경이 있었을 때 macOS notification을 표시합니다. 예를 들어 SSID가 바뀌어 현재 Wi-Fi가 설정한 hotspot이 아닌 경우에도 한 번 알립니다. 같은 상태가 유지되는 동안에는 polling이나 helper watchdog이 다시 실행되어도 반복 알림을 보내지 않습니다.

Notification은 세 상태를 구분합니다.

- `✅ Hotspot Proxy On`: 핫스팟 프록시를 사용 중입니다.
- `⚠️ Hotspot Proxy Unavailable`: 핫스팟은 감지됐지만 프록시 서버가 응답하지 않습니다.
- `ℹ️ Hotspot Proxy Idle`: 현재 Wi-Fi가 설정한 핫스팟이 아니어서 프록시를 사용하지 않습니다.

Notification은 현재 macOS `osascript` notification을 사용하므로 sender icon을 상태별 custom icon으로 지정하지 않습니다. Notification title의 emoji는 상태 구분 보조 신호로 유지합니다.

Wi-Fi가 현재 기본 네트워크 경로가 아니거나 Wi-Fi router가 아직 확인되지 않은 transient 상태에서는 사용자 알림을 표시하지 않고, 내부 state만 기록합니다.

`NOTIFICATION_LOCALE=auto`이면 macOS 언어 설정이 한국어일 때 한국어 문구를 사용하고, 그 외에는 영어 문구를 사용합니다. `NOTIFICATION_LOCALE=en` 또는 `NOTIFICATION_LOCALE=ko`로 고정할 수 있습니다.

Notification 중복을 막기 위한 마지막 상태는 다음 local state file에 저장합니다.

```text
~/Library/Application Support/hotspot-proxy-toggle/state
```

## 제거

```bash
./uninstall.sh
```

설정 파일은 의도적으로 남겨둡니다.

```text
~/.config/hotspot-proxy-toggle.conf
```

## 개발

프로젝트 요구사항과 현재 동작은 아래 문서에 있습니다.

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- [docs/SPEC.md](docs/SPEC.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)

전체 개발 검증은 다음 명령으로 실행합니다.

```bash
./scripts/validate.sh
```

이 명령은 shell 문법 검사, 의사결정 로직 테스트, `shellcheck` 정적 분석을 실행합니다. `shellcheck`가 설치되어 있지 않으면 정적 분석만 건너뜁니다.

macOS에서 `shellcheck`는 Homebrew로 설치할 수 있습니다.

```bash
brew install shellcheck
```

의사결정 로직 테스트만 별도로 실행하려면 다음 명령을 사용합니다. 이 테스트는 macOS 프록시 설정을 바꾸지 않습니다.

```bash
./tests/run.sh
```

Event-driven helper를 직접 빌드해서 dry-run으로 한 번 실행해 볼 수 있습니다.

```bash
./scripts/build-helper.sh
.build/hotspot-proxy-toggle-helper --command ./bin/hotspot-proxy-toggle --dry-run --once
```

Menu bar companion도 직접 빌드할 수 있습니다.

```bash
./scripts/build-menu-bar.sh
.build/hotspot-proxy-toggle-menu --command ./bin/hotspot-proxy-toggle
```

`MHP.app` bundle도 직접 빌드할 수 있습니다.

```bash
./scripts/build-app.sh
open .build/MHP.app
```

패키지 매니저용 prefix 설치는 사용자 config나 LaunchAgent를 생성하지 않고 실행 파일, helper, app bundle, 예시 config만 설치합니다.

```bash
make install PREFIX=/usr/local
```

Release tag와 Homebrew tap Formula를 함께 갱신하려면 `homebrew-tap` checkout을 이 저장소 옆에 두거나 `HOMEBREW_TAP_DIR`로 지정한 뒤 release helper를 실행합니다.

```bash
HOMEBREW_TAP_DIR=../homebrew-tap ./scripts/release.sh v1.3.0
```

이 helper는 source validation, tag push, Formula `url`/`sha256` 갱신, tap commit/push, `brew audit`, source install, `brew test`를 순서대로 실행합니다.
