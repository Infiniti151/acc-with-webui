### v1.5.0 (10500) - 2026-10-26
`ACC: dev-2025-06-06`

WebUI 🎛️ ->
- Added Action and WebUI shortcut icons.
- Added `Charging Switch` section to list, test, and set the appropriate switch.
- Added `Reset` button to `Config` to reset the config to default settings.
- Added `Clear` button to `Logs` to clear volatile logs.
- Added search, undo/redo, and top/bottom navigation controls to `Config`.
- Added search and polling toggle controls to `Logs`.
- Added orientation persistence for the WebUI so it retains the scroll position when the screen is rotated.
- Added orientation persistence for toggle descriptions, `Idle Apps Modal`, `Config`, and `Logs` so they remain open and retain their exact scroll position when the screen is rotated.
- Added banners which guide users (especially first install) on the actions to take when a charging switch is not set making the process more transparent.
- Added hints to `Charging Thresholds` and `Idle Mode` to indicate that these sections won't be in effect until a charging switch is set.
- Added app icons in `Idle Apps Modal`.
- Added sync for `Config Editor`; if the editor is open and any setting is changed via toggles/dropdown/modal/input, it is reflected instantly in the editor.
- Added multi-type toasts (`info`/`success`/`error`/`warning`/`confirm`) for clearer visual feedback.
- Added CLI args (`-d/--deploy`) to `build.sh` to enable live-deploying the WebUI (`index.html`) to a device connected via wired/wireless ADB. If a device is connected via both, wired is selected by default (Needs root granted to Shell [com.android.shell] in the root manager app). This saves time and effort when testing compared to manually copying the file from PC to phone.
- Added ACC base version to module version and WebUI footer to make it easier to know the ACC version on which the WebUI is based.
- Reorganized sections as per the `Charging Switch` section.
- Made the sections cleaner by removing the divider lines between each setting and only keeping a single divider under the section title.
- Fixed `Config` and `Logs` autoscroll; whenever they are opened, the autoscroll will scroll them above the NavBar height instead of partially behind it.
- Fixed app labels in `Idle Apps Modal`; now they show the correct app names.
- Fixed daemon status showing `Stopped` for a brief moment after opening the WebUI; now it shows `Checking...`
- Changed the color of log file paths in `Logs` to make them distinct.
- Switched from CDN Material icons to bundled Material icons via unplugin-icons (tree-shaken, offline-ready).
- Switched from system monospace font to bundled JetBrains mono font.
- Updated npm dependencies.

### v1.4.0 (10400) - 2026-09-15
`ACC: dev-2025-06-06`

WebUI 🎛️ ->
- Added volatile logs (`/dev/.vr25/acc/*.log`) to `Logs` section.
- Moved existing logs (`/data/adb/vr25/acc-data/logs/*.log`) under persistent logs.
- Added a button to select volatile/persistent logs.
- Added text selection in logs viewer.

### v1.3.0 (10300) - 2026-09-13
`ACC: dev-2025-06-06`

WebUI 🎛️ ->
- Added search functionality inside Idle Apps modal.
- Added CLI args (`-W/--webui`) to `build.sh` to make building the WebUI easier.
- Fixed long package names that previously truncated with ...; they now scroll horizontally for full visibility inside Idle Apps modal.
- Fixed unwanted text selection and long‑press context menu inside Idle Apps modal.
- Fixed scroll bleed on the Idle Apps modal; scrolling inside the modal no longer scrolls the WebUI behind it.
- Fixed an issue where selected system apps did not appear in the app list unless the “System Apps” toggle was enabled; selected system apps now always appear regardless of toggle state.
- Optimized `build.sh`.

### v1.2.0 (10200) - 2026-09-12
`ACC: dev-2025-06-06`

WebUI 🎛️ ->
- Added `Idle Mode` section with multiple toggles and idle-apps selector.
- Added info buttons to provide detailed descriptions for each toggle.
- Updated npm dependencies.

### v1.1.1 (10101) - 2026-08-10
`ACC: dev-2025-06-06`

WebUI 🎛️ ->
- Fixed `accd` not showing correct status in WebUI for module's initial install.
- Fixed capacity fetching in action.sh and service.sh to use a single command instead of three.
- Reduced module zip size by 13% by only including files and folders needed by the module.
- Used latest-release-notes.md for module changelog instead of changelog-webui.md so users are presented only with the latest version changelog instead of the entire project changelog.
- Optimized build workflow.

### v1.1.0 (10100) - 2026-08-09
`ACC: dev-2025-06-06`

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
`ACC: dev-2025-06-06`

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