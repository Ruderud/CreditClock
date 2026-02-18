[English](./README.md) | [한국어](./README.ko.md)

<h1 align="center">CreditClock</h1>

<p align="center">
  AI 구독 사용량, 리필 시간, 플랜 상태를 한 화면에서 확인하세요.
  <br />
  Codex, Claude, Gemini를 위한 macOS 앱 + 데스크탑 위젯입니다.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-111111?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-0A84FF?style=flat-square" alt="SwiftUI + WidgetKit" />
  <img src="https://img.shields.io/badge/License-MIT-2563EB?style=flat-square" alt="MIT License" />
</p>

## 스크린샷

<p align="center">
  <img src="./docs/images/creditclock-app-main.png" width="620" alt="CreditClock 메인 데스크탑 앱" />
</p>

<p align="center">
  <img src="./docs/images/creditclock-widget-large.png" width="330" alt="CreditClock 위젯" />
</p>

<p align="center">
  <img src="./docs/images/creditclock-showcase.png" width="470" alt="CreditClock 쇼케이스" />
</p>

## CreditClock로 할 수 있는 것

- 여러 AI 서비스 사용량을 한 대시보드에서 통합 확인
- `5h`, `1w`, 일 단위 등 리필 카운트다운 확인
- 구독 상태(`Active`, `Trial`, `Paused`, `Expired`) 빠른 파악
- WidgetKit 위젯(`systemMedium`, `systemLarge`)으로 데스크탑에서 바로 확인
- 메뉴바에서 즉시 상태 확인 및 수동 리프레시

## 지원 Provider

| Provider | 데이터 소스 | 앱에서 설정 방법 |
|---|---|---|
| Codex (`OpenAI`) | 로컬 `~/.codex` 사용량 캐시/세션 로그, JWT fallback | 로컬 폴더 권한 승인 + `Connect` |
| Claude (`Anthropic`) | 로컬 `~/.claude/plugins/oh-my-claudecode/.usage-cache.json` 또는 Anthropic OAuth usage endpoint | 로컬 폴더 권한 승인 + `Connect` |
| Gemini | 로컬 `~/.gemini/oauth_creds.json` (CLI OAuth 쿼터) 또는 Gemini API 키 fallback | CLI OAuth를 위한 로컬 폴더 권한 승인, 또는 API 키 저장 + 활성화 |

## 설치 방법 (macOS)

사전 준비:

- macOS 14 이상
- Xcode 15 이상
- Homebrew + `xcodegen`

```bash
brew install xcodegen
xcodegen generate
open CreditClock.xcodeproj
```

Xcode에서 `CreditClock` 스킴을 실행하세요.

## 백그라운드 동작 방식

- CreditClock는 메뉴바 에이전트로 동작합니다 (Dock 아이콘/상시 메인 창 없음).
- Provider 설정이 끝나면 백그라운드에서 주기적으로 폴링하고 위젯 데이터를 갱신합니다.
- 설정 창을 닫아도 백그라운드 폴링은 계속 유지됩니다.
- 메뉴바에서 `Quit`를 누르면 앱이 완전히 종료되어 폴링도 중단됩니다.
- 로그인 후 자동 실행이 필요하면 메뉴바 패널에서 `Launch at Login`을 켜세요.

## 위젯 추가 방법 (데스크탑)

1. 데스크탑 빈 공간을 우클릭하고 `Edit Widgets`를 선택합니다.
2. `CreditClock`를 검색합니다.
3. 크기(`Medium` 또는 `Large`)를 선택해 데스크탑에 추가합니다.
4. 초기 설정 후 CreditClock 메뉴바 패널에서 `Refresh Now`를 1회 누릅니다.
5. 위젯에 계속 `No synced data`가 보이면, 리프레시 후 위젯을 제거/재추가합니다.

## 설정 체크리스트

- `Settings` -> `Local Data Access`에서 `Grant Codex + Claude + Gemini Together (Recommended)`를 누르고 홈 폴더(`~`)를 1회 선택합니다.
- `OpenAI`, `Anthropic`는 `Connect`를 눌러 연결합니다.
- `Anthropic` 테스트가 실패하면 `Re-login Claude`를 사용합니다.
- `Gemini`는 로컬 CLI OAuth(`~/.gemini/oauth_creds.json`)를 사용하거나 API 키를 저장 후 활성화합니다.
- Provider별 `Test` 버튼으로 연결 상태를 확인합니다.

## 사용 방법

1. `CreditClock` 앱을 실행합니다.
2. 메뉴바 아이콘(`creditcard.circle`)에서 `Settings`를 엽니다.
3. 위 `설정 체크리스트`를 완료합니다.
4. `위젯 추가 방법 (데스크탑)`에 따라 위젯을 추가합니다.
5. CreditClock를 메뉴바에서 계속 실행 상태로 유지합니다 (선택: `Launch at Login` 활성화).

> 설치 안내 (2026-02-17 기준): CreditClock는 아직 코드사이닝되지 않아 실제 설치/실행은 Xcode에서 `CreditClock` 스킴으로 직접 진행해야 합니다.

## 문제 해결

- `No providers configured`: `Settings`에서 최소 1개 Provider를 연결하세요.
- 위젯에 `No synced data` 표시: 앱에서 `Refresh` 1회 후 위젯을 제거/재추가하세요.
- 폴더 권한 오류: `Settings`에서 로컬 권한을 다시 승인하세요.
- 재부팅 후 위젯 갱신이 멈춤: 메뉴바에서 `Launch at Login`이 켜져 있는지 확인하세요.

## 개인정보/보안

- 로컬 Provider 데이터는 사용자 기기 경로(`~/.codex`, `~/.claude`, `~/.gemini`)에서 읽습니다.
- API 키는 macOS Keychain에 저장됩니다.
- 앱-위젯 동기화는 App Group + 로컬 fallback 경로를 함께 사용합니다.

<details>
<summary><strong>Development</strong></summary>

### 기술 스택

- Swift 5.10
- SwiftUI (macOS 앱)
- WidgetKit (데스크탑 위젯)
- XcodeGen (`project.yml` 기반 프로젝트 생성)

### 프로젝트 구조

```text
CreditClock/
├── CreditClockApp/                 # macOS 메뉴바 에이전트 + 설정
├── CreditClockWidget/              # WidgetKit 확장
├── Shared/
│   ├── Models/                     # 스냅샷/상태 모델
│   ├── Persistence/                # App Group, fallback 저장소, keychain 래퍼
│   ├── Providers/                  # OpenAI/Anthropic/Gemini 어댑터
│   └── Store/                      # 리프레시 오케스트레이션 + 폴링
├── scripts/                        # 타입체크, 버전 증가, 릴리스 스크립트
└── project.yml                     # XcodeGen 기준 파일
```

### 로컬 개발

```bash
# Xcode 프로젝트 생성
xcodegen generate

# pre-commit과 동일한 Swift 타입체크 실행
./scripts/typecheck.sh
```

### Pre-commit 자동화

`.husky/pre-commit`에서 아래 순서로 실행합니다.

1. `scripts/bump-version.sh`
   - `VERSION` 패치 버전 증가
   - `Shared/Generated/BuildVersion.generated.swift` 재생성
2. `scripts/typecheck.sh`

새 클론에서 훅 활성화:

```bash
git config core.hooksPath .husky
```

필요 시 1회 버전 증가 스킵:

```bash
CREDITCLOCK_SKIP_VERSION_BUMP=1 git commit -m "your message"
```

### 빌드 / 릴리스 스크립트

```bash
# unsigned Release 앱 빌드 + zip 아티팩트 생성
./scripts/build-release-artifact.sh

# main-latest GitHub release 업로드/갱신 (gh auth 필요)
./scripts/upload-main-release.sh
```

### 데이터 동기화 참고

- 기본 동기화: App Group 컨테이너 (`group.com.creditclock.shared`)
- fallback: `~/.creditclock/snapshots.json`
- 위젯 브리지 fallback: `~/Library/Containers/com.creditclock.app.widget/Data/Documents/snapshots.json`

</details>

## 라이선스

MIT License. 자세한 내용은 [LICENSE](./LICENSE)를 확인하세요.
