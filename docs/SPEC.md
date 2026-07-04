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

## Event-driven helper prototype

`Sources/hotspot-proxy-toggle-helper/main.swift`에는 event-driven helper prototype이 있음.

현재 helper prototype은 아래 역할만 함:

- SystemConfiguration dynamic store network change notification을 관찰함.
- event burst를 debounce함.
- child process로 기존 `hotspot-proxy-toggle run`을 호출함.
- `--dry-run`이면 child command에 `DRY_RUN=1`을 전달함.
- `--once`이면 event loop 없이 child command를 한 번 실행하고 종료함.

helper prototype은 macOS proxy setting을 직접 변경하지 않고, hotspot/proxy decision을 재구현하지 않음.

현재 설치 기본값은 여전히 polling LaunchAgent임. `install.sh`는 helper prototype을 설치하거나 helper LaunchAgent를 생성하지 않음.

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

## 설치

`install.sh`는 아래를 설치함:

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

LaunchAgent는 아래 command를 호출함:

```text
hotspot-proxy-toggle run
```

기본 polling interval은 60초임.

## 제거

`uninstall.sh`는 LaunchAgent를 unload하고, 설치된 binary tree와 command symlink를 제거하며, config file은 유지함.
