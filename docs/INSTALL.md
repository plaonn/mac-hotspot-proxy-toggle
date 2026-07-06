# 설치

## Homebrew

```bash
brew install plaonn/tap/hotspot-proxy-toggle
```

설정 파일을 만든 뒤 `PROXY_PORT`와 `HOTSPOT_SSID`를 수정합니다.

```bash
mkdir -p ~/.config
cp "$(brew --prefix)/etc/hotspot-proxy-toggle.conf.example" ~/.config/hotspot-proxy-toggle.conf
${EDITOR:-vi} ~/.config/hotspot-proxy-toggle.conf
```

event helper를 LaunchAgent로 실행합니다.

```bash
brew services start plaonn/tap/hotspot-proxy-toggle
```

즉시 한 번 reconcile하려면 다음 명령을 실행합니다.

```bash
hotspot-proxy-toggle run
```

## Source Install

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 ./install.sh
```

SSID를 같이 지정하려면 다음처럼 설치합니다.

```bash
PROXY_PORT=1080 HOTSPOT_SSID='My Phone Hotspot' ./install.sh
```

기본 설치에서 생성되는 주요 파일:

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-helper
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.helper.plist
~/Applications/MHP.app
```

설치를 다시 실행하면 기존 helper/polling LaunchAgent를 먼저 멈추고 generated plist를 삭제한 뒤 설치 파일을 갱신합니다. 설정 파일과 로그는 유지합니다.

## Event Helper

기본 설치는 네트워크 변경 event에 반응하는 helper LaunchAgent를 사용합니다. helper는 Swift로 빌드되며, macOS network change event를 debounce한 뒤 기존 `hotspot-proxy-toggle run`을 호출합니다. 프록시 판단과 설정 변경은 계속 single-shot runtime command가 담당합니다.

핫스팟 상태에서는 helper가 endpoint watchdog을 켭니다. 기본값은 60초마다 한 번 `hotspot-proxy-toggle run`을 호출하는 방식이며, 휴대폰 쪽 프록시 서버만 중간에 켜지거나 꺼지는 경우를 보정합니다. 일반 Wi-Fi처럼 hotspot이 아닌 상태에서는 watchdog을 끕니다.

```bash
HELPER_WATCHDOG_SECONDS=120 PROXY_PORT=1080 ./install.sh
```

watchdog을 끄려면 `HELPER_WATCHDOG_SECONDS=0`으로 설치합니다.

event helper 설치에는 macOS Swift compiler가 필요합니다. Xcode Command Line Tools가 설치된 환경이면 보통 사용할 수 있습니다. Swift compiler가 없거나 helper 설치가 실패하면 polling fallback이 설치됩니다.

## Polling Fallback

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

## Menu Bar와 App

source install에서 menu bar companion을 LaunchAgent로 함께 올리려면 `HOTSPOT_MENU_BAR=1`을 지정합니다.

```bash
HOTSPOT_MENU_BAR=1 PROXY_PORT=1080 ./install.sh
```

Menu bar companion이 켜지면 아래 파일이 추가됩니다.

```text
~/.local/share/hotspot-proxy-toggle/bin/hotspot-proxy-toggle-menu
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.menu.plist
```

Source install은 Finder와 Spotlight에서 실행할 수 있는 `MHP.app`도 설치합니다.

```text
~/Applications/MHP.app
```

`Quit Mac Hotspot Proxy Toggle`로 menu bar item과 helper를 내린 뒤에는 Finder, Spotlight, Launchpad에서 `Mac Hotspot Proxy Toggle`을 실행해 다시 올릴 수 있습니다. 앱은 Dock icon을 띄우지 않고 menu bar item만 표시합니다.

`MHP.app` menu의 `Settings...`에서는 `Hotspot SSID`, `Proxy Type`, `Proxy Port`, `Language`, `Start Automatically`를 설정할 수 있습니다. `Start Automatically`는 background helper와 menu bar app을 하나의 사용자 설정으로 함께 켜거나 끕니다.

App bundle 설치를 생략하려면 다음처럼 실행합니다.

```bash
HOTSPOT_APP=0 PROXY_PORT=1080 ./install.sh
```

## 제거

```bash
./uninstall.sh
```

설정 파일은 의도적으로 남겨둡니다.

```text
~/.config/hotspot-proxy-toggle.conf
```
