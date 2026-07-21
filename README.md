# ForceCursor

ForceCursor is a macOS and watchOS prototype that turns an Apple Watch into a short-session air mouse. Wrist rotation produces relative pointer movement and explicit Watch controls produce clicks.

This version uses Swift gRPC over the local network. There is no Bluetooth LE code or Bluetooth permission in either target.

The custom single-tap classifier comes after transport and motion have been proven on a physical Watch. The temporary click buttons exercise the exact `leftClick()` and `rightClick()` command path that a gesture detector will call later.

## Architecture

```text
Apple Watch                                      Mac
Core Motion                                      gRPC server on TCP 8787
gesture and motion intent   == gRPC/HTTP2 ==>    ordered command handler
one bidirectional stream                         CGEvent cursor control
```

The Watch determines what the wrist did. It sends `motion`, `leftClick`, `rightClick`, `mouseDown`, `mouseUp`, `scroll`, and `stop` commands through one persistent ordered stream. The Mac owns the actual pointer location because another mouse, HomeRow, a display change, or macOS can move it independently.

The Protocol Buffer contract is in `Protocol/force_cursor.proto`. Xcode's `GRPCProtobufGenerator` build tool plugin generates the Swift client, server, and message types when either target builds.

## Requirements

- Xcode 27 beta with the macOS 27 and watchOS 27 SDKs
- macOS 15 or newer
- watchOS 11 or newer
- A physical Apple Watch for the meaningful networking and motion test
- The Mac and Watch on the same trusted local network
- XcodeGen 2.45.4 or newer

ForceCursor currently uses plaintext gRPC because this is a LAN transport spike. Do not use it on an untrusted network. Pairing, authentication, and TLS belong in the next transport milestone.

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

   Or keep the system setting unchanged and prefix commands:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -version
   ```

4. Run `xcodegen generate`, then open `ForceCursor.xcodeproj`.
5. Wait for Xcode to resolve the two package dependencies.
6. If Xcode asks whether to trust and enable `GRPCProtobufGenerator`, approve it. It is supplied by the official `grpc/grpc-swift-protobuf` package.
7. Select the blue `ForceCursor` project icon in the navigator.
8. Under **Targets**, select `ForceCursorMac`, open **Signing & Capabilities**, enable **Automatically manage signing**, and choose your Apple Developer team.
9. Repeat that signing step for `ForceCursorWatchContainer` and `ForceCursorWatch`. The container is the non-executable iOS packaging stub required by a Watch-only app. It does not install an app on your iPhone.
10. If a bundle identifier is unavailable, change it under the target's **Signing & Capabilities** tab and make the same change in `project.yml` so regeneration keeps it. Keep the Watch identifier beneath the container identifier, such as `com.yourname.forcecursor.watchkitapp` beneath `com.yourname.forcecursor`.

Free personal-team signing is enough for your own devices, although its provisioning expires periodically.

## Connect a physical Apple Watch to Xcode

1. Pair the Watch normally with your iPhone and keep Bluetooth and Wi-Fi enabled on both devices. This pairing is only for Xcode device management, not ForceCursor's transport.
2. Connect the paired iPhone to the Mac with a cable. Unlock the iPhone and tap **Trust** if it asks whether to trust the Mac.
3. In Xcode, open **Window > Devices and Simulators**. In Xcode 27 this may open Device Hub.
4. Select the iPhone in the device list. Its paired Apple Watch should appear with it. Keep the iPhone and Watch unlocked while Xcode prepares developer support.
5. If Xcode asks for Developer Mode, open **Settings > Privacy & Security > Developer Mode** on both the iPhone and Apple Watch. Turn it on, allow the restart, then confirm Developer Mode after each device restarts.
6. Return to Xcode and wait until neither device says **Preparing**, **Connecting**, or **Developer Mode disabled**.
7. At the top of Xcode's main window, click the scheme menu and select `ForceCursorWatch`.
8. Click the destination immediately to the right of the scheme name. Under physical devices, select your Apple Watch, which may be displayed as the Watch name followed by **via** your iPhone.
9. Press **Command-R**. The first signed build can take several minutes because Xcode registers the Watch and creates provisioning profiles. If Xcode shows a **Register Device** button, click it.
10. Leave the Watch unlocked and on its charger until Xcode reports that the app launched.

If the Watch does not appear in the destination menu, do not choose **Any watchOS Device**. That destination only builds and cannot install. Verify that Xcode, iOS, and watchOS are compatible versions, reconnect the iPhone by cable, reopen Device Hub, and wait for device preparation to finish.

## Run the Mac server

1. Select the `ForceCursorMac` scheme and **My Mac** destination.
2. Press **Run**.
3. If macOS asks whether ForceCursor may accept incoming connections, allow it.
4. Click **Request Permission** in ForceCursor.
5. Open **System Settings > Privacy & Security > Accessibility** and enable ForceCursor.
6. Return to ForceCursor and click **Move right 80 px**. The pointer should move.
7. Copy the `Mac address` shown in the app, such as `192.168.1.42:8787`. Enter only the IP portion on the Watch.

If the Mac has multiple active network interfaces, the displayed address may not be the one used by the Watch. In that case, use the IPv4 address for the Wi-Fi interface shown under **System Settings > Network > Wi-Fi > Details > TCP/IP**.

## Run the Watch client

1. Leave the Mac app running.
2. Select the `ForceCursorWatch` scheme and your physical Apple Watch destination.
3. Press **Run** and wait for installation.
4. Grant Motion and Local Network permission if prompted.
5. Enter the Mac's IPv4 address in the Watch app. Do not include `:8787`.
6. Tap **Connect**. The Watch should show **Connected to Mac**, and the Mac should show **Apple Watch connected**.
7. Tap **Start Cursor**, then rotate your wrist gently.
8. Use the temporary buttons to test left and right click.
9. Tap **Stop Cursor** before leaving the app.

There is no Bluetooth pairing step. Reconnecting means opening the apps and tapping **Connect** after the Mac server is ready.

## Important watchOS transport test

Apple documents restrictions around low-level networking from watchOS apps, while the Swift gRPC packages declare watchOS support and WWDC26 demonstrates the new Swift gRPC stack. A simulator can also permit networking that a physical Watch refuses. For that reason, the first real milestone is simple: verify that this client can establish its HTTP/2 connection on an actual Watch.

If the physical Watch fails while the simulator succeeds, collect the exact error shown by the Watch and Xcode console. Do not spend time tuning motion until that transport result is understood. A fallback transport can then be chosen from evidence, but this repository currently remains gRPC-only.

## Current behavior

- Motion uses processed device-motion rotation rate at 50 Hz.
- The Watch sends relative motion intent, not absolute screen coordinates.
- All motion and button commands use one persistent bidirectional gRPC stream, preserving command order.
- Clicks are separate functions in `WatchAppModel`; a gesture recognizer can call the same functions later.
- The first version uses a manually entered Mac IP address. Discovery is intentionally deferred.
- Axis direction, dead zone, acceleration, and sensitivity need physical-device tuning.
- There is no application-level pairing, authentication, or TLS yet.

## Command-line checks

List schemes:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project ForceCursor.xcodeproj -list
```

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

1. Prove gRPC on a physical Watch and record connection latency and failures.
2. Tune wrist axes, dead zone, acceleration, and motion coalescing on hardware.
3. Add authenticated pairing and TLS.
4. Record labeled tap and non-tap IMU windows.
5. Implement a conservative personal tap detector, then replace it with an on-device model if data justifies it.
6. Add Digital Crown scrolling and tap-and-hold dragging.
