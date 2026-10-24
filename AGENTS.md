# Project instructions

Follow the Australian Government Style Manual at https://www.stylemanual.gov.au for all project-owned copy. Read docs/style.md before changing wording. Apply the relevant guidance to app labels, messages, documentation and release notes. Preserve exact product names, code identifiers and third-party legal notices.

Use SettingsStore and SQLite for persistent app data. UserDefaults is only a migration source. macOS remains responsible for pairing, permissions and login registration. Do not persist live device readings as current settings.

Run ./scripts/test.sh and ./scripts/build.sh after code changes. Preserve the temporary build and signing workflow in scripts/build.sh.
