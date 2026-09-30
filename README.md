# Scope

macOS oscilloscope / meter for system audio output (ScreenCaptureKit). Requires macOS 15+ and Xcode.

## Build & run

```sh
brew install xcodegen
./scripts/build.sh          # generate Scope.xcodeproj and build
./scripts/build.sh test     # run unit tests
./scripts/run.sh            # build and launch
```

The scripts set `DEVELOPER_DIR` to `/Applications/Xcode.app` because `xcode-select` may point at the Command Line Tools.

## Screen Recording permission

System audio capture goes through ScreenCaptureKit, so macOS requires Screen Recording permission.

1. Launch Scope and click **Request Screen Recording Access**.
2. Enable Scope in System Settings → Privacy & Security → Screen & System Audio Recording.
3. Quit and relaunch Scope, then click **Start Capture**.

The app is ad-hoc signed (`CODE_SIGN_IDENTITY=-`), so each rebuild changes its signature and macOS may drop the grant. If capture starts failing after a rebuild, remove Scope from the list and grant it again, or run `tccutil reset ScreenCapture com.tsaqif.scope`. To stop this happening, sign with a stable development identity.

DRM-protected playback may capture as silence.
