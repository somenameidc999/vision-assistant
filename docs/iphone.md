# Install on a personal iPhone

Checked: 2026-11-06.

## Current state

The native iPhone build compiled successfully without signing. The private Tailscale HTTPS proxy on this Mac is enabled on port 8443 and its health endpoint returned HTTP 200 from the Mac. The backend still listens only on localhost. Public Funnel is disabled.

Xcode now detects an iPhone 12 running iOS 16.6.1 over USB. The app now has an unsigned compatibility build with `MinimumOSVersion` 16.6. Personal Team signing, installation, launch, and developer-certificate trust are complete. The user confirmed live camera use, spoken interaction, live words, and the full-screen interface. Formal delay, echo, interruption, and orientation measurements remain pending.

## Local setup

1. Connect the iPhone to this Mac mini with a USB data cable.
2. Unlock the iPhone.
3. Tap **Trust** on the iPhone if prompted.
4. Open `ios/VisionAssistant.xcodeproj` in Xcode.
5. On the Mac, open **Xcode > Settings > Apple Accounts** and sign in locally.
6. Select the **VisionAssistant** app target.
7. Open **Signing & Capabilities**.
8. Select your **Personal Team** under Team.
9. Select your connected iPhone as the run destination.
10. Enable **Settings > Privacy & Security > Developer Mode** on the iPhone if requested.
11. Confirm Developer Mode after the iPhone restarts.

Apple requires a local Apple Account for personal-device signing. A free Personal Team is sufficient for this app. Personal Team provisioning expires after seven days, requiring a rebuild and reinstall. [Apple account requirements](https://developer.apple.com/help/account/basics/about-your-developer-account), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

Keep Apple credentials in Xcode. The helper uses Xcode's stored account and never accepts an Apple password.

## Build and install

From the repository root:

```sh
python3 scripts/install_iphone.py
```

The helper selects a phone only when exactly one iPhone is visible. It uses `xcdevice` for discovery across supported iOS versions. It checks the OS and Developer Mode, reads the selected Xcode development team, generates ignored phone configuration, builds with automatic provisioning, verifies the code signature, installs, and launches the app. iOS 16 uses `ios-deploy` for installation and `idevicedebug --detach` for launch; iOS 17 or later uses Apple’s `devicectl`. The legacy path verifies that the installed app has a running process. It registers the device through Xcode when required. The phone build uses a bundle identifier scoped to the selected team to avoid a generic app-identifier conflict.

The ignored root `.env` stores `IPHONE_BACKEND_URL`. Optionally store `IPHONE_DEVELOPMENT_TEAM`, or pass `--team <team-id>` when the project has no selected team. Use `--device <phone-name-or-identifier>` if several phones are visible. Build logs and device metadata stay under ignored `runs/`.

The current build requires iOS 16.6 or later. The connected iPhone runs iOS 16.6.1. The compatibility build passed and the app is installed. Live behavior is user-confirmed; quantified acceptance tests remain pending. The helper does not update or erase the phone.

For iOS 16, install the legacy deployment tool once:

```sh
brew install ios-deploy libimobiledevice
```

`ios-deploy` 1.12.2 and `libimobiledevice` 1.4.0 are installed on this Mac. The project documents support for iOS versions before iOS 17. Xcode 26.6 supports device deployment to iOS 15 or later. [ios-deploy](https://github.com/ios-control/ios-deploy), [Apple Xcode requirements](https://developer.apple.com/xcode/system-requirements), checked 2026-11-06.

## Phone connection and first run

The current phone build uses the Mac's private Wi-Fi IPv4 address through a small LAN proxy. The earlier Tailscale hostname failed DNS lookup on the phone. Tailscale remains available when the phone connects to the same tailnet.

For local Wi-Fi, keep the phone and Mac on the same trusted network. Start the backend, then start the proxy with the Mac's actual private IPv4 address:

```sh
ipconfig getifaddr en1
python3 scripts/run_iphone_proxy.py --listen-address <mac-private-ip>
```

The proxy binds only that address, not every interface. The backend remains on localhost. The proxy forwards bytes in memory and retains backend authentication and validation. LAN HTTP does not encrypt traffic; use private Tailscale HTTPS when encryption is needed. Set `IPHONE_BACKEND_URL` in ignored `.env` to `http://<mac-private-ip>:18787`, then run the installer. A changed DHCP address requires updated configuration. Do not put the session token into a URL.

1. Open the configured backend's `/health` address in Safari on the iPhone.
2. Confirm the response contains `"status":"ok"`.
3. Open Vision Assistant.
4. Trust the Developer App under **Settings > General > VPN & Device Management** if iOS blocks first launch.
5. Tap the centered camera icon button.
6. Allow camera, microphone, and Speech Recognition access.
7. Wait quietly for one second of microphone calibration.
8. Point the camera at a non-sensitive ordinary scene.
9. Ask “What do you see?”
10. Confirm live words appear while you speak.
11. Ask a follow-up question.
12. Tap the camera-switch icon to use the front camera.
13. Tap the stop icon to end the session.

The active controls are mute, stop speaking, switch camera, and end, from left to right. Stop speaking is available only while the assistant is speaking. Camera failures never substitute video. Long-press the start button to change Connection settings. Speech Recognition is optional for spoken questions and required for live words. Live recognition requires on-device support; the app does not fall back to Apple's servers.

The app receives a backend session token, never the OpenRouter credential. Selected camera frames and recorded questions go to the cloud model after question submission. The app does not save captures to the photo library.

The current private address is prefilled in ignored `LocalConfig.json`. The optional Tailscale pattern is `https://<backend>.<tailnet>.ts.net:8443`. The development Mac's successful check does not prove the iPhone can reach that address; the Safari check establishes that separately.

## Local service management

The private proxy was created with Tailscale Serve, after confirming no existing Serve configuration:

```sh
tailscale serve --bg --https=8443 http://127.0.0.1:18787
```

Inspect the current configuration with `tailscale serve status`. Disable only this proxy with `tailscale serve --https=8443 off`. This does not require changing the backend to listen on the LAN. [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)

Physical-device verification remains recorded in the [demo checklist](demo.md). Successful installation alone does not establish camera quality, live voice quality, or interruption performance.
