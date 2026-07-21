# ForceCursor

ForceCursor is a macOS and watchOS prototype that turns an Apple Watch into a short-session air mouse. Wrist rotation produces relative pointer movement, and explicit Watch controls produce clicks.

The physical Watch uses high-level `URLSession` HTTP requests. It does not use gRPC, Network.framework, Bluetooth LE, or a manually managed Bluetooth connection. This transport is compatible with the networking policy enforced on physical Apple Watch hardware.

The custom single-tap classifier comes after transport and motion have been proven. The temporary click buttons exercise the exact `leftClick()` and `rightClick()` command path that a gesture detector will call later.

## Architecture

```text
Apple Watch                                     Mac
Core Motion                                     HTTP server on TCP 8787
motion and button intent  == URLSession ==>     ordered command handler
protobuf request bodies                         CGEvent cursor control
```

The Watch determines what the wrist did. It sends `motion`, `leftClick`, `rightClick`, `mouseDown`, `mouseUp`, `scroll`, and `stop` commands as serialized Protocol Buffer messages. The Mac owns the actual pointer location because another mouse, HomeRow, a display change, or macOS can move it independently.

Motion is sampled at 50 Hz and transmitted at no more than about 30 Hz. Gyroscope velocity is integrated using the actual sample interval, a small dead zone removes drift, and nonlinear acceleration lets fast wrist turns cross a large display without making slow aiming overly sensitive. Displacement is accumulated while an HTTP request is in flight, so coalescing does not lose travel. The Mac eases each received displacement across 60 Hz cursor updates. Button commands preserve their order and are not discarded.

The Protocol Buffer contract is in `Protocol/force_cursor.proto`. Xcode's `SwiftProtobufPlugin` build tool plugin generates the Swift message types when either target builds.

## Requirements

- Xcode 27 beta with the macOS 27 and watchOS 27 SDKs
- macOS 15 or newer
- watchOS 11 or newer
- A physical Apple Watch for meaningful networking and motion testing
- The Mac and Watch on the same trusted local network
- XcodeGen 2.45.4 or newer

ForceCursor currently uses plaintext HTTP because this is a LAN prototype. Do not use it on an untrusted network. Authentication and TLS belong in a later milestone.

## Generate the Xcode project

`project.yml` is the source of truth. From the repository root, run:

```sh
xcodegen generate
```

Regenerate after changing packages, targets, build settings, capabilities, or adding source files. Normal edits to an existing Swift file do not require regeneration.

## First-time Xcode setup

1. Install Xcode 27 beta from Apple Developer Downloads.
2. Open Xcode once and let it install requested platform components.
3. If command-line tools still point to Command Line Tools, either select the beta globally:

   ```sh
   sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer
   ```

   Or prefix commands with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

4. Run `xcodegen generate`, then open `ForceCursor.xcodeproj`.
5. Wait for Xcode to resolve the Swift Protobuf package.
6. If Xcode asks whether to trust and enable `SwiftProtobufPlugin`, approve it. It is supplied by Apple's `swift-protobuf` package.
7. Select `ForceCursorMac`, open **Signing & Capabilities**, and choose your Apple Developer team.
8. Repeat that signing step for `ForceCursorWatchContainer` and `ForceCursorWatch`. The container is the iOS packaging stub for the Watch app.
9. If a bundle identifier is unavailable, change it in Xcode and make the same change in `project.yml` so regeneration keeps it.

Free personal-team signing is enough for your own devices, although its provisioning expires periodically.

## Connect a physical Apple Watch to Xcode

1. Pair the Watch normally with your iPhone.
2. Connect the paired iPhone to the Mac by cable for initial setup.
3. Enable Developer Mode on the iPhone and Watch when Xcode requests it.
4. In Xcode, open **Window > Devices and Simulators**.
5. Select the iPhone and wait for its paired Watch to appear.
6. Accept trust prompts and keep the iPhone and Watch unlocked while Xcode prepares developer support.
7. Confirm that the Watch appears as a run destination for the `ForceCursorWatch` scheme.

## Run the Mac server

1. Select the `ForceCursorMac` scheme and **My Mac** destination.
2. Press **Run**.
3. If macOS asks whether ForceCursor may accept incoming connections, allow it.
4. Click **Request Permission** in ForceCursor.
5. Open **System Settings > Privacy & Security > Accessibility** and enable ForceCursor.
6. Return to ForceCursor and click **Move right 80 px**. The pointer should move.
7. Copy the `Mac address` shown in the app, such as `192.168.1.42:8787`. Enter only the IP portion on the Watch.

If the Mac has multiple active network interfaces, use the IPv4 address for the Wi-Fi interface shown under **System Settings > Network > Wi-Fi > Details > TCP/IP**.

## Run the Watch client

1. Leave the Mac app running.
2. Select the `ForceCursorWatch` scheme and your physical Apple Watch destination.
3. Press **Run** and wait for installation.
4. Grant Motion and Local Network permission if prompted.
5. Enter the Mac's IPv4 address in the Watch app. Do not include `:8787`.
6. Tap **Connect**. The Watch performs `GET /health` and should show **Connected to Mac**.
7. Tap **Start Cursor**, then rotate your wrist gently.
8. Use the temporary buttons to test left and right click.
9. Tap **Stop Cursor** before leaving the app.

There is no Bluetooth pairing step beyond the normal Apple Watch and iPhone pairing. Reconnecting means opening both ForceCursor apps and tapping **Connect** after the Mac server is ready.

## HTTP endpoints

- `GET /health` returns HTTP 200 when the Mac server is ready.
- `POST /control` accepts one serialized `ForceCursorInput` and returns HTTP 204.
- The server keeps HTTP connections alive so `URLSession` can reuse the connection.
- The Watch sets its maximum connection count to one, preserving request order.

## Current limitations

- Plaintext HTTP has no authentication or encryption.
- The first version uses a manually entered Mac IP address.
- Cursor axes, dead zone, acceleration, and sensitivity need physical-device tuning.
- `URLSession` latency on watchOS can vary with the Watch's current network route.
- There is no automatic reconnection yet.

## Command-line checks

Build the Mac target without signing:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project ForceCursor.xcodeproj \
  -scheme ForceCursorMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Build the Watch target for a generic physical device without signing:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project ForceCursor.xcodeproj \
  -scheme ForceCursorWatch \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Next milestones

1. Measure HTTP request latency and loss on a physical Watch.
2. Tune wrist axes, dead zone, acceleration, and motion coalescing.
3. Add automatic reconnection and clearer network diagnostics.
4. Add authenticated pairing and TLS.
5. Record labeled tap and non-tap IMU windows.
6. Implement a conservative personal tap detector.
