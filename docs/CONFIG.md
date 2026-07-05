# 설정

기본 설정 파일 경로:

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

## 네트워크와 핫스팟 감지

- `NETWORK_SERVICE`: macOS `networksetup` service 이름. 기본값은 `Wi-Fi`.
- `WIFI_DEVICE`: 비워두면 `networksetup -listallhardwareports`로 Wi-Fi device를 찾음.
- `HOTSPOT_SSIDS`: 정확히 매칭할 SSID allow-list. 쉼표로 구분함.
- `HOTSPOT_DHCP_MARKERS`: DHCP summary에서 찾을 marker. 기본값은 Android hotspot에 흔한 `ANDROID_METERED`.
- `STRICT_SSID=1`: DHCP marker fallback을 끄고 `HOTSPOT_SSIDS`만 사용함.

## Proxy Backend

지원 backend:

- `PROXY_TYPE=socks5`: macOS SOCKS firewall proxy를 설정함.
- `PROXY_TYPE=http`: macOS Web Proxy와 Secure Web Proxy를 같은 host/port로 함께 설정함.

선택한 backend만 desired state로 취급함. `socks5`를 켜면 Web/Secure Web Proxy를 끄고, `http`를 켜면 SOCKS firewall proxy를 끔.

`PROXY_PORT`는 휴대폰 핫스팟 라우터 IP에서 proxy server가 열어 둔 port임.

## Endpoint 확인

`REQUIRE_PROXY_CHECK=1`이면 핫스팟 라우터가 `PROXY_PORT`에서 실제 proxy처럼 응답할 때만 macOS 프록시 설정을 켬.

- `socks5`: SOCKS5 no-auth greeting에 대한 응답을 확인함.
- `http`: absolute URI 형식의 HTTP request에 `HTTP/` response line이 오는지 확인함.

`PROXY_CHECK_TIMEOUT`은 endpoint 확인 timeout 초 단위 값임.

## Notification

`NOTIFY_ON_CHANGE=1`이면 `run`의 최종 reconciliation state가 바뀌거나 실제 macOS 프록시 설정 변경이 있었을 때 macOS notification을 표시함. 같은 상태가 유지되는 동안에는 polling이나 helper watchdog이 다시 실행되어도 반복 알림을 보내지 않음.

Notification은 세 상태를 구분함.

- `✅ Hotspot Proxy On`: 핫스팟 프록시를 사용 중.
- `⚠️ Hotspot Proxy Unavailable`: 핫스팟은 감지됐지만 프록시 서버가 응답하지 않음.
- `ℹ️ Hotspot Proxy Idle`: 현재 Wi-Fi가 설정한 핫스팟이 아님.

Notification은 설치된 `MHP.app` sender를 우선 사용해 App icon으로 표시되게 시도함. App sender를 사용할 수 없으면 macOS `osascript` notification으로 되돌아감. 상태별 custom notification icon은 사용하지 않으므로 title의 emoji는 상태 구분 보조 신호로 유지함.

Wi-Fi가 현재 기본 네트워크 경로가 아니거나 Wi-Fi router가 아직 확인되지 않은 transient 상태에서는 사용자 알림을 표시하지 않고, 내부 state만 기록함.

`NOTIFICATION_LOCALE=auto`이면 macOS 언어 설정이 한국어일 때 한국어 문구를 사용하고, 그 외에는 영어 문구를 사용함. `NOTIFICATION_LOCALE=en` 또는 `NOTIFICATION_LOCALE=ko`로 고정할 수 있음.

Notification 중복을 막기 위한 마지막 상태는 다음 local state file에 저장함.

```text
~/Library/Application Support/hotspot-proxy-toggle/state
```
