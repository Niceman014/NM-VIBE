# NM VIBE Update Policy

- **Store handoff**: app updates should be handed off to Google Play or Microsoft Store.
- **Windows integrity**: verify Windows installers by hash before opening them.
- **No self-updater**: do not build a mechanism that replaces the app binary itself.
- **Existing implementation**: hand off updates to the stores and verify Windows installers by hash.
