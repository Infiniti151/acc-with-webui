### v1.2.0 (10200) - 2026-09-12

WebUI 🎛️ ->
- Added `Idle Mode` section with multiple toggles and idle-apps selector.
- Added info buttons to provide detailed descriptions for each toggle.
- Updated npm dependencies.

### v1.1.1 (10101) - 2026-08-10

WebUI 🎛️ ->
- Fixed `accd` not showing correct status in WebUI for module's initial install.
- Fixed capacity fetching in action.sh and service.sh to use a single command instead of three.
- Reduced module zip size by 13% by only including files and folders needed by the module.
- Used latest-release-notes.md for module changelog instead of changelog-webui.md so users are presented only with the latest version changelog instead of the entire project changelog.
- Optimized build workflow.

### v1.1.0 (10100) - 2026-08-09

WebUI 🎛️ ->
- Added action button to quickly toggle `accd` state.
- Added status indicators for `accd` ✅❌, `resume_capacity` 🟢, `pause_capacity` 🟡, and `shutdown_capacity` 🔴 in the description.
- Added `shutdown_capacity (sc)` slider to `Charging Thresholds`. It's clamped between 0%-20% (`acc` default is 5%). It shuts down the phone at that threshold to preserve battery health.
- Added `Export Logs` button in `Logs` to export logs. `acc` exports logs as a .tgz file in `/storage/emulated/0/Download`. It takes about 30 seconds to export, so be patient!
- Added a notification banner to enforce restarting the daemon on any setting change. Needed to do this as some settings weren't being picked up by the daemon automatically. The banner persists until `accd` restarts or the device reboots.
- Added a toast to notify config file save status and completion of log export.
- Fixed issue where daemon started/restarted from the WebUI wouldn't persist due to it being in the manager's cgroup instead of the root cgroup.
- Updated `Save Config` button to show saved status on successful save.
- Updated sliders to be cascading to enforce `shutdown_capacity < resume_capacity < pause_capacity` and for better UX.
- Updated `acca` commands to `/dev/acca` to prevent path lookup.
- Updated readme with build instructions for the WebUI.
- Updated CSS into sections for better manageability.
- Updated npm dependencies.

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