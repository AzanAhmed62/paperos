# E-Ink Friendly profile

PaperOS 1.2 adds a persistent **Display profile** setting with two values:

- **Standard** — the original PaperOS presentation.
- **E-Ink Friendly** — a still, high-contrast, page-oriented presentation for
  electrophoretic panels.

The profile is a user preference, not a device detection result. It can be
selected on any Android display. It is stored in the settings document as
`display.profile` and is included in backups.

The profile is software-only. PaperOS 1.2 does not call a vendor refresh API,
does not send undocumented broadcasts, and does not claim that an E-Ink panel
was flashed. Android exposes no portable display-refresh API. A future
implementation may use a documented, testable vendor API behind
`DisplayCapabilityService`, but only with real hardware validation.

## What the profile changes

The values below are implemented in `DisplayPolicy` and are consumed by real
widgets. Tests cover the policy and the settings round trip; visual appearance
still requires a device.

| Area | Standard | E-Ink Friendly |
| --- | --- | --- |
| Motion | Short 220 ms theme transition and 180 ms overlay fade | Route overlays render without the fade; `MediaQuery.disableAnimations` is true; theme animation duration is zero |
| Home clock | Rebuilds every second | One one-shot timer lands 40 ms after the next minute boundary |
| Reader flow | The stored paged/scroll choice | Forced to paged at render time; the stored choice is unchanged |
| Page turns | The stored tap/swipe/both choice | Forced to tap zones at render time |
| Page-turn zones | 30% of the reader width on each side | 34% on each side, leaving a wider selection-safe centre |
| Reader chrome | Auto-hides after inactivity | Stays visible after it is summoned; no redraw timer removes it |
| Typography | Stored font size, line height and margins | Render-time ×1.06 font size, +0.06 line height and ×1.12 margins, clamped to the reader control ranges |
| Touch targets | 44/32 logical pixels | 48/40 logical pixels |
| Contrast | Selected paper palette | Higher-contrast rules, secondary text and selection fill |
| Selection | 20% selection fill | 34% selection fill |
| Loading and chrome | Normal animations | Animation durations from the policy are zero |

The clock does not rebuild 60 times a minute for a value that changes once a
minute. A fresh minute boundary schedules a full 60-second delay plus the 40 ms
safety margin, rather than a tight zero-duration timer.

## Where it is applied

- `PaperApp` watches `displayPolicyProvider`, applies the high-contrast palette,
  publishes `DisplayPolicyScope`, and sets `MediaQuery.disableAnimations`.
- The router's custom overlay transition returns its child immediately when
  animations are disabled.
- `PaperHomeScreen` schedules the clock with `nextClockDelay` and reschedules
  when the profile changes.
- `ReaderController` and `ReaderScreen` apply `readerSettingsForDisplay` to a
  copy; they never write those adjusted values back to Settings.
- Shared `Paper` widgets enlarge their minimum interactive size.
- The reader's chrome timer respects `autoHideReaderChrome`.
- Settings shows the active profile and an honest capability summary.

## Where it is not applied

- It does not change Android system UI, the status bar, the keyboard or other
  apps.
- It does not force the whole OS into a monochrome mode.
- It does not control a front light or refresh waveform.
- It does not guess "this looks like E-Ink" from a device model or screen
  contrast.

## Capability seam

`DisplayCapabilityService` has one shipped implementation,
`ConservativeDisplayCapabilityService`, which reports:

```text
isEinkPanel: false
supportsHardwareRefresh: false
vendorName: null
```

`DisplayPolicy.hardwareRefreshAvailable` is true only for the E-Ink profile when
capabilities report a documented hardware refresh implementation. Even then,
the policy must not fake a flash. No vendor code ships in 1.2.

Adding a vendor implementation requires:

1. documented public API details from the vendor;
2. a platform channel that degrades safely when the API is absent;
3. real hardware to validate the waveform, ghosting and failure behaviour;
4. tests for the capability decision and the fallback;
5. an updated version of this document and the manual checklist.

Until all of that exists, the honest status is "software-only".

## Verification

| Check | Status |
| --- | --- |
| Profile persists across a settings reload | Automated test passed |
| Legacy settings without a display section load as Standard | Automated test passed |
| Future settings version is rejected by strict import | Automated test passed |
| Standard values are unchanged | Unit test passed |
| E-Ink values, clamps and clock cadence | Unit test passed |
| Render-time reader settings do not mutate stored values | Unit test passed |
| Visual quality on a real E-Ink panel | Not run — no device |
| Ghosting, refresh latency and front light behaviour | Not run — no device |
| Hardware vendor refresh | Not implemented; no documented API |

To try the profile, open **Settings → Display profile → E-Ink Friendly**. Switch
back to Standard at any time; stored reading choices were never overwritten.
