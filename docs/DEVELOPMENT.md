# 개발

프로젝트 요구사항과 현재 동작은 아래 문서에 있습니다.

- [REQUIREMENTS.md](REQUIREMENTS.md)
- [SPEC.md](SPEC.md)
- [ROADMAP.md](ROADMAP.md)

## 검증

전체 개발 검증:

```bash
./scripts/validate.sh
```

이 명령은 shell 문법 검사, 의사결정 로직 테스트, `shellcheck` 정적 분석, helper/menu/app build를 실행합니다. `shellcheck`가 설치되어 있지 않으면 정적 분석만 건너뜁니다.

macOS에서 `shellcheck`는 Homebrew로 설치할 수 있습니다.

```bash
brew install shellcheck
```

의사결정 로직 테스트만 별도로 실행하려면 다음 명령을 사용합니다. 이 테스트는 macOS 프록시 설정을 바꾸지 않습니다.

```bash
./tests/run.sh
```

## 직접 빌드

Event-driven helper:

```bash
./scripts/build-helper.sh
.build/hotspot-proxy-toggle-helper --command ./bin/hotspot-proxy-toggle --dry-run --once
```

Menu bar companion:

```bash
./scripts/build-menu-bar.sh
.build/hotspot-proxy-toggle-menu --command ./bin/hotspot-proxy-toggle
```

`MHP.app` bundle:

```bash
./scripts/build-app.sh
open .build/MHP.app
```

패키지 매니저용 prefix 설치는 사용자 config나 LaunchAgent를 생성하지 않고 실행 파일, helper, app bundle, 예시 config만 설치합니다.

```bash
make install PREFIX=/usr/local
```

## Release

Release tag를 push하면 GitHub Actions가 Homebrew tap Formula 갱신을 수행합니다. 이 workflow는 source validation, Formula `url`/`sha256` 갱신, tap commit/push, `brew audit`, source install, `brew test`를 순서대로 실행합니다.

```bash
git tag v1.4.1
git push origin main v1.4.1
```

Workflow가 `plaonn/homebrew-tap`에 push하려면 source repository secret `HOMEBREW_TAP_TOKEN`이 필요합니다. Secret 값은 저장소에 넣지 않습니다.

로컬에서 source validation과 tag push까지만 수행하고 tap 갱신은 GitHub Actions에 맡기려면 다음처럼 실행합니다.

```bash
UPDATE_HOMEBREW_TAP=0 ./scripts/release.sh v1.4.1
```

GitHub Actions를 사용하지 않고 로컬에서 Release tag와 Homebrew tap Formula를 함께 갱신하려면 `homebrew-tap` checkout을 이 저장소 옆에 두거나 `HOMEBREW_TAP_DIR`로 지정한 뒤 release helper를 실행합니다.

```bash
HOMEBREW_TAP_DIR=../homebrew-tap ./scripts/release.sh v1.4.1
```

이 로컬 helper도 source validation, tag push, Formula `url`/`sha256` 갱신, tap commit/push, `brew audit`, source install, `brew test`를 순서대로 실행합니다.
