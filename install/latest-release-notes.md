### v1.6.0 (10600) - 2026-11-05
`ACC: dev-2025-06-06`

WebUI 🎛️ ->
- Added language switcher to the WebUI banner.
- Added animated gradient glow to the WebUI banner border to indicate active charging.
- Added system information line to the WebUI banner displaying the root solution, Android version, and kernel version.
- Added automatic daemon restart on configuration reset.
- Added dynamic `accd` description system with real-time status and charging thresholds (@LegacyFreeman).
- Added multi-language localization support (de-DE, fr-FR, pt-PT, ru-RU, tr-TR, zh-CN, zh-TW) (@LegacyFreeman). *Only Russian currently has a complete WebUI translation; the other languages currently include shell translations only. WebUI translations can be contributed through [Crowdin](https://crowdin.com/project/acc-with-webui).*
- Centralized WebUI and Shell (action button, module description, and installation) translations in Crowdin as the single source of truth.
- Added documentation language switcher and corrected header layout in `README.md` (@LegacyFreeman).
- Fixed `module.prop` initialization and prevented infinite loops during background state updates (@LegacyFreeman).
- Fixed WebUI components (`App.svelte`, `Toast.svelte`, `DropdownModal.svelte`, `banner.svelte.js`) and build workflow integration (@LegacyFreeman).
- Fixed unwanted long-press highlighting of dropdown items in *WebUI X: Portable (WXP)* while preserving selected item styling.
- Fixed unwanted text selection on the WebUI banner title and subtitle.
- Fixed `Test All` card not autoscrolling correctly upon opening.
- Fixed visual synchronization for `Charging Thresholds`, `Idle Mode`, and `Reset Battery Stats` so they update instantly on configuration reset.
- Updated npm dependencies.

