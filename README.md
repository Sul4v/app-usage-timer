# Capsule

A minimal app that makes you conscious of the time you spend in other apps.
Pick the apps to track, set a daily limit for each, and a small **capsule
timer** follows you into those apps — green while you're well under your
limit, drifting through yellow to red as you approach and pass it. Inside
Capsule you get Screen-Time-style stats (sessions, opens, daily/weekly
trends, limit adherence), accounts, and cross-device sync.

| | iOS | Android |
|---|---|---|
| UI | SwiftUI (iOS 17+) | Jetpack Compose (Android 8+) |
| Usage tracking | Screen Time API (`FamilyControls` + `DeviceActivity` monitor extension) | `UsageStatsManager` polled by a foreground service |
| The capsule | **Live Activity in the Dynamic Island** (compact: colored dot + minutes) + Lock Screen banner | **Floating, draggable overlay** (`SYSTEM_ALERT_WINDOW`) drawn over the tracked app |
| Sessions / opens | Approximated from per-minute threshold events (Apple never exposes raw timelines) | Exact, from activity resume/pause events |
| Over-limit action | Notification + optional app **shield** (blocks the app) | Notification |
| Storage | JSON day-files in the App Group container | JSON day-files in app storage |
| Sync | Hand-rolled Supabase REST client (no SDK dependency) | Same |

## Quick start

### Prerequisites

- macOS with Xcode 15+ (for iOS) and Android Studio / the Android SDK (for Android)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A JDK for Gradle — Android Studio ships one; point `JAVA_HOME` at it if your
  system Java is newer than what Gradle 8.14 supports:
  `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`

### iOS

```bash
cd ios
xcodegen generate
open Capsule.xcodeproj
```

In Xcode: pick the **Capsule** scheme, pick a simulator (or your device),
press `⌘R`. First run may prompt you to pick a development team — the free
personal team Xcode offers is enough for the simulator.

**To test it:** the simulator can't grant real Screen Time access, so the
app boots straight into demo mode with 3 sample apps and 14 days of seeded
usage — explore onboarding, Today, and Stats immediately. To see the actual
Dynamic Island capsule, run on a real device, allow Screen Time access when
onboarding asks, pick a real app to track, and open it — or fake it from the
simulator/device via **Settings ▸ Developer ▸ Preview capsule (Live
Activity)** in the app (Debug builds only), then switch to another app to see
it float in the island.

### Android

```bash
cd android
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Or just open `android/` in Android Studio and hit Run.

**To test it:** on first launch, onboarding walks you through the two
required permissions (usage access, display-over-other-apps) via
system Settings — grant both, pick an app to track, open it, and the
draggable capsule appears over it. To speed through permission grants on an
emulator instead of tapping through Settings:

```bash
adb shell appops set com.sodhera.capsule GET_USAGE_STATS allow
adb shell appops set com.sodhera.capsule SYSTEM_ALERT_WINDOW allow
adb shell pm grant com.sodhera.capsule android.permission.POST_NOTIFICATIONS
```

## Why these choices

**iOS doesn't allow floating overlays over other apps, ever.** The sanctioned
equivalent is exactly what you suggested: something in the Dynamic Island.
Capsule keeps one Live Activity alive; the `DeviceActivity` monitor extension
updates it each time the system reports another minute of use in a tracked
app. On devices without the island it appears on the Lock Screen / notch
banner area.

**iOS also never tells an app which apps the user picked or their raw usage.**
The `FamilyActivityPicker` returns opaque tokens — we can *render* the real
name/icon but can't read them. So each tracked app carries a user-editable
nickname ("App 1" until renamed) used for stats and sync, and per-minute
usage is reconstructed from threshold-event callbacks. This is the same
compromise every Screen-Time-based app (Opal, one sec, …) lives with.

**Android just lets us do the thing.** A foreground service watches the
foreground app once a second while the screen is on, shows a real draggable
overlay capsule with a per-second timer, and records exact sessions.

**Sync is Supabase** (email auth + Postgres with row-level security) through
a ~150-line REST client per platform instead of the heavyweight SDKs. Both
apps are **local-first**: without a configured server they run fully offline
in "demo mode", and the sign-in screen offers "Continue without an account".
What syncs: app list, nicknames, limits (both ways, last-write-wins) and
daily usage/sessions (up). iOS app tokens can't leave the device, so a new
iPhone re-picks apps once and history re-attaches by app id.

## Repo layout

```
ios/        SwiftUI app — XcodeGen project (app + monitor extension + widgets)
android/    Kotlin/Compose app — Gradle project
supabase/   schema.sql — tables + RLS for auth'd sync
```

## Platform notes

**iOS.** On a real device you need: a team set on all three targets, the
**Family Controls** capability (development works with any Apple ID;
distribution requires [applying to Apple](https://developer.apple.com/contact/request/family-controls-distribution)),
App Groups (`group.com.sodhera.capsule`), and Live Activities enabled.
Threshold-event granularity is 1 minute, so the island capsule updates once
per minute of real usage; registered thresholds go fine-grained (every
minute) up to the limit and coarser (every 5 min) to 2× the limit — keep
tracked apps to ~8 or fewer.

**Android.** Onboarding deep-links into system Settings for the two special
permissions (usage access, display-over-other-apps) since Android won't grant
them from an in-app dialog. The tracking service restarts on boot.

## Enabling sync

1. Create a Supabase project, enable email auth, run `supabase/schema.sql`.
2. iOS: set `SupabaseURL` / `SupabaseAnonKey` in `ios/project.yml` (Info
   properties) and regenerate; Android: set `SUPABASE_URL` /
   `SUPABASE_ANON_KEY` in `android/app/build.gradle.kts`.

## Design

Calm and restrained: system backgrounds, neutral text, generous whitespace,
rounded cards. The only saturated color anywhere is the capsule's state ramp
(green → yellow → orange → red, same stops on both platforms and in every
progress bar and chart).

## Known limitations / next steps

- iOS sessions and open counts are approximations (3-minute gap heuristic
  over minute events); Apple offers no exact API. A `DeviceActivityReport`
  extension could add Apple-rendered exact stats (view-only, not syncable).
- Live Activity updates from the monitor extension are reliable on iOS 17+,
  but Apple may throttle very frequent updates; milestone notifications are
  the guaranteed fallback.
- Android battery: polling only runs while the screen is on; a JobScheduler
  fallback for OEMs that kill foreground services would harden it.
- Auth is email/password; Sign in with Apple / Google are the obvious adds.
