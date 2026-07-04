# mac-hotspot-proxy-toggle

일치하는 휴대폰 핫스팟과 프록시 endpoint가 있을 때만 macOS 프록시 설정을 켜는 작은 macOS 유틸리티임.

현재 release는 현재 핫스팟 라우터 IP 위의 SOCKS5만 지원함. 프로젝트 이름과 설정은 일부러 proxy-generic하게 두었고, 나중에 다른 macOS 프록시 타입을 추가할 수 있게 함.

## 왜 필요한가

macOS 프록시 설정은 Wi-Fi SSID별이 아니라 `Wi-Fi` 같은 network service 단위로 붙음. 휴대폰 핫스팟은 연결할 때마다 라우터 IP가 바뀔 수도 있음.

이 유틸리티는 다음 상태를 reconcile함:

1. 기본 route가 Wi-Fi인지 확인함.
2. 현재 Wi-Fi 라우터 IP를 DHCP 상태에서 읽음.
3. 현재 Wi-Fi가 설정된 휴대폰 핫스팟처럼 보이는지 판단함.
4. `router:PROXY_PORT`의 프록시 endpoint를 확인함.
5. endpoint가 사용 가능할 때만 macOS 프록시 설정을 켬. 아니면 끔.

## 설치

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 ./install.sh
```

SSID를 정확히 지정하고 싶으면:

```bash
PROXY_PORT=1080 HOTSPOT_SSIDS='My Phone Hotspot' ./install.sh
```

설치되는 파일:

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

LaunchAgent는 기본 60초마다 실행됨:

```bash
CHECK_INTERVAL_SECONDS=30 PROXY_PORT=1080 ./install.sh
```

## 확인

```bash
~/.local/bin/hotspot-proxy-toggle status
/usr/sbin/networksetup -getsocksfirewallproxy Wi-Fi
```

즉시 한 번 reconcile:

```bash
~/.local/bin/hotspot-proxy-toggle run
```

macOS 프록시 설정을 바꾸지 않는 dry-run:

```bash
PROXY_PORT=1080 DRY_RUN=1 ./bin/hotspot-proxy-toggle run
```

## 설정

설정 파일:

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

현재 release에서 지원하는 backend는 `PROXY_TYPE=socks5`뿐임.

`REQUIRE_PROXY_CHECK=1`이면 핫스팟 라우터가 `PROXY_PORT`에서 SOCKS5 no-auth greeting에 응답할 때만 macOS 프록시 설정을 켬.

## 제거

```bash
./uninstall.sh
```

설정 파일은 의도적으로 남겨둠:

```text
~/.config/hotspot-proxy-toggle.conf
```

## 개발

프로젝트 요구사항과 현재 동작은 아래 문서에 있음:

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- [docs/SPEC.md](docs/SPEC.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)

shell 문법 검증:

```bash
bash -n bin/hotspot-proxy-toggle install.sh uninstall.sh
```
