# Settings window 제안

## 상태

구현됨. 현재 동작은 `docs/SPEC.md`를 기준으로 함.

## Root goal

사용자가 terminal config 편집 없이 MHP를 처음 설정하고 자동 실행 상태를 관리할 수 있게 함.

Settings는 핵심 proxy 판단과 macOS proxy write policy를 재구현하지 않음. 저장된 config와 LaunchAgent 상태를 갱신하고, 실제 reconciliation은 계속 `hotspot-proxy-toggle run`이 담당함.

## 사용자 모델

MHP는 단일 휴대폰 핫스팟 위에서 실행 중인 단일 proxy endpoint를 대상으로 함.

복수 SSID allow-list나 SSID별 profile은 현재 범위가 아님. 복수 SSID를 지원하려면 SSID별 proxy type, port, 상태 표시, notification, validation을 분리하는 profile model이 필요함.

## Main settings

- `Hotspot SSID`: 단일 SSID. 현재 Wi-Fi가 사용자가 의도한 핫스팟인지 판단하는 identity gate임.
- `Proxy Type`: `SOCKS5` 또는 `HTTP/HTTPS Web Proxy`. `HTTP/HTTPS Web Proxy`는 macOS Web Proxy와 Secure Web Proxy를 같은 host/port로 설정하는 현재 `PROXY_TYPE=http` backend를 표시하는 사용자-facing 이름임.
- `Proxy Port`: 현재 핫스팟 router IP에서 proxy server가 listen하는 port.
- `Language`: `System Default`, `English`, `한국어`. UI와 notification에 동일한 사용자-facing language setting을 적용함.
- `Start Automatically`: 사용자 관점의 단일 자동 시작 toggle. 켜면 background helper와 menu bar app을 함께 시작하고 로그인 시 자동 시작되게 함. 끄면 helper와 menu LaunchAgent를 함께 내림.

## Advanced settings

Advanced는 일반 설정이 아니라 troubleshooting용으로 둠.

- `Proxy Check Timeout`: endpoint check timeout, seconds.
- `Helper Watchdog Interval`: hotspot 상태에서 proxy endpoint on/off 변화를 보정하는 watchdog interval, seconds.

## Diagnostics

Settings는 아래 값을 read-only diagnostics로 보여줄 수 있음.

- detected Wi-Fi device
- current default route interface
- detected Wi-Fi network service
- helper/menu LaunchAgent loaded state
- config path
- log path

## Auto-detected network service

사용자가 `NETWORK_SERVICE`와 `WIFI_DEVICE`를 직접 설정하지 않아도 되게 함.

Runtime은 Wi-Fi hardware port의 device를 찾고, `networksetup -listnetworkserviceorder`에서 해당 device와 연결된 network service name을 찾는 방향으로 개선함. Proxy write에는 service name이 필요하지만, 사용자가 기본값 `Wi-Fi`에 의존하거나 직접 service name을 알 필요가 없게 하는 것이 목표임.

Manual override는 유지할 수 있지만 Settings UI에는 노출하지 않음. 필요하면 config file에서만 다룸.

## 제외

- `HOTSPOT_DHCP_MARKERS`: Android hotspot 여부는 알 수 있어도 사용자가 의도한 proxy hotspot identity를 보장하지 못하므로 제거 또는 manual-only deprecation 대상으로 둠.
- `STRICT_SSID`: strict SSID match가 기본이자 유일한 일반 동작이므로 사용자 설정으로 두지 않음.
- `REQUIRE_PROXY_CHECK`: endpoint check는 MHP의 핵심 안전장치이므로 일반 사용자 toggle로 노출하지 않음.
- `NETWORK_SERVICE`, `WIFI_DEVICE`: Settings에서는 read-only diagnostics 또는 manual config override로만 다룸.
- Path override, install path, build option: Settings 범위가 아님.
- Background helper만 켜거나 menu app만 켜는 분리 상태: 일반 사용자 설정으로 만들지 않음.

## 저장 동작

Settings 저장은 whitelisted config key만 갱신함.

Config 문법은 제한된 dotenv-style `KEY=value` 형식으로 유지함. 파일 경로는 `~/.config/hotspot-proxy-toggle.conf`를 유지하고, runtime은 shell `source` 대신 제한 parser를 사용함.

저장 후에는 현재 세션에서 한 번 reconcile할 수 있음. 이 동작은 설정 항목이 아니라 save action의 후속 동작임.
