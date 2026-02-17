# CreditClock Claude Implementation Plan (Auth + Polling + Widget + Menu Bar)

## 0) 목표
CreditClock를 macOS 전용 유틸리티로 확장한다.
핵심 요구사항은 아래 4가지다.

1. AI 서비스별 인증을 지원한다. OAuth 가능 서비스는 OAuth 우선, 불가 시 API Key 입력.
2. 사용량/리필 정보를 주기적으로 polling해서 앱/위젯에 반영한다.
3. 위젯에서 서비스별 `현재 사용량(선형 progress)` + `리필까지 남은 시간(원형 loader)`를 표시한다.
4. macOS 상단 메뉴바(Menu Bar)에서 클릭해 현재 상태를 확인할 수 있게 한다.

## 1) 인증 전략 (서비스별 정책)
기준일: 2026-02-17

| 서비스 | 1차 인증 방식 | OAuth 지원 여부 | 비고 |
|---|---|---|---|
| OpenAI API | API Key / Admin Key | 직접 API OAuth 문서 없음 | Usage/Costs 조회는 조직 권한 키(예: admin key) 필요 |
| Anthropic API | API Key / Admin API Key | 직접 API OAuth 문서 없음 | Usage & Cost Admin API는 Admin key 필요 |
| Gemini API (AI Studio) | API Key | 지원(선택) | 기본은 API key, 필요 시 OAuth quickstart 가능 |

구현 원칙:
- `OAuth available -> OAuth 기본 선택`, 단 OpenAI/Anthropic은 현재 직접 API 기준 API Key 방식으로 시작.
- Gemini는 `API Key`와 `OAuth`를 모두 옵션으로 제공.
- 인증 정보 저장은 Keychain 사용(토큰/키 모두 평문 저장 금지).

## 2) 데이터 모델 확장
기존 `ServiceSnapshot` 중심 구조를 아래로 확장한다.

### 2.1 ProviderAccount
- `id`, `provider` (`openai`, `anthropic`, `gemini`)
- `authMethod` (`oauth`, `apiKey`)
- `credentialsRef` (Keychain 참조 키)
- `isEnabled`
- `pollIntervalSeconds`

### 2.2 UsageWindow
- `windowStart`, `windowEnd`
- `used`, `limit`
- `refillAt`
- `remaining = max(limit - used, 0)`
- `timeRemaining = max(refillAt - now, 0)`

### 2.3 FetchHealth
- `lastSuccessAt`, `lastFailureAt`, `lastErrorMessage`
- `consecutiveFailures`
- `latencyMs`

## 3) 아키텍처 변경

### 3.1 Auth Layer
- `AuthMethod` enum: `.oauth`, `.apiKey`
- `CredentialStore` 프로토콜 + `KeychainCredentialStore` 구현
- `OAuthCoordinator`:
  - macOS `ASWebAuthenticationSession` 기반
  - PKCE + refresh token 보관
  - 우선 적용 대상: Gemini

### 3.2 Provider Layer
- `ServiceProvider`를 `UsageProvider`/`AuthProvider` 역할로 분리
- Provider별 Adapter:
  - `OpenAIProviderAdapter`
  - `AnthropicProviderAdapter`
  - `GeminiProviderAdapter`
- 각 Adapter는 공통 출력 `ServiceSnapshot`으로 매핑

### 3.3 Polling Layer
- `PollingScheduler` 신설:
  - 기본 5분 주기
  - 실패 시 exponential backoff (예: 1m → 2m → 4m, max 30m)
  - 성공 시 기본 주기로 복귀
- 앱 활성/비활성 상태에 따라 polling 강도 조절
- polling 결과 저장 후 `WidgetCenter.reloadAllTimelines()` 호출

## 4) UI 구현 계획 (macOS 앱)

### 4.1 계정/인증 설정 화면
- `Provider Settings` 화면 추가
- 서비스 카드별:
  - 인증 방식 선택 (가능한 방식만 표시)
  - API Key 입력 or OAuth 연결 버튼
  - 연결 테스트 버튼
  - polling interval 설정

### 4.2 대시보드
- 기존 리스트를 확장해 아래 표시:
  - 사용량 progress
  - 남은 크레딧
  - 리필까지 남은 시간
  - 마지막 동기화 시각
  - 오류 상태 배지

## 5) Widget 구현 계획

### 5.1 표시 요구사항
각 서비스 row에 다음 2개를 함께 표시:

1. `LinearProgressView`: 사용량(used/limit)
2. `CircularCountdownRing`: 리필까지 남은 시간 비율

### 5.2 원형 loader 계산
- `ringProgress = elapsedSinceWindowStart / totalWindowDuration`
- 또는 `remainingRatio = timeRemaining / totalWindowDuration`
- 데이터가 불완전하면 fallback으로 텍스트만 표시

### 5.3 Widget family
- `systemMedium`: 상위 3~4개 서비스
- `systemLarge`: 더 많은 서비스 + 상태 텍스트 보강

## 6) Menu Bar (Top Nav) 구현 계획

### 6.1 Scene 추가
- `CreditClockApp`에 `MenuBarExtra` 추가
- 메뉴바 아이콘 클릭 시:
  - 서비스 요약 리스트
  - 즉시 새로고침 버튼
  - 메인 앱 열기 버튼

### 6.2 메뉴바 콘텐츠
- 서비스명
- 남은량
- 리필 카운트다운
- 상태 점(색상)

## 7) Claude 작업 순서 (실행 단위)

### Phase 1: Foundation
1. 모델 확장(`ProviderAccount`, `FetchHealth`, `UsageWindow`)
2. Keychain 저장소 + CredentialStore 구현
3. PollingScheduler 도입

### Phase 2: Auth UI + Provider Config
1. Provider Settings 화면 추가
2. API Key 입력 플로우 연결
3. Gemini OAuth 플로우(1차) 연결

### Phase 3: Provider Integration
1. OpenAI usage/cost adapter
2. Anthropic usage/cost adapter
3. Gemini adapter(API key 우선, OAuth 병행)

### Phase 4: Widget + Menu Bar
1. 위젯 row에 progress + circular ring 도입
2. MenuBarExtra scene 추가
3. 앱/위젯/메뉴바 동기화 확인

### Phase 5: Hardening
1. 재시도/백오프/오류 배지 강화
2. 테스트 추가(모델 매핑/시간 계산/필터링)
3. 민감정보/로그 마스킹 점검

## 8) 수용 기준 (Acceptance Criteria)
- 사용자는 서비스별로 인증 방식을 설정할 수 있다.
- polling 주기마다 데이터가 갱신되고, 실패 시 백오프가 동작한다.
- 위젯에 서비스별 사용량 progress + 리필 원형 loader가 보인다.
- 메뉴바 클릭으로 핵심 상태를 즉시 확인할 수 있다.
- API 키/토큰은 Keychain에 저장된다.

## 9) 리스크 / 결정 필요사항
- OpenAI/Anthropic은 직접 API OAuth 흐름이 아닌 API Key 중심으로 시작한다.
- 서비스별 "limit/refill" 정의가 다르므로 공통 정규화 규칙이 필요하다.
- 초기에는 3개 서비스(OpenAI, Anthropic, Gemini) 우선 구현 후 확장한다.

## 10) 참고 문서 (공식)
- OpenAI Quickstart (API key): https://platform.openai.com/docs/quickstart/overview
- OpenAI Usage/Costs API: https://platform.openai.com/docs/api-reference/usage/costs
- Anthropic API Overview (x-api-key): https://docs.anthropic.com/en/api/getting-started
- Anthropic Usage & Cost Admin API: https://docs.anthropic.com/en/api/usage-cost-api
- Gemini API Quickstart (API key): https://ai.google.dev/gemini-api/docs/quickstart
- Gemini API Reference (x-goog-api-key): https://ai.google.dev/api
- Gemini OAuth Quickstart: https://ai.google.dev/gemini-api/docs/oauth

## 11) 관련 개발 플랜 문서
- Codex 사용량(5h/1week) 위젯 연동 플랜: `docs/codex-usage-widget-plan.md`
