# Changelog

## Unreleased

### Added

- The iMessage Relay menu-bar app for macOS: forwards new incoming Messages (iMessage, SMS and RCS) to an HTTPS webhook, without sending texts or writing to `chat.db`.
- Read-only access to `~/Library/Messages/chat.db` with a saved high-water mark, so existing history is not sent on first launch.
- Detail levels Ping, Sender and Full, with Ping the default.
- One-time-code skipping on by default; a skipped row still advances the high-water mark.
- Webhook URL and auth header stored in the Keychain; a **Test webhook** button.
- Settings for poll interval, Show in Dock, and Launch at login (`SMAppService`), plus Skip missed / Catch up when re-enabling.
- A log file that never contains message text, and masked sender handles.
- A command-line dry run (`--dry-run --once --config …`) with `--show-text`, and an **Import config.json…** button in Settings.
