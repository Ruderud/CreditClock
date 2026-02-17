[English](./README.md) | [Korean](./README.ko.md)

# CreditClock

CreditClock is an MVP macOS app + widget that lets you track usage, refill time, and subscription status across multiple AI services in one place.

## Included in this MVP
- macOS SwiftUI dashboard
- WidgetKit widget (`systemMedium`, `systemLarge`)
- Shared data model (`ServiceSnapshot`)
- App Group-based data sharing between app and widget
- Provider abstraction + mock providers
- Base HTTP JSON provider scaffold for real API integration

## Generate and Run
This repository is configured with `xcodegen`.

1. Install `xcodegen` if needed: `brew install xcodegen`
2. From the project root, run: `xcodegen generate`
3. Open the generated `CreditClock.xcodeproj` in Xcode
4. Run the `CreditClock` scheme

## Project Structure
- `project.yml`: XcodeGen project configuration
- `CreditClockApp/`: macOS app UI
- `CreditClockWidget/`: Widget extension
- `Shared/`: shared models, providers, and persistence for app/widget

## How to Integrate Real APIs
The current setup uses mock providers. Replace them with real service integrations using this flow:

1. Remove mock providers from `ProviderCatalog.defaultProviders()` in `Shared/Providers/MockProviders.swift`
2. Create per-service providers using `Shared/Providers/JSONEndpointProvider.swift`
3. Map each service response into `ServiceSnapshot`
4. Store sensitive data (API keys/tokens) in Keychain or another secure store

Conceptual example:
```swift
var req = URLRequest(url: URL(string: "https://api.example.com/usage")!)
req.addValue("Bearer <token>", forHTTPHeaderField: "Authorization")

let provider = JSONEndpointProvider(serviceId: "example", request: req) { data in
    // decode data and map to ServiceSnapshot
}
```

## Recommended Next Steps
- Finalize auth and endpoints per service
- Model refill rules per provider (fixed time, billing-cycle reset, rolling window)
- Add robust caching/retry/backoff policies
- Decide whether to add a menu bar experience
