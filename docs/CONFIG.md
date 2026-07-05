# 설정

기본 설정 파일 경로:

```text
~/.config/hotspot-proxy-toggle.conf
```

예시:

```bash
NETWORK_SERVICE=''
WIFI_DEVICE=''
PROXY_TYPE=socks5
PROXY_PORT=1080
HOTSPOT_SSID='My Phone'
REQUIRE_PROXY_CHECK=1
PROXY_CHECK_TIMEOUT=1
NOTIFY_ON_CHANGE=0
LANGUAGE=auto
```

설정 파일은 제한된 `KEY=value` 형식으로 읽습니다. 빈 줄과 `#` comment를 사용할 수 있고, 값은 unquoted, single-quoted, double-quoted 형식을 지원합니다. Runtime은 설정 파일을 shell script로 `source`하지 않고, 지원하는 key만 읽습니다.

## 네트워크와 핫스팟 감지

- `HOTSPOT_SSID`: 정확히 매칭할 단일 휴대폰 핫스팟 SSID입니다. 이 값이 현재 Wi-Fi SSID와 같을 때만 hotspot candidate로 봅니다.
- `NETWORK_SERVICE`: macOS `networksetup` service 이름 override입니다. 비워두면 Wi-Fi device에 대응하는 service를 자동으로 찾습니다.
- `WIFI_DEVICE`: Wi-Fi device override입니다. 비워두면 `networksetup -listallhardwareports`로 Wi-Fi device를 찾습니다.

## Proxy Backend

지원 backend:

- `PROXY_TYPE=socks5`: macOS SOCKS firewall proxy를 설정합니다.
- `PROXY_TYPE=http`: macOS Web Proxy와 Secure Web Proxy를 같은 host/port로 함께 설정합니다. Settings UI에서는 `HTTP/HTTPS Web Proxy`로 표시합니다.

선택한 backend만 desired state로 취급합니다. `socks5`를 켜면 Web/Secure Web Proxy를 끄고, `http`를 켜면 SOCKS firewall proxy를 끕니다.

`PROXY_PORT`는 휴대폰 핫스팟 라우터 IP에서 proxy server가 열어 둔 port입니다.

## Endpoint 확인

`REQUIRE_PROXY_CHECK=1`이면 핫스팟 라우터가 `PROXY_PORT`에서 실제 proxy처럼 응답할 때만 macOS 프록시 설정을 켭니다.

- `socks5`: SOCKS5 no-auth greeting에 대한 응답을 확인합니다.
- `http`: absolute URI 형식의 HTTP request에 `HTTP/` response line이 오는지 확인합니다.

`PROXY_CHECK_TIMEOUT`은 endpoint 확인 timeout 초 단위 값입니다.

## Notification

`NOTIFY_ON_CHANGE=1`이면 `run`의 최종 reconciliation state가 바뀌거나 실제 macOS 프록시 설정 변경이 있었을 때 macOS notification을 표시합니다. 같은 상태가 유지되는 동안에는 polling이나 helper watchdog이 다시 실행되어도 반복 알림을 보내지 않습니다.

Notification은 세 상태를 구분합니다.

- `✅ Hotspot Proxy On`: 핫스팟 프록시를 사용 중입니다.
- `⚠️ Hotspot Proxy Unavailable`: 핫스팟은 감지됐지만 프록시 서버가 응답하지 않습니다.
- `ℹ️ Hotspot Proxy Idle`: 현재 Wi-Fi가 설정한 핫스팟이 아닙니다.

Notification은 설치된 `MHP.app` sender를 우선 사용해 App icon으로 표시되게 시도합니다. App sender를 사용할 수 없으면 macOS `osascript` notification으로 되돌아갑니다. 상태별 custom notification icon은 사용하지 않으므로 title의 emoji는 상태 구분 보조 신호로 유지합니다.

Wi-Fi가 현재 기본 네트워크 경로가 아니거나 Wi-Fi router가 아직 확인되지 않은 transient 상태에서는 사용자 알림을 표시하지 않고, 내부 state만 기록합니다.

`LANGUAGE=auto`이면 macOS 언어 설정이 한국어일 때 한국어 문구를 사용하고, 그 외에는 영어 문구를 사용합니다. `LANGUAGE=en` 또는 `LANGUAGE=ko`로 고정할 수 있습니다.

Notification 중복을 막기 위한 마지막 상태는 다음 local state file에 저장합니다.

```text
~/Library/Application Support/hotspot-proxy-toggle/state
```
