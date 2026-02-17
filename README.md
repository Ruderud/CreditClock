[English](./README.md) | [Korean](./README.ko.md)

<h1 align="center">CreditClock</h1>

<p align="center">
  One dashboard for AI plan usage, refill times, and subscription health.
  <br />
  Built for macOS with SwiftUI + WidgetKit.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2011%2B-111111?style=flat-square&logo=apple&logoColor=white" alt="macOS 11+" />
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-0A84FF?style=flat-square" alt="SwiftUI + WidgetKit" />
  <img src="https://img.shields.io/badge/Status-MVP-5E5CE6?style=flat-square" alt="MVP" />
  <img src="https://img.shields.io/badge/Open%20Source-Yes-22C55E?style=flat-square" alt="Open Source" />
  <img src="https://img.shields.io/badge/License-MIT-2563EB?style=flat-square" alt="MIT License" />
</p>

## Why CreditClock

Most AI subscriptions expose usage in different places and different formats.
CreditClock brings them into one place so you can quickly answer:

- How much quota is left right now?
- When does each plan refill?
- Is each subscription active, trial, paused, or expired?

## Features

- **Unified Usage View**: Track usage and remaining credits across providers in one list.
- **Refill Countdown**: See refill/reset timing per service at a glance.
- **Subscription Health**: Monitor plan state (`active`, `trial`, `paused`, `expired`).
- **macOS Widget**: View the same shared data directly from your desktop widget.
- **App Group Data Sharing**: App and widget stay synced through shared persistence.
- **Provider Abstraction**: Plug in real API providers without changing UI layers.

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.10 |
| App UI | SwiftUI (macOS) |
| Widget | WidgetKit |
| Data Sharing | App Groups + `UserDefaults(suiteName:)` |
| Project Generator | XcodeGen |

## Architecture

```text
CreditClock/
├── CreditClockApp/                 # macOS SwiftUI app
├── CreditClockWidget/              # WidgetKit extension
├── Shared/
│   ├── Models/                     # ServiceSnapshot, states
│   ├── Persistence/                # App Group storage
│   ├── Providers/                  # Provider protocol + implementations
│   └── Store/                      # App state + refresh flow
└── project.yml                     # XcodeGen project definition
```

Core design choices:

- Keep provider logic isolated behind `ServiceProvider`.
- Keep app and widget in sync using a shared snapshot store.
- Keep UI independent from API details via mapped `ServiceSnapshot` data.

## Quick Start

```bash
# 1) Install xcodegen if you don't have it
brew install xcodegen

# 2) Generate the Xcode project
xcodegen generate

# 3) Open in Xcode
open CreditClock.xcodeproj
```

Then run the `CreditClock` scheme.

## Commit Automation (Husky-Style)

CreditClock uses a Git `pre-commit` hook (via `.husky/`) to enforce baseline quality and version metadata:

- Runs Swift type-checks for shared/app/widget sources.
- Auto-bumps patch version in `VERSION` on each commit.
- Regenerates and stages `/Shared/Generated/BuildVersion.generated.swift`.

If hooks are not active in your local clone, run:

```bash
git config core.hooksPath .husky
```

## Real API Integration

Current providers are mock-based for MVP development.
To connect real services (OpenAI, Anthropic, Gemini, etc.):

1. Replace `ProviderCatalog.defaultProviders()` in `Shared/Providers/MockProviders.swift`.
2. Create service-specific providers with `Shared/Providers/JSONEndpointProvider.swift`.
3. Map each API response into `ServiceSnapshot`.
4. Store API tokens in Keychain (recommended), not in source.

Conceptual example:

```swift
var request = URLRequest(url: URL(string: "https://api.example.com/usage")!)
request.addValue("Bearer <token>", forHTTPHeaderField: "Authorization")

let provider = JSONEndpointProvider(serviceId: "example", request: request) { data in
    // Decode response and map into ServiceSnapshot
}
```

## Roadmap

- [ ] Add first-party providers for OpenAI / Anthropic / Gemini
- [ ] Add per-service refill policy modeling (fixed reset, billing cycle, rolling window)
- [ ] Add retry/backoff and stale-cache policy for failures
- [ ] Add settings UI for account tokens and provider enable/disable
- [ ] Evaluate menu bar mode in addition to widget

## Open Source

CreditClock is an **open-source program**. Contributions, feedback, and issue reports are welcome.

## License

MIT License. See [LICENSE](./LICENSE).
