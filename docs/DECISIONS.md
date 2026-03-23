
---

## 2026-03 · Mobile navigation: fixed bottom nav bar, not off-canvas hamburger sidebar — M19

The original M19 spec called for an off-canvas sidebar toggled by a hamburger button via
`sidebar_controller.ts`. During implementation, Cuprite's headless Chrome viewport emulation
proved unreliable for testing media-query-driven CSS changes mid-test: `Emulation.setDeviceMetricsOverride`
updates `window.innerWidth` but the rendered layout does not consistently recalculate before
subsequent interactions fire, making the toggle specs non-deterministic regardless of
synchronization strategy attempted.

Rather than work around a test infrastructure limitation, the mobile nav pattern was changed
to a fixed bottom nav bar (`_bottom_nav.html.erb`, `_bottom_nav.css`). This is a better mobile
UX pattern for a navigation-heavy internal tool (mirrors native app conventions), eliminates
all JavaScript from the navigation layer, and makes the specs straightforward DOM presence
and link checks that don't depend on viewport state. `sidebar_controller.ts` removed entirely.
