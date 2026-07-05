# UI

<p>
  <img src="assets/mhp-app-icon.svg" width="96" alt="MHP app icon">
</p>

MHP는 menu bar companion과 `MHP.app`을 제공함. 핵심 프록시 판단과 macOS proxy write는 계속 `hotspot-proxy-toggle run`이 담당하고, UI는 상태 표시와 사용자의 즉시 실행 진입점 역할만 함.

## Menu Bar Companion

![MHP menu preview](assets/mhp-menu-preview.svg)

Menu bar companion은 `hotspot-proxy-toggle run`/`off`가 쓰는 UI state JSON을 watch해 상태를 갱신함. 메뉴에서 `Refresh Status`를 선택하면 상태만 다시 확인하고, `Reconcile Now`를 선택하면 `hotspot-proxy-toggle run`을 한 번 실행함. `Quit MHP`는 `hotspot-proxy-toggle off`로 proxy setting을 끄고 helper/menu LaunchAgent를 내림.

UI state JSON 기본 경로:

```text
~/Library/Application Support/hotspot-proxy-toggle/status.json
```

이 파일에는 SSID, router IP, local path를 넣지 않음.

## 상태 아이콘

![MHP status icons](assets/mhp-status-icons.svg)

Menu bar status item은 기본적으로 상태 아이콘만 표시함. `MENU_BAR_TITLE`을 지정하면 title 옆에 아이콘을 표시함.

```bash
HOTSPOT_MENU_BAR=1 MENU_BAR_TITLE=MHP MENU_BAR_REFRESH_SECONDS=60 MENU_BAR_LOCALE=ko PROXY_PORT=1080 ./install.sh
```

아이콘은 같은 휴대폰 핫스팟 glyph를 세 가지 형태로 구분함.

| 아이콘 | 의미 |
| --- | --- |
| 채워진 휴대폰 | 핫스팟 프록시를 사용 중 |
| 외곽선 휴대폰 | 현재 Wi-Fi가 설정한 핫스팟이 아니거나 MHP가 대기 중 |
| 대각선이 있는 채워진 휴대폰 | 핫스팟은 감지됐지만 프록시를 사용할 수 없음 |

macOS menu bar icon은 template image이므로 색상은 macOS가 정하고, glyph의 alpha와 knockout shape만 상태를 표현함.

## Menu Status

Menu status는 notification 문맥과 맞춘 5상태를 사용함.

- `Hotspot Proxy On`: 핫스팟 프록시를 사용 중.
- `Hotspot Proxy Unavailable`: 핫스팟은 감지됐지만 프록시 서버가 응답하지 않음.
- `Hotspot Proxy Idle`: 현재 Wi-Fi가 설정한 핫스팟이 아님.
- `Wi-Fi Not Ready`: Wi-Fi route 또는 router가 아직 준비되지 않음.
- `MHP Error`: 상태를 읽거나 해석하지 못함.

## MHP.app

`MHP.app`은 Finder, Spotlight, Launchpad에서 실행할 수 있는 LSUIElement app임. Dock icon을 띄우지 않고 menu bar item만 표시함.

App bundle은 핫스팟 프록시 켜짐 상태 glyph를 기반으로 한 아이콘을 사용함. Notification은 가능하면 이 app sender를 사용해 같은 app icon으로 표시되게 시도함.
