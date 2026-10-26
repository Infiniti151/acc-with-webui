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

