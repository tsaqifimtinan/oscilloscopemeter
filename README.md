# Scope

macOS oscilloscope, goniometer, VU meter and loudness (LUFS) meter for system audio (ScreenCaptureKit), with a clean mode for capturing the window in OBS. Requires macOS 15+ and Xcode.

## Build & run

```sh
brew install xcodegen
./scripts/build.sh          # generate Scope.xcodeproj and build
./scripts/build.sh test     # run unit tests (quiet; use xcodebuild directly to see per-test output)
./scripts/run.sh            # build and launch
TEST_RUNNER_STRESS_SECONDS=60 ./scripts/build.sh test   # long feed stress test
```

The scripts set `DEVELOPER_DIR` to `/Applications/Xcode.app` because `xcode-select` may point at the Command Line Tools.

## Screen Recording permission

System audio capture goes through ScreenCaptureKit, so macOS requires Screen Recording permission.

1. Launch Scope and click **Request Access**.
2. Enable Scope in System Settings → Privacy & Security → Screen & System Audio Recording.
3. Quit and relaunch Scope, then click **Start**.

The app is ad-hoc signed (`CODE_SIGN_IDENTITY=-`), so each rebuild changes its signature and macOS may drop the grant. If capture starts failing after a rebuild, remove Scope from the list and grant it again, or run `tccutil reset ScreenCapture com.tsaqif.scope`. To stop this happening, sign with a stable development identity.

## Using it

Everything lives in the **View** menu and the right-click menu. The right-click menu stays available in clean mode.

| Key | Action |
|-----|--------|
| ⇧⌘H or H | Toggle clean mode |
| Esc | Leave clean mode |
| 1 – 5 | Layout: Scope only · Scope + VU · Scope + LUFS · Scope + VU + LUFS · Meters only |
| R | Reset loudness |

The single-letter keys only work while Scope is focused.

- **Panels:** Scope, Goniometer, VU and LUFS can be shown in any combination. The layout presets set Scope/VU/LUFS and leave the Goniometer toggle alone.
- **Wide layout:** panels sit side by side. The scope takes the leftover width, the goniometer is square, LUFS is a tall column and VU takes up to half the remaining width. A Free window narrower than about 1.6:1 switches to the stacked arrangement (VU under the scope).
- **VU:** standard ballistics (99% at 300 ms). Reference is 0 VU = −18 dBFS by default, or −20 (EBU) or −14. Stereo shows L and R needles; Mono Sum shows one needle for (L+R)/2.
- **Loudness:** ITU-R BS.1770-4 / EBU R128. Three slim bars: Momentary (400 ms), Short-term (3 s) and Integrated (gated). Loudness Range (EBU Tech 3342) is still measured but not displayed. Targets are −23 / −24 / −16 / −14 LUFS; bars turn yellow above the target, which is marked by an arrow and a thin line.
  - **Pause** freezes Integrated and LU Range, which stop accumulating. Momentary and Short-term keep moving so you can still monitor.
  - **Reset** clears everything, including the K-filter state and the max peaks.
  - Pause/Resume and Reset are in the Loudness menu and on the panel's right-click menu; R also resets.
  - **Show dB Scale** (on by default) shows the dB labels left of the bars. Turn it off for just the bars.
- **Settings persist:** layout, panels, scope controls, VU reference, loudness target, background, keep-on-top, window shape, and window size/position.

## OBS setup

1. In Scope, pick a shape from View → Window Shape. It resizes the window and locks the aspect, including in clean mode. OBS captures native pixels, so on a Retina display the capture is 2× the point size:

   | Shape | Window (pt) | Capture (px) |
   |---|---|---|
   | 21:9 (default) | 1260 × 540 | 2520 × 1080 |
   | 2:1 | 1080 × 540 | 2160 × 1080 |
   | 32:9 | 1920 × 540 | 3840 × 1080 |
   | 16:9 | 960 × 540 | 1920 × 1080 |
   | Free | any | — |

   For a wide recording, set OBS **Settings → Video → Base (Canvas) Resolution** and **Output (Scaled) Resolution** to the matching capture size (e.g. 2520 × 1080 for 21:9). A 16:9 canvas would letterbox the window.
2. Turn on **Keep on Top** so the window is never covered, then enter clean mode (H). The title bar, buttons, controls, overlays, shadow and cursor all disappear. Drag the window from anywhere.
3. In OBS, add a **macOS Screen Capture** source, set Method to **Window Capture**, and pick the Scope window.
4. Pick a background in View → Background:
   - **Black** (default): add a **Luma Key** filter or set the source's blend mode to **Additive** to drop the black.
   - **Chroma Green** (#00FF00): add a **Chroma Key** filter.
   - **Transparent** is experimental. OBS on macOS often captures it as black, so the two options above are the reliable routes.

Scope holds a `ProcessInfo` activity so App Nap doesn't throttle it while it's in the background. macOS may still slow redraws for a window that is fully covered, which is another reason to use Keep on Top.

## Known limits

- **Input:** capture is system audio at 48 kHz only. The loudness filters use 48 kHz coefficients, so any other rate is rejected with an error rather than measured wrongly. There is no input-device selection yet.
- **DRM:** DRM-protected playback may capture as silence.
- **Mono sources:** mono input is duplicated to L and R. That reads +3 LU higher than BS.1770's single-channel measurement of a mono file. System audio arrives as stereo, so this doesn't normally come up.
- **True peak:** uses a Hann-windowed-sinc interpolator, not the BS.1770-4 Annex 2 coefficient table. It is within ~0.1 dB below ~16 kHz but isn't conformance-grade near Nyquist.
- **Loudness tests:** Integrated and LRA are checked against synthetic signals (see `Tests/LoudnessTests.swift`). They have not yet been run against the EBU Tech 3341/3342 conformance files.
- **Scope trigger:** no holdoff, hysteresis or Single mode.
