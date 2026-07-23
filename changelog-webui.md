### v1.0.1 (10001) - 2026-07-23

WebUI 🎛️ ->
- Fixed inverted array index parsing for `rbsu` (On Unplug) and `rbspl` (On Plug) configuration flags, restoring accurate switch state reporting.
- Improved `toggleSetting` reliability by extracting input state directly from DOM change events (`e.target.checked`), eliminating race conditions between Svelte bindings and rapid toggles.
- Cleaned up repetitive inline flexbox styles across M3 card settings using a dedicated `.setting-row` CSS component with automated bottom-border handling.
- Added automatic state rollback/refresh handling on command execution failures.

### v1.0.0 (10000) - 2026-07-23

WebUI 🎛️ ->
- Battery stats monitor (health, temperature, current and voltage)
- Daemon (accd) control panel
- Charging threshold sliders
- Reset battery stats toggles
- Config file editor
- Logs viewer

ACC ⚡ ->
- dev-908a5a4b716b7f2506a2e1426429293a11f42ab3 - 2025-06-06