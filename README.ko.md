[English](./README.md) | [Korean](./README.ko.md)

<h1 align="center">CreditClock</h1>

<p align="center">
  AI 구독 사용량, 리필 시간, 구독 상태를 한 번에 보여주는 대시보드.
  <br />
  SwiftUI + WidgetKit 기반 macOS 앱입니다.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-111111?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-0A84FF?style=flat-square" alt="SwiftUI + WidgetKit" />
  <img src="https://img.shields.io/badge/Status-MVP-5E5CE6?style=flat-square" alt="MVP" />
  <img src="https://img.shields.io/badge/Open%20Source-Yes-22C55E?style=flat-square" alt="Open Source" />
  <img src="https://img.shields.io/badge/License-MIT-2563EB?style=flat-square" alt="MIT License" />
</p>

## CreditClock가 필요한 이유

AI 서비스마다 사용량 확인 위치와 포맷이 다릅니다.
CreditClock는 이를 하나로 모아 아래 질문에 즉시 답할 수 있게 합니다.

- 지금 남은 크레딧은 얼마인가?
- 서비스별 리필(초기화) 시점은 언제인가?
- 구독 상태가 활성/체험/일시중지/만료 중 무엇인가?

## 주요 기능

- **통합 사용량 뷰**: 여러 서비스의 사용량과 잔여량을 한 화면에서 확인
- **리필 카운트다운**: 서비스별 리필/초기화 타이밍 빠르게 파악
- **구독 상태 확인**: `active`, `trial`, `paused`, `expired` 상태 추적
- **macOS 위젯 지원**: 데스크탑 위젯에서 핵심 정보 즉시 확인
- **App Group 데이터 공유**: 앱과 위젯 간 스냅샷 동기화
- **Provider 추상화**: UI 변경 없이 실제 API Provider 연결 가능

## 기술 스택

| 레이어 | 기술 |
|---|---|
| Language | Swift 5.10 |
| App UI | SwiftUI (macOS) |
| Widget | WidgetKit |
| 데이터 공유 | App Groups + `UserDefaults(suiteName:)` |
| 프로젝트 생성 | XcodeGen |

## 아키텍처

```text
CreditClock/
├── CreditClockApp/                 # macOS SwiftUI 앱
├── CreditClockWidget/              # WidgetKit 확장
├── Shared/
│   ├── Models/                     # ServiceSnapshot, 상태 모델
│   ├── Persistence/                # App Group 저장소
│   ├── Providers/                  # Provider 프로토콜 + 구현체
│   └── Store/                      # 앱 상태 + 리프레시 흐름
└── project.yml                     # XcodeGen 정의
```

핵심 설계 원칙:

- API 연결 로직은 `ServiceProvider` 뒤로 분리
- 앱/위젯은 공용 스냅샷 저장소로 동기화
- UI는 `ServiceSnapshot` 기준으로 API 세부사항과 분리

## 빠른 시작

```bash
# 1) xcodegen 설치 (미설치 시)
brew install xcodegen

# 2) Xcode 프로젝트 생성
xcodegen generate

# 3) Xcode에서 열기
open CreditClock.xcodeproj
```

그 다음 `CreditClock` 스킴을 실행하세요.

## 커밋 자동화 (Husky 스타일)

CreditClock는 `.husky/` 기반 `pre-commit` 훅으로 기본 품질/버전 메타데이터를 자동 처리합니다.

- Shared/App/Widget Swift 소스 타입체크 실행
- 커밋마다 `VERSION` 패치 버전 자동 증가
- `/Shared/Generated/BuildVersion.generated.swift` 재생성 및 자동 스테이징

로컬 클론에서 훅이 비활성화되어 있다면 아래를 실행하세요.

```bash
git config core.hooksPath .husky
```

## 실제 API 연동

현재는 MVP 개발을 위해 Mock Provider를 사용합니다.
OpenAI, Anthropic, Gemini 등 실제 서비스 연동 시:

1. `Shared/Providers/MockProviders.swift`의 `ProviderCatalog.defaultProviders()`를 실제 Provider로 교체
2. `Shared/Providers/JSONEndpointProvider.swift`로 서비스별 Provider 구성
3. API 응답을 `ServiceSnapshot`으로 매핑
4. API 토큰은 소스가 아닌 Keychain에 저장

개념 예시:

```swift
var request = URLRequest(url: URL(string: "https://api.example.com/usage")!)
request.addValue("Bearer <token>", forHTTPHeaderField: "Authorization")

let provider = JSONEndpointProvider(serviceId: "example", request: request) { data in
    // 응답 디코딩 후 ServiceSnapshot으로 매핑
}
```

## 로드맵

- [ ] OpenAI / Anthropic / Gemini 1차 Provider 구현
- [ ] 서비스별 리필 정책 모델링 (고정 시각, 결제 주기, 롤링 윈도우)
- [ ] 실패 시 재시도/백오프/캐시 정책 강화
- [ ] 토큰 관리 및 Provider On/Off 설정 UI 추가
- [ ] 위젯 외 메뉴바 모드 확장 검토

## 오픈소스

CreditClock는 **오픈소스 프로그램**입니다. 이슈/피드백/기여를 환영합니다.

## 라이선스

MIT License. 자세한 내용은 [LICENSE](./LICENSE) 참조.
