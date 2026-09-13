### v1.3.0 (10300) - 2026-09-13

WebUI 🎛️ ->
- Added search functionality inside Idle Apps modal.
- Added CLI args (`-W/--webui`) to `build.sh` to make building the WebUI easier.
- Fixed long package names that previously truncated with ...; they now scroll horizontally for full visibility inside Idle Apps modal.
- Fixed unwanted text selection and long‑press context menu inside Idle Apps modal.
- Fixed scroll bleed on the Idle Apps modal; scrolling inside the modal no longer scrolls the WebUI behind it.
- Fixed an issue where selected system apps did not appear in the app list unless the “System Apps” toggle was enabled; selected system apps now always appear regardless of toggle state.
- Optimized `build.sh`.

