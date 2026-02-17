# CreditClock Stitch Design Brief (macOS-first, HIG-aligned)

## Generated Stitch Assets
- Project: `projects/2942324076236035754`
- Screen: `projects/2942324076236035754/screens/425e7eb699884a9d815399d6d56bf610`
- Alternate Screen: `projects/2942324076236035754/screens/e53e38e6bb8541e3ab995323a9590df6`
- Screenshot URL:
  - `https://lh3.googleusercontent.com/aida/AOfcidVBQUvccCvj8uFM3Q0j7-dLC3aPuL4lPjNacDcJ7Ve-tP9XqkLER7pNtiab3iub7qaAV2R5ozh5WaaRLt9W6Q2-E4bRWDzlkWQNvZUcZkWII_CPqxXLWdEQiVRvgnUSAOGxcvXRphuZ9xzcJaFxD5Lw1y1bnjXVr8yYn8fYRGhZkzV8hBjOukvyYoQ4wMS2Cx2z6rzN5ZSICM5-RSt1F2n5SfWGQ4gLVj0N6ih99KLG7hdW0tWlv-pZd8E`
- Notes:
  - Stitch generated the content using a mobile canvas (`width: 780`) even when `deviceType` was set to desktop.
  - The composition still reflects the requested macOS information architecture (sidebar + toolbar + metrics + provider cards).
  - Use this as structural reference and implement with true macOS layout constraints in SwiftUI.

## Design Direction
- Platform: macOS app first (desktop only as primary target)
- Guideline baseline: Apple Human Interface Guidelines (desktop clarity, hierarchy, spacing, legible text, clear affordances)
- Visual tone: dark premium control panel
- Style tokens inspired by TempoTune patterns:
  - Background: `#0A1112`
  - Surface: `#1A2E2E`
  - Accent: `#0DF2F2`
  - Supporting text: slate neutral scale
- UI language: subtle glass layers, restrained glow, tabular numeric emphasis for usage counters

## Screen A: macOS Dashboard (Required)
Prompt for Stitch:

"Design a macOS desktop dashboard for CreditClock. The app tracks AI service usage, refill times, and subscription health across OpenAI, Claude, Gemini, and other providers. Use Apple desktop HIG style principles for clarity and control hierarchy. Visual style: dark premium glass UI with deep charcoal background (#0A1112), layered surface cards (#1A2E2E), cyan accent (#0DF2F2), soft subtle glow, and a faint grid texture.

Layout requirements:
- Top toolbar/header: app name, last sync timestamp, Refresh button, Add Provider button.
- Left sidebar filter: All, Active, Trial, Expired, Paused.
- Main content: summary insight strip at top (total remaining credits, next refill event, warning provider count).
- Provider card grid in main area (2-3 columns depending on width).
- Each provider card includes:
  - Provider icon and name
  - Subscription status pill
  - Used vs limit
  - Progress bar
  - Remaining credits (high emphasis)
  - Refill countdown / next reset time
  - Last successful fetch time
  - Inline warning state for near-limit providers
- Ensure typography hierarchy is explicit and numbers use tabular alignment style.
- Keep spacing and component composition implementation-ready for SwiftUI."

## Screen B: Provider Detail (Required)
Prompt for Stitch:

"Design a macOS provider detail screen for CreditClock. This screen opens when a provider card is selected. Keep the same dark HIG-aligned visual style.

Include:
- Header with provider name + status + manual refresh action.
- Left section: current cycle usage gauge, used/limit, remaining credits, next refill timestamp.
- Right section: recent usage trend chart (7d/30d segmented control).
- Lower section: API health and fetch diagnostics (last success, last failure, response time, retry count).
- Alert rules panel: thresholds for warning/critical states.
- Footer actions: Save settings, Test connection.
- The screen should feel native to a professional macOS utility app."

## Screen C: Widget Preview Board (Required)
Prompt for Stitch:

"Design a macOS widget preview board for CreditClock. Show how data appears in medium and large widget sizes with consistent style.

Include:
- Side-by-side widget previews: medium and large.
- Medium widget: top 3-4 providers and remaining credits.
- Large widget: providers, refill timing, and warning badges.
- Small explanatory panel on the right: what data appears in widget vs full app.
- Keep design aligned with macOS desktop visual language and CreditClock dark theme."

## Optional Screen D: Mobile Companion (Optional)
Prompt for Stitch:

"Create an optional mobile companion view for CreditClock (not primary target). Keep visual consistency with macOS design. Use compact card stack with provider usage and refill countdown. Prioritize readability and one-hand scanning."

## HIG Alignment Checklist
- Clear hierarchy: primary values visually dominant
- Control clarity: buttons and segmented controls have obvious states
- Legibility: avoid tiny text; body text >= 12pt equivalent
- Reduced visual noise: glow effects are subtle, not distracting
- Consistency: status colors and semantic meanings fixed across screens
- Desktop ergonomics: keyboard-focus friendly spacing and section grouping
