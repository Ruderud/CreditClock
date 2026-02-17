[English](./README.md) | [한국어](./README.ko.md)

<h1 align="center">CreditClock</h1>

<p align="center">
  Track AI subscription usage, refill timers, and plan status in one place.
  <br />
  macOS app + desktop widget for Codex, Claude, and Gemini.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-111111?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-0A84FF?style=flat-square" alt="SwiftUI + WidgetKit" />
  <img src="https://img.shields.io/badge/License-MIT-2563EB?style=flat-square" alt="MIT License" />
</p>

## Screenshots

<p align="center">
  <img src="./docs/images/creditclock-app-main.png" width="620" alt="CreditClock main desktop app" />
</p>

<p align="center">
  <img src="./docs/images/creditclock-widget-large.png" width="330" alt="CreditClock widget" />
</p>

<p align="center">
  <img src="./docs/images/creditclock-showcase.png" width="470" alt="CreditClock showcase" />
</p>

## What You Get

- Unified usage tracking across providers in one dashboard.
- Refill countdowns for multiple quota windows (for example, `5h`, `1w`, daily).
- Subscription state indicators (`Active`, `Trial`, `Paused`, `Expired`).
- WidgetKit support (`systemMedium`, `systemLarge`) with shared app data.
- Menu bar quick view with one-click refresh.

## Supported Providers

| Provider | Data Source | Setup in App |
|---|---|---|
| Codex (`OpenAI`) | Local `~/.codex` usage cache/session logs, with JWT fallback | Grant local folder access + click `Connect` |
| Claude (`Anthropic`) | Local `~/.claude/plugins/oh-my-claudecode/.usage-cache.json` or Anthropic OAuth usage endpoint | Grant local folder access + click `Connect` |
| Gemini | Local `~/.gemini/oauth_creds.json` (CLI OAuth quota) or Gemini API key fallback | Grant local folder access for CLI OAuth, or save API key + enable |

## Installation (macOS)

Prerequisites:

- macOS 14+
- Xcode 15+
- Homebrew + `xcodegen`

```bash
brew install xcodegen
xcodegen generate
open CreditClock.xcodeproj
```

In Xcode, run the `CreditClock` scheme.

## How To Use

1. Launch `CreditClock`.
2. Open `Settings` from the gear button.
3. In `Local Data Access`, click `Grant Codex + Claude + Gemini Together (Recommended)`.
4. Select your home folder (`~`) once.
5. Configure providers:
   - `OpenAI`, `Anthropic`: click `Connect`.
   - `Gemini`: use local CLI OAuth (`~/.gemini/oauth_creds.json`) or save an API key.
6. Click `Test` per provider (optional but recommended).
7. Close settings and click `Refresh` in the main window.
8. Add the CreditClock widget to your desktop.

> Installation note (as of February 17, 2026): CreditClock is not code-signed yet, so install/run it directly from Xcode (`CreditClock` scheme).

## Troubleshooting

- `No providers configured`: open `Settings` and connect at least one provider.
- Widget shows `No synced data`: refresh once in app, then remove/re-add the widget.
- Folder access errors: re-open `Settings` and re-grant local access.

## Privacy

- Local provider data is read from your machine (`~/.codex`, `~/.claude`, `~/.gemini`).
- API keys are stored in macOS Keychain.
- Snapshot sync between app and widget uses App Group plus local fallback paths.

<details>
<summary><strong>Development</strong></summary>

### Tech Stack

- Swift 5.10
- SwiftUI (macOS app)
- WidgetKit (desktop widget)
- XcodeGen project generation (`project.yml`)

### Project Structure

```text
CreditClock/
├── CreditClockApp/                 # macOS app (main window + settings + menu bar)
├── CreditClockWidget/              # WidgetKit extension
├── Shared/
│   ├── Models/                     # Snapshot/state models
│   ├── Persistence/                # App Group, fallback storage, keychain wrappers
│   ├── Providers/                  # OpenAI/Anthropic/Gemini adapters
│   └── Store/                      # Refresh orchestration + polling
├── scripts/                        # Type-check, version bump, release helpers
└── project.yml                     # XcodeGen source of truth
```

### Local Development

```bash
# Generate Xcode project
xcodegen generate

# Run Swift type checks used by pre-commit
./scripts/typecheck.sh
```

### Pre-commit Automation

`.husky/pre-commit` runs:

1. `scripts/bump-version.sh` (patch bump in `VERSION` + regenerate `Shared/Generated/BuildVersion.generated.swift`)
2. `scripts/typecheck.sh`

Enable hooks in a fresh clone:

```bash
git config core.hooksPath .husky
```

If needed, skip version bump once:

```bash
CREDITCLOCK_SKIP_VERSION_BUMP=1 git commit -m "your message"
```

### Build / Release Scripts

```bash
# Build unsigned Release app and zip artifact
./scripts/build-release-artifact.sh

# Build and upload/update GitHub release tag main-latest (requires gh auth)
./scripts/upload-main-release.sh
```

### Data Sync Notes

- Primary sync: App Group container (`group.com.creditclock.shared`).
- Fallback sync: `~/.creditclock/snapshots.json`.
- Widget bridge fallback: `~/Library/Containers/com.creditclock.app.widget/Data/Documents/snapshots.json`.

</details>

## License

MIT License. See [LICENSE](./LICENSE).
