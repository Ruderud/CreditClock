# CreditClock Codex Usage Widget Development Plan

기준일: 2026-02-17

## 0) 목표
CreditClock에서 Codex 사용량 제한(`5h`, `1week`)을 안정적으로 수집해 앱/위젯에 표시한다.

핵심 출력:
- 5시간 윈도우: 사용률, 남은 비율, 리셋 시각
- 1주 윈도우: 사용률, 남은 비율, 리셋 시각

## 1) 데이터 소스 전략

### 1.1 단기(프로토타입): 로컬 세션 로그 파싱
대상 경로:
- `~/.codex/sessions/YYYY/MM/DD/*.jsonl`

추출 규칙:
- `payload.rate_limits.limit_id == "codex"` 필터
- `primary` = 5시간, `secondary` = 1주
- 최신 `timestamp` 레코드 1개 사용

장점:
- 구현이 빠르고 즉시 동작

리스크:
- 내부 로그 스키마 변경 가능성
- 샌드박스 앱에서 파일 접근 권한 이슈 가능

### 1.2 중장기(권장): Codex App Server JSON-RPC
공식 메서드:
- `account/rateLimits/read`

필드:
- `rateLimits.primary.usedPercent`
- `rateLimits.primary.windowDurationMins`
- `rateLimits.primary.resetsAt`
- `rateLimits.secondary.*`

장점:
- 공식 인터페이스 기반
- 로그 포맷 변경 리스크 감소

## 2) 구현 아키텍처

### 2.1 도메인 모델
`CodexUsageSnapshot`:
- `fetchedAt`
- `fiveHourUsedPercent`
- `fiveHourRemainingPercent`
- `fiveHourResetsAt`
- `weeklyUsedPercent`
- `weeklyRemainingPercent`
- `weeklyResetsAt`
- `source` (`sessionLog`, `appServer`)

### 2.2 수집 계층
`CodexUsageProvider` 프로토콜:
- `fetchUsage() async throws -> CodexUsageSnapshot`

구현체:
- `CodexSessionLogUsageProvider` (Phase 1)
- `CodexAppServerUsageProvider` (Phase 2)

### 2.3 저장/공유 계층
기존 App Group 저장소에 키 추가:
- `codex.usage.snapshot.v1`
- `codex.usage.lastError`
- `codex.usage.lastSuccessAt`

앱은 주기적으로 갱신 후 저장, 위젯은 저장값만 렌더링.

## 3) 폴링/갱신 정책
- 기본 갱신 주기: 5분
- 실패 시 백오프: 1m -> 2m -> 4m (max 30m)
- 성공 시 기본 주기로 복귀
- 수동 새로고침(앱/메뉴바) 제공
- 저장 성공 후 `WidgetCenter.reloadAllTimelines()`

## 4) 위젯 표시 정책
- 5시간: 선형 Progress + `%`
- 1주: 선형 Progress + `%`
- 리셋 시각: 로컬 타임존 변환 표시
- 데이터 없음: `Not available`
- 오류 상태: 마지막 성공 시각과 함께 경고 배지

## 5) 단계별 실행 계획

### Phase 1: 로그 파싱 기반 MVP
1. `CodexSessionLogUsageProvider` 구현
2. JSONL 최신 레코드 파서 구현
3. 앱/위젯 표시 연결
4. 실패/빈 데이터 fallback 처리

### Phase 2: 공식 JSON-RPC 전환
1. `CodexAppServerUsageProvider` 구현
2. `account/rateLimits/read` 요청/응답 매핑
3. feature flag로 소스 선택 가능하게 구성
4. 기본 소스를 `appServer`로 전환

### Phase 3: 하드닝
1. 캐시 정책/에러 메시지 정제
2. 타임존/포맷 일관성 검증
3. 단위 테스트 추가(파싱/매핑/남은 비율 계산)

## 6) 수용 기준 (Acceptance Criteria)
- 위젯에서 `5h`, `1week` 사용률과 리셋 시각이 보인다.
- 데이터 수집 실패 시 앱이 크래시하지 않고 fallback UI를 보여준다.
- 마지막 성공 스냅샷이 앱/위젯에서 일관되게 표시된다.
- 5분 주기 자동 갱신 + 수동 새로고침이 동작한다.

## 7) 구현 메모 (로그 파싱 커맨드 샘플)
```bash
find ~/.codex/sessions -name '*.jsonl' -type f -print0 \
| xargs -0 rg '"rate_limits"' \
| sed 's#^[^:]*:##' \
| jq -s '
  map(select(.payload.rate_limits.limit_id=="codex"))
  | sort_by(.timestamp)
  | last
  | {
      timestamp,
      primary: .payload.rate_limits.primary,
      secondary: .payload.rate_limits.secondary
    }'
```

## 8) 리스크 / 결정 필요사항
- macOS 샌드박스 앱인 경우 홈 디렉토리 로그 접근 정책 결정 필요
- `secondary == null` 상황에 대한 제품 UI 정책 확정 필요
- `codex app-server`를 앱 내부에서 상시 구동할지, 온디맨드 호출할지 결정 필요

## 9) 참고 문서
- Codex Pricing: https://developers.openai.com/codex/pricing.md
- Codex App Server: https://developers.openai.com/codex/app-server.md

