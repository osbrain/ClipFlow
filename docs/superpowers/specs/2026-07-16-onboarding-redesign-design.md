# ClipFlow First-Run Onboarding Redesign

## Goal

Replace the sparse first-run screen with a compact, product-grade single-screen onboarding experience that explains ClipFlow's value, requests Accessibility permission honestly, and remains usable when permission is skipped or denied.

## Layout

The onboarding fills the existing main panel instead of centering a narrow 430-point column inside it. At the minimum supported 800×520 window it uses a two-column layout:

- The 250-point left column contains the brand icon, a concise product promise, three capability statements, and the current global shortcut.
- The flexible right column contains the initial-setup heading, three status rows, the Accessibility privacy explanation, and the completion actions.

The layout uses the existing rounded window, material, accent color, and control metrics. It avoids decorative empty space, nested oversized cards, and long paragraphs.

## Setup States

The right column contains three rows:

1. Local encrypted storage is always shown as ready.
2. Automatic paste reflects the live `AXIsProcessTrusted` result. When untrusted it explains why permission is needed and offers an authorization action. When trusted it changes to a completed state without requiring the user to reopen onboarding.
3. The current panel shortcut is shown as ready and localized.

Accessibility remains optional. Before authorization, the primary completion action says “Try ClipFlow” and a secondary action says “Not now.” After authorization, the primary action says “Get Started.” Both completion actions mark onboarding complete; skipping permission must not block clipboard history, search, copy-back, or manual paste.

The permission state refreshes when onboarding appears and every second while it remains visible, covering the common flow of leaving ClipFlow for System Settings and returning. Opening System Settings must not dismiss the onboarding panel.

## Privacy and Recovery

The screen explicitly states that Accessibility is used only to post the paste keyboard shortcut and is not used to read keyboard input. If the system remains untrusted, onboarding continues to show the pending state and remains actionable. Existing rebind/reset recovery stays in Settings rather than making the first-run screen destructive.

## Localization and Accessibility

Every new visible string has English and Simplified Chinese translations. Status rows expose combined accessible labels, the authorization and completion controls have explicit labels and help text, and keyboard focus reaches the permission action before the primary completion action.

## Verification

- Unit tests cover layout metrics and trusted/untrusted presentation states.
- Localization parity tests cover all new keys.
- Visual acceptance adds a deterministic 800×520 Chinese onboarding capture and confirms there is no clipping or excess blank region.
- The complete test suite, Debug build, and Release build must pass.
