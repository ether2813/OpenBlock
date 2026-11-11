# OpenBlock

OpenBlock is the iPhone version of **PersonalBlocker**, a private, offline app blocker. It's a native SwiftUI app built on Apple's Screen Time frameworks:

- **FamilyControls** picks apps privately.
- **ManagedSettings** blocks apps and websites.
- **DeviceActivity** runs schedules and usage limits.

There are no accounts, analytics, ads or network calls, and everything stays on the device.

## Features

| | |
| --- | --- |
| **Schedules** | Blocklist or allowlist. Triggered by time of day (overnight windows included) or a daily usage limit, on chosen days. Includes duplicate, pause and swipe-to-delete. |
| **App limits** | Per-app or per-category daily limits, or "always block". |
| **Websites** | Always-blocked domains plus per-schedule domains, blocked in Safari and in-app browsers. |
| **Adult content** | Apple's built-in adult website filter, behind a single switch. |
| **Strict Mode** | Five unlock methods: timer, follow schedules, cooldown, charger and PIN. While it's on, it can lock in-app edits, stop apps being deleted or installed, and keep the date and time on automatic. |
| **Block screen** | A custom shield that shows the reason ("Focus time · until 5:00 PM"), your own message and your accent color. |
| **Insights** | Screen time for today, the week or two weeks, with a daily chart and the most used apps. You can hide chosen apps. |
| **Notifications** | A quiet notification when a schedule starts or a limit is reached. |
| **Appearance** | Sky, Violet and Red accents with System, Light and Dark modes. |
| **Backup** | Export and import as JSON. A live Strict Mode session is never exported. |

### What's different from Android

iOS doesn't let one app watch or cover another, so OpenBlock uses Screen Time instead. iOS shows the block screen itself, which makes blocking reliable and light on the battery. Some Android features have no iOS equivalent:

- Launch-count limits
- Keyword blocking inside web pages
- Silencing notifications from blocked apps
- Rejecting calls
- Locking Recent Apps, split screen and Settings
- Device Owner mode

The app explains these differences under **More → How blocking works on iPhone**.

## Project layout

```
ios/
  project.yml                      XcodeGen spec (the .xcodeproj is generated)
  App/                             SwiftUI app: Blocking, Strict, Insights, More tabs
  Shared/                          Models, policy engine, enforcement (compiled into every target)
  ReportShared/                    Report context shared by the app and the report extension
  Extensions/Monitor/              DeviceActivityMonitor: applies blocks at window starts, ends and thresholds
  Extensions/ShieldConfiguration/  Custom block screen
  Extensions/ShieldAction/         Block screen buttons
  Extensions/Report/               DeviceActivityReport: the Insights view
```

## Getting the IPA

Every push that changes `ios/` runs **.github/workflows/ios.yml** on a macOS runner:

1. It generates the Xcode project with XcodeGen.
2. It builds the app for iOS devices.
3. It ad-hoc signs each binary with its entitlements.
4. It uploads `OpenBlock.ipa` as the **OpenBlock-ipa** artifact on the run page.

Pushing a tag such as `v1.0` also attaches the IPA to a GitHub Release. You can start a build by hand from **Actions → iOS build → Run workflow**.

The IPA is unsigned, so install it with a sideloading tool such as **Sideloadly** or **AltStore**. That tool re-signs it with your Apple ID.

> **The Screen Time entitlement**
>
> Blocking depends on the `com.apple.developer.family-controls` entitlement. Apple grants the development version of it to paid Apple Developer Program accounts. A free Apple ID may not be able to sign it, in which case the app installs but can't get Screen Time access. Distributing through TestFlight or the App Store also needs Apple to approve the distribution entitlement for the bundle IDs.

## Building locally

On a Mac with Xcode 15 or later:

```bash
brew install xcodegen
```

```bash
cd ios && xcodegen generate && open OpenBlock.xcodeproj
```

Set your team on all five targets. If `com.openblock.app` is taken under your team, change the bundle IDs and App Group in `project.yml` and `Shared/SharedStore.swift`. Then run on a real iPhone; Screen Time APIs don't work in the Simulator.
