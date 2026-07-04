# mac-hotspot-proxy-toggle

일치하는 휴대폰 핫스팟과 프록시 endpoint가 있을 때만 macOS 프록시 설정을 켜는 작은 macOS 유틸리티입니다.

현재 release는 현재 핫스팟 라우터 IP 위의 SOCKS5만 지원합니다. 프로젝트 이름과 설정은 proxy-generic하게 유지하여, 나중에 다른 macOS 프록시 타입을 추가할 수 있도록 했습니다.

## 왜 필요한가

macOS 프록시 설정은 Wi-Fi SSID별이 아니라 `Wi-Fi` 같은 network service 단위로 적용됩니다. 또한 휴대폰 핫스팟은 연결할 때마다 라우터 IP가 바뀔 수 있습니다.

이 유틸리티는 다음 상태를 reconcile합니다.

1. 기본 route가 Wi-Fi인지 확인합니다.
2. 현재 Wi-Fi 라우터 IP를 DHCP 상태에서 읽습니다.
3. 현재 Wi-Fi가 설정된 휴대폰 핫스팟처럼 보이는지 판단합니다.
4. `router:PROXY_PORT`의 프록시 endpoint를 확인합니다.
5. endpoint가 사용 가능할 때만 macOS 프록시 설정을 켜고, 그렇지 않으면 끕니다.

## 설치

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 ./install.sh
```

SSID를 정확히 지정하려면 다음처럼 설치합니다.

```bash
PROXY_PORT=1080 HOTSPOT_SSIDS='My Phone Hotspot' ./install.sh
```

설치되는 파일은 다음과 같습니다.

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

LaunchAgent는 기본적으로 60초마다 실행됩니다.

```bash
CHECK_INTERVAL_SECONDS=30 PROXY_PORT=1080 ./install.sh
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
```

현재 release에서 지원하는 backend는 `PROXY_TYPE=socks5`뿐입니다.

`REQUIRE_PROXY_CHECK=1`이면 핫스팟 라우터가 `PROXY_PORT`에서 SOCKS5 no-auth greeting에 응답할 때만 macOS 프록시 설정을 켭니다.

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
