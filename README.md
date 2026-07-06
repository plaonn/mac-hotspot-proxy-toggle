# mac-hotspot-proxy-toggle

[English](README.en.md) | 한국어

<p>
  <img src="docs/assets/mhp-app-icon.svg" width="96" alt="Mac Hotspot Proxy Toggle app icon">
</p>

일치하는 휴대폰 핫스팟과 프록시 endpoint가 있을 때만 macOS 프록시 설정을 켜는 작은 macOS 유틸리티입니다.

## 무엇을 해결하나요?

macOS 프록시 설정은 Wi-Fi SSID별이 아니라 `Wi-Fi` 같은 network service 단위로 적용됩니다. 휴대폰 핫스팟은 연결할 때마다 라우터 IP가 바뀔 수도 있습니다.

Mac Hotspot Proxy Toggle은 현재 네트워크 상태를 한 번 확인하고, 아래 조건이 맞을 때만 macOS 프록시를 켭니다.

1. 기본 route가 Wi-Fi입니다.
2. 현재 Wi-Fi SSID가 설정한 `HOTSPOT_SSID`와 정확히 일치합니다.
3. 현재 핫스팟 라우터 IP의 `PROXY_PORT`에서 proxy endpoint가 응답합니다.

조건이 맞지 않으면 프록시를 끕니다. 현재 backend는 `socks5`와 `http`를 지원합니다.

## 빠른 설치

### Homebrew

```bash
brew install plaonn/tap/hotspot-proxy-toggle
mkdir -p ~/.config
cp "$(brew --prefix)/etc/hotspot-proxy-toggle.conf.example" ~/.config/hotspot-proxy-toggle.conf
${EDITOR:-vi} ~/.config/hotspot-proxy-toggle.conf
brew services start plaonn/tap/hotspot-proxy-toggle
```

즉시 한 번 실행:

```bash
hotspot-proxy-toggle run
```

### Source

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 HOTSPOT_SSID='My Phone Hotspot' ./install.sh
```

Source install은 `~/Applications/MHP.app`도 설치합니다. `MHP.app`을 실행한 뒤 메뉴바에서 `Settings...`를 열면 `Hotspot SSID`, `Proxy Type`, `Proxy Port`, `Language`, `Start Automatically`를 GUI로 설정할 수 있습니다.

메뉴바 아이콘을 로그인 시 자동으로 띄우려면:

```bash
HOTSPOT_MENU_BAR=1 PROXY_PORT=1080 HOTSPOT_SSID='My Phone Hotspot' ./install.sh
```

자세한 설치 옵션은 [docs/INSTALL.md](docs/INSTALL.md)에 있습니다.

## 최소 설정

설정 파일:

```text
~/.config/hotspot-proxy-toggle.conf
```

핵심 값:

```bash
PROXY_TYPE=socks5
PROXY_PORT=1080
HOTSPOT_SSID='My Phone'
REQUIRE_PROXY_CHECK=1
```

- `PROXY_TYPE=socks5`: macOS SOCKS firewall proxy를 설정합니다.
- `PROXY_TYPE=http`: HTTP/HTTPS Web Proxy를 설정합니다. Web Proxy와 Secure Web Proxy를 같은 host/port로 함께 켭니다.
- `HOTSPOT_SSID`: 정확히 매칭할 단일 휴대폰 핫스팟 SSID입니다.
- `REQUIRE_PROXY_CHECK=1`: proxy endpoint가 실제 응답할 때만 macOS proxy setting을 켭니다.

전체 설정 설명은 [docs/CONFIG.md](docs/CONFIG.md)에 있습니다.

## 상태 아이콘

![Mac Hotspot Proxy Toggle status icons](docs/assets/mhp-status-icons.svg)

Menu bar item은 기본적으로 아이콘만 표시합니다. macOS template icon 규칙에 맞춰 색상 대신 alpha와 knockout shape으로 상태를 구분합니다.

| 상태 | 의미 |
| --- | --- |
| 채워진 휴대폰 | 핫스팟 프록시를 사용 중입니다. |
| 외곽선 휴대폰 | 현재 Wi-Fi가 설정한 핫스팟이 아니거나 대기 중입니다. |
| 대각선이 있는 채워진 휴대폰 | 핫스팟은 감지됐지만 프록시를 사용할 수 없습니다. |

Menu bar, `MHP.app`, notification, Settings 동작은 [docs/UI.md](docs/UI.md)에 있습니다.

## 확인

```bash
hotspot-proxy-toggle status
/usr/sbin/networksetup -getsocksfirewallproxy Wi-Fi
```

macOS 프록시 설정을 바꾸지 않고 dry-run으로 확인:

```bash
PROXY_PORT=1080 DRY_RUN=1 ./bin/hotspot-proxy-toggle run
```

## 문서

- [docs/INSTALL.md](docs/INSTALL.md): 설치, LaunchAgent, source install, 제거.
- [docs/CONFIG.md](docs/CONFIG.md): 설정 파일, backend, notification.
- [docs/UI.md](docs/UI.md): menu bar, app icon, 상태 아이콘.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): 개발 검증, 빌드, release.
- [docs/SPEC.md](docs/SPEC.md): 현재 구현 contract.
- [docs/ROADMAP.md](docs/ROADMAP.md): 공개 가능한 future direction.

## 개발

```bash
./scripts/validate.sh
```

더 자세한 개발 workflow는 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)에 있습니다.
