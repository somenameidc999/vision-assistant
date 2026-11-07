# Setup

Checked: 2026-11-06.

## Current Mac

The inspected machine runs macOS 26.5.2 on Apple silicon. The initial check found about 53 GiB free. Xcode 26.6 is present at `/Applications/Xcode-26.6.0.app`. Apple license and first-launch setup pass. The iOS 26.5 runtime is installed and an iPhone 17 Pro simulator is booted. Apple Command Line Tools remain the global selection; the project launch scripts use the explicit Xcode developer directory.

Installed during implementation: `xcodes` 2.1.0, XcodeGen 2.46.0, FFmpeg 9.0.2, and project Python/Node dependencies. Node.js 22.22.3 is available through nvm. The backend launcher selects that version when necessary.

The initial Xcode download stopped at an Apple Account prompt. The user completed installation and license setup locally. No Apple credentials were supplied to or stored by the project.

## Install full Xcode

Run these commands locally in Terminal. Apple sign-in and two-factor authentication happen there. Do not put Apple credentials in the repository or chat.

1. Run `xcodes install 26.6 --experimental-unxip`.
2. Run `xcodes select 26.6`.
3. Run `sudo xcodebuild -license` and review Apple's license.
4. Run `sudo xcodebuild -runFirstLaunch`.
5. Run `xcodebuild -downloadPlatform iOS`.
6. Run `xcrun simctl list devices available`.

If no iOS 26 iPhone simulator exists, create one in **Xcode > Window > Devices and Simulators**. Use an available iOS 26 runtime. Apple lists Xcode 26.6 as compatible with macOS 26.2 or later; recheck before downloading a different version. [Apple system requirements](https://developer.apple.com/xcode/system-requirements/)

Simulator builds do not require device signing. Installing on an iPhone requires a free Apple Account in Xcode. Free Personal Team provisioning expires after seven days. [Apple account requirements](https://developer.apple.com/help/account/basics/about-your-developer-account)

## Reproduce project setup

From the repository root:

```sh
nvm use
npm ci --prefix backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
brew install xcodegen ffmpeg
```

Create root `.env` from `backend/.env.example` and set `OPENROUTER_API_KEY` locally. Bootstrap generates a random `SESSION_TOKEN` when the token is missing or empty. Then run:

```sh
python3 scripts/bootstrap.py
.venv/bin/python scripts/make_fixtures.py
xcodegen generate --spec ios/project.yml
```

Bootstrap generates the ignored root `.env` and app `LocalConfig.json`. The app receives only the backend token. It never receives the OpenRouter credential. The generated Xcode project references the ignored config resource, so rerun bootstrap before building a fresh checkout.

Launch:

```sh
./scripts/run_backend.sh
```

In another terminal:

```sh
./scripts/run_simulator.sh --dev-prerecorded-scene
```

The video flag is development-only and works only in Debug Simulator builds. The default launch requires a live camera and never falls back to video. Long-press the centered camera button to open Connection settings.

The backend uses port **18787**. Port 8787 was occupied by an unrelated process during setup. Do not stop that process. If another port is needed, change `PORT` in root `.env` and rerun bootstrap.

## Microphone

In Simulator, choose **Device > Sound > Sound Input > System**. Grant macOS microphone permission to Simulator and iOS microphone permission to the app. The current Mac exposes a Jump Desktop virtual microphone; its presence does not prove audio is arriving. [Apple simulator audio configuration](https://developer.apple.com/documentation/xcode/configuring-a-simulator-for-your-environment)

The voice path requires voice processing on the selected route. If setup fails, the app shows the error and keeps text questions available. Fix the route, end the session, and start again. A quiet first second allows microphone calibration. The app now requests one input channel after activating the session. This fixed a measured Core Audio initialization abort on the eight-channel Jump Desktop route. The engine now starts, but the user reports no real microphone on this machine. Audio route initialization does not prove live speech capture.

## Experiments

Stop the backend before a probe or baseline run. A process lock prevents concurrent backend and experiment writes to the spending ledger.

```sh
.venv/bin/python scripts/probe_openrouter.py
.venv/bin/python scripts/probe_openrouter.py --model google/gemini-3.5-flash-lite
npm --prefix backend run baseline
```

The probe uses synthetic images and synthesized speech. The baseline uses the public coffee photograph. Raw outputs remain under ignored `runs/`. Never infer live voice performance from these requests.

The probes stop after a failed request. The baseline has a $2 accounting ceiling; the full demo has a $10 ceiling. The ledger reserves $0.25 before each app or baseline request. Known reported cost replaces the reservation. Unknown charges retain the reservation, including cancellations and malformed replies. The model catalog is checked at startup for required inputs and price bounds. This is a conservative application guard, not a provider-enforced cap on the shared API credential.

Do not delete `runs/budget.json` to bypass the budget. After a crash, inspect the PID in `runs/budget.lock` and verify that process has exited before removing a stale lock. Restart the backend after changing configuration.

With the backend running, exercise real requests through the local API:

```sh
.venv/bin/python scripts/smoke_backend.py
```

## Connect an iPhone

Keep the backend on loopback. Use Tailscale Serve for private HTTPS or the iPhone proxy on trusted Wi-Fi. Follow the [iPhone install guide](iphone.md).

## Runtime matching on the development Mac

The installed Xcode is 26.6, build 17F113. Its SDK canonical name is `iphoneos26.5`, while its embedded SDK version metadata is 26.5.1 and build 23F81a. Xcode preferred simulator build 23F81a, but the installed iOS 26.5 runtime is build 23F73. Xcode initially reported that iOS was not installed even though `simctl` listed the runtime.

The following supported `simctl` override made the installed simulator a valid Xcode destination:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer xcrun simctl runtime match set iphoneos26.5 23F73
```

This is a local Xcode/runtime pairing choice, not an application requirement. Inspect `xcrun simctl runtime match list` before copying this workaround to another Xcode version. Restore the default mapping with `xcrun simctl runtime match set iphoneos26.5 --default` when using a newer matching runtime. The command behavior was checked against local `simctl runtime` help on 2026-11-06.

## Another Mac over Tailscale

The Simulator client needs another Mac with compatible Xcode and a real microphone. The backend can remain on this Mac. The app accepts a private HTTPS hostname ending in `.ts.net`; unencrypted Tailscale IP addresses are not supported by the client configuration. Private HTTPS avoids adding broad iOS transport-security exceptions.

A private Serve proxy is now enabled on this backend Mac at HTTPS port 8443. Mac-side health and authenticated session requests passed through the proxy. Phone-side and other-client connectivity still need verification. See the [iPhone install guide](iphone.md). For another client Mac, use [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) to proxy a private tailnet HTTPS endpoint to `http://127.0.0.1:18787`. Keep the backend on localhost. Check existing Serve configuration before selecting the proxy port. Serve may require HTTPS enablement in the tailnet. No public Funnel endpoint is needed. Sources checked 2026-11-06.

Package the current source tree on the backend Mac:

```sh
python3 scripts/package_demo.py
```

The archive is `runs/vision-assistant-demo.tar.gz`. It includes current uncommitted source files and the licensed media. It excludes ignored local credentials, session configuration, captures, dependencies, and build products. The packager checks for the current provider credential, local session token, and OpenRouter key patterns before producing the archive.

On the client Mac:

1. Transfer and extract the archive using your chosen private connection.
2. Install compatible Xcode and an iOS 26 simulator runtime.
3. Install XcodeGen with `brew install xcodegen`.
4. Create an ignored root `.env` containing only `SESSION_TOKEN` and `BACKEND_URL` for the private backend.
5. Run `python3 scripts/bootstrap.py --client-only`.
6. Run `./scripts/run_simulator.sh --dev-prerecorded-scene`.
7. Verify the microphone route and repeat the spoken tests.

The client Mac does not need the OpenRouter credential, Node dependencies, Pillow, or FFmpeg to build the already packaged app and media. The session token authorizes the local demo backend; transfer it privately. You can instead enter the URL and token in the app's Connection sheet, opened by long-pressing the start button. Without a local `.env`, client-only bootstrap creates a blank token configuration and does not create an environment file.

## Physical iPhone

The installed app supports iOS 16.6 or later. Follow the [iPhone setup](iphone.md) for Personal Team signing, developer-certificate trust, the optional LAN proxy, and live-word permission. Keep the explicit Simulator development flag for fixture-based checks. Do not regenerate a locally configured Xcode project without preserving its selected development team.
