[English](./README.md) | [Korean](./README.ko.md)

# CreditClock

CreditClock는 여러 AI 서비스의 사용량, 리필 시간, 구독 상태를 한 곳에서 확인할 수 있는 macOS 앱 + 위젯 MVP입니다.

## 현재 포함된 기능 (MVP)
- macOS SwiftUI 대시보드
- WidgetKit 위젯 (`systemMedium`, `systemLarge`)
- 공용 데이터 모델 (`ServiceSnapshot`)
- App Group 기반 앱/위젯 데이터 공유
- Provider 추상화 + Mock Provider
- 실제 API 연동을 위한 HTTP JSON Provider 스캐폴드

## 생성 및 실행
이 저장소는 `xcodegen` 기반으로 구성되어 있습니다.

1. 필요 시 `xcodegen` 설치: `brew install xcodegen`
2. 프로젝트 루트에서 실행: `xcodegen generate`
3. 생성된 `CreditClock.xcodeproj`를 Xcode에서 열기
4. `CreditClock` 스킴 실행

## 프로젝트 구조
- `project.yml`: XcodeGen 프로젝트 설정
- `CreditClockApp/`: macOS 앱 UI
- `CreditClockWidget/`: 위젯 Extension
- `Shared/`: 앱/위젯 공용 모델, Provider, 저장소

## 실제 API 연동 방법
현재 설정은 Mock Provider를 사용합니다. 실제 서비스 연동 시 아래 순서로 교체하세요.

1. `Shared/Providers/MockProviders.swift`의 `ProviderCatalog.defaultProviders()`에서 Mock Provider 제거
2. `Shared/Providers/JSONEndpointProvider.swift`를 사용해 서비스별 Provider 생성
3. 각 서비스 API 응답을 `ServiceSnapshot`으로 매핑
4. 민감 정보(API 키/토큰)는 Keychain 또는 보안 저장소에 저장

개념 예시:
```swift
var req = URLRequest(url: URL(string: "https://api.example.com/usage")!)
req.addValue("Bearer <token>", forHTTPHeaderField: "Authorization")

let provider = JSONEndpointProvider(serviceId: "example", request: req) { data in
    // data 디코딩 후 ServiceSnapshot으로 매핑
}
```

## 다음 권장 작업
- 서비스별 인증 방식과 엔드포인트 확정
- 서비스별 리필 규칙(고정 시각, 결제 주기 초기화, 롤링 윈도우) 모델링
- 실패 캐싱/재시도/백오프 정책 추가
- 메뉴바 앱 형태로 확장할지 결정
