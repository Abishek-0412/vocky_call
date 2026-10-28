# VockyCall

Short-distance voice calls between Android phones over **WiFi** or **Bluetooth**.
No internet, SIM card or server needed. The phones talk directly to each other.

## Features

- Finds nearby phones automatically, on the same WiFi / hotspot or over Bluetooth
- Works with WiFi only, Bluetooth only, or both at once
- Refresh button, plus automatic refresh every 20 s while no device is found
- One-to-one voice calls, plus group calls over WiFi
- Incoming call screen with Answer / Decline
- Mute, speaker / earpiece switch, and walkie-talkie (push-to-talk) mode
- Bluetooth calls work without pairing the phones first

## Technology Used

| Area | Technology |
|---|---|
| App framework | Flutter (Dart 3.3+), Material 3 dark theme |
| State management & DI | Riverpod (`flutter_riverpod`) |
| Navigation | `go_router` |
| WiFi voice | WebRTC (`flutter_webrtc`): Opus codec, echo cancellation, noise suppression |
| WiFi discovery | UDP multicast (`239.255.0.1:9999`) + subnet broadcast |
| WiFi call signaling | TCP on port `9000`, newline-delimited JSON |
| Bluetooth discovery | `flutter_bluetooth_serial` (device scan) + a short "hello" over RFCOMM so both phones list each other |
| Bluetooth calls | Native Kotlin (`BtCallService.kt`): RFCOMM socket, raw PCM audio (8 kHz / 16-bit / mono) via `AudioRecord` / `AudioTrack` |
| Permissions | `permission_handler` |
| Device name | `device_info_plus` |
| Testing | `flutter_test`, `mocktail` |

### Architecture

The code follows clean architecture:

```
lib/
├── core/           constants, errors, Result type, network utils
├── domain/         entities, value objects, repository interfaces, use cases
├── data/
│   ├── sources/    WiFi (UDP discovery, WebRTC) and Bluetooth sources
│   └── repositories/  discovery, transport (call protocol), audio
├── di/             all Riverpod providers (wiring)
├── presentation/   home and call screens, controllers, widgets, theme
└── sandbox/        fake sources for UI testing without real devices
android/.../MainActivity.kt   multicast lock, audio routing, BT bridge
android/.../BtCallService.kt  native Bluetooth call transport
```

### Call flow

```
Caller                               Callee
  │ ── CALL_INVITE ───────────────────▶ │  (rings)
  │ ◀──────────────────── CALL_ACCEPT ─ │  (user taps Answer)
  │  audio starts on both phones        │
  │    WiFi: SDP offer/answer + ICE → WebRTC audio
  │    BT:   PCM frames on the RFCOMM socket
  │ ── CALL_END ──────────────────────▶ │  (either side hangs up)
```

`CALL_DECLINE` tells the caller the call was declined, or that the other phone is busy.

## How to Use the App

### 1. Install on both phones

Install the app on **two Android phones** (Android 7.0+). Open it on both and
**allow all permissions** it asks for:

- **Location / Nearby devices**: to find other phones
- **Microphone**: to talk

### 2. Choose how to connect

**Over WiFi (best quality, longer range)**

1. Connect both phones to the **same WiFi network**, or turn on the hotspot on
   one phone and connect the other phone to it.
2. Open VockyCall on both. Each phone appears in the other's list with a
   **WiFi** badge within a few seconds.

**Over Bluetooth (no WiFi needed, ~10 m range)**

1. Turn **Bluetooth on** for both phones.
2. On **one** of the phones, tap **Make Visible** (top right) and allow it.
   The phone stays visible for 2 minutes.
3. The other phone finds it, then says hello to it, so **both** phones list
   each other with a **Bluetooth** badge (within about 30 seconds). After that
   they keep finding each other even when neither is visible.

Pairing is not needed. Already-paired phones show up straight away.

**Both on:** if WiFi and Bluetooth are both available, the app uses both, and
a phone can appear twice (once per badge). Either entry can be used to call.
The status bar shows what is in use: *WiFi + Bluetooth*, *WiFi only* or
*Bluetooth only*.

### Refresh

Tap **⟳** (top right) to clear the list and scan again, for example after
turning on WiFi or Bluetooth. While no device is found, the app refreshes by
itself every 20 seconds. It never refreshes during a call.

### 3. Make a call

- Tap the green **call** button next to a device.
- Your screen shows **Calling…** until the other person answers. Then the
  timer starts.

### 4. Answer a call

- The other phone shows an **Incoming Call** sheet with the caller's name.
- Tap **Answer** to talk, or **Decline**, which tells the caller.

### 5. During a call

| Control | What it does |
|---|---|
| **Mute** | Turns your microphone off / on |
| **Earpiece / Speaker** | Plays sound from the earpiece or the loudspeaker |
| **Walkie** | Push-to-talk: hold the button to speak, release to listen |
| **End Call** | Hangs up on both phones |

### Group call (WiFi)

Tap the circle next to two or more devices to select them, then tap
**Start Group Call**.

## Build & Run

Requirements: Flutter 3.22+, Android SDK, a USB cable with **USB debugging**
on the phone.

```bash
cd vocky_call
flutter pub get

# Run on a connected phone
flutter run --release

# Or build an APK and install it
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. You can
also copy it to a phone and open it there.

### Run tests

```bash
flutter test
```

### Sandbox mode (no second phone)

```bash
flutter run -t lib/main_sandbox.dart
```

This uses fake devices and fake calls to try the UI.

## Testing on Two Emulators

Bluetooth works between two emulators out of the box: the emulator's virtual
Bluetooth connects them. Start two instances of an AVD with `-read-only`,
install the app on both, tap **Make Visible** on one, and call from the other.

Two emulators can't reach each other over WiFi, because each sits on its own
private network. For testing only, the app accepts these build flags:

| Flag | Purpose |
|---|---|
| `VOCKY_STATIC_PEERS=Name@host:port` | Adds a WiFi peer by address, e.g. `Emulator-B@10.0.2.2:19001` |
| `VOCKY_TURN_URL`, `VOCKY_TURN_USER`, `VOCKY_TURN_PASS` | Relays WebRTC audio through a TURN server, e.g. `turn:10.0.2.2:3478` |

Use them with `adb forward` (for signaling) and a TURN server running on the
host (for audio). **Never use these flags for real-device builds.**

## Troubleshooting

| Problem | Fix |
|---|---|
| Other phone not listed (WiFi) | Make sure both are on the same network. Some routers block devices from seeing each other ("AP / client isolation"); use a phone hotspot instead. |
| Other phone not listed (Bluetooth) | Tap **Make Visible** on one phone, check Bluetooth and location are on, then wait up to 30 s or tap refresh. |
| Status says "Discovery error" | Neither WiFi nor Bluetooth is on. Turn one on; the app retries every 20 s. |
| "Could not connect to Bluetooth device" | VockyCall must be open on the other phone. Move the phones closer and try again. If it keeps failing, turn Bluetooth off and on again on both phones. |
| No sound | Check that microphone permission is allowed and the volume is up. Try switching between Speaker and Earpiece. |
| "Required permissions were denied" | Open Android **Settings → Apps → VockyCall → Permissions** and allow them. |

View logs from a connected phone:

```bash
adb logcat | grep -E "VockyBt|flutter"
```

### Ports used

| Port | Protocol | Purpose |
|---|---|---|
| 9999 | UDP | WiFi device discovery |
| 9000 | TCP | WiFi call signaling |
| RFCOMM `…2e10` / `…2e11` | Bluetooth | Calls / hello messages |
| dynamic | UDP | WebRTC audio |
