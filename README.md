# MacSafe

[English](README.md) | [简体中文](README.zh-CN.md)

MacSafe is a native macOS menubar application that monitors your device's surrounding environment when you're away, helping protect it from unauthorized access.

## Features

- **Automatic activation** when your screen locks, screensaver starts, or after a configurable idle timeout
- **Camera monitoring** — detects motion and approaching faces at 1fps with minimal CPU impact
- **Audio monitoring** — detects sudden loud sounds near your device
- **Video evidence** — saves a rolling 10-second pre-roll + 5-second post-roll clip to `~/Movies/MacSafe/` on every alert
- **Local notifications** — immediate macOS banner alerts with critical sound
- **Mobile push notifications** via [Pushover](https://pushover.net) — get alerted on your phone
- **Alert history** — browse recent alerts with timestamps and video clip links
- **Menubar-only** — no Dock icon, extremely low background resource usage

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- An Apple Developer account (for code signing)

## Getting Started

### Build with Xcode

1. Open `MacSafe.xcodeproj` in Xcode
2. Select the `MacSafe` target
3. Set your Development Team under **Signing & Capabilities**
4. Build and Run (`⌘R`)

### Regenerate project with XcodeGen (optional)

If you modify `project.yml`, regenerate the `.xcodeproj`:

```bash
brew install xcodegen
xcodegen generate
```

## Configuration

Click the shield icon in the menubar → **Settings** to configure:

| Setting | Default | Description |
|---|---|---|
| Motion threshold | 8% | Lower = more sensitive to movement |
| Audio threshold | −30 dBFS | Higher = only very loud sounds trigger alerts |
| Idle timeout | 5 minutes | How long before idle activates monitoring |
| Pre-roll buffer | 10 seconds | Video recorded before the alert trigger |
| Post-roll duration | 5 seconds | Video recorded after the alert trigger |

### Pushover Setup

1. Create an account at [pushover.net](https://pushover.net)
2. Create an application token at [pushover.net/apps/build](https://pushover.net/apps/build)
3. Enter your **User Key** and **API Token** in MacSafe Settings → Mobile Push Notifications

## Architecture

```
MacSafeApp (@main)
  └── AppDelegate (NSStatusItem + NSPopover)
        └── MonitoringCoordinator (central ObservableObject)
              ├── MonitoringStateMachine (actor, pure state transitions)
              ├── ScreenStateMonitor    (DistributedNotificationCenter)
              ├── IdleMonitor           (IOKit HIDIdleTime polling)
              ├── CameraService         (AVFoundation, 1fps)
              │     ├── MotionDetector  (CIFilter frame differencing)
              │     └── FaceDetector    (Vision VNDetectFaceRectanglesRequest)
              ├── VideoRecorder         (AVAssetWriter rolling ring buffer)
              ├── AudioMonitor          (AVAudioEngine, Accelerate vDSP)
              └── AlertService          (UNNotification + Pushover + history)
```

### State Machine

```
.idle ──[lock/screensaver/idle/manual]──► .monitoring
.monitoring ──[motion/face/audio]──────► .alerting
.alerting ──[acknowledged/timeout]─────► .monitoring
any ──[unlock/user activity]───────────► .idle
any ──[manual disable]─────────────────► .suspended
```

## Frameworks Used

- **AVFoundation** — camera capture and video recording
- **Vision** — face detection
- **CoreImage** — GPU-accelerated frame differencing
- **UserNotifications** — local push notifications
- **IOKit** — system idle time detection
- **Accelerate** — fast audio RMS computation
- **Combine** — reactive event pipeline
- **ServiceManagement** — launch at login (macOS 13+)

## Privacy

MacSafe processes all camera and audio data locally on your device. No data is ever uploaded except optional Pushover notifications (which contain only alert text, no images or audio).

Video clips are saved locally to `~/Movies/MacSafe/` and are never shared automatically.
