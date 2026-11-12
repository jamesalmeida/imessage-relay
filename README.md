# iMessage Relay

Menu-bar app for macOS that forwards **new incoming** Messages (iMessage, SMS, and RCS) to a webhook you choose. It works with any HTTPS endpoint, for example a Grok Bot routine webhook.

The app never sends texts and never writes to `chat.db`.

## Privacy

- `~/Library/Messages/chat.db` is opened read-only (`file:…?mode=ro`, `SQLITE_OPEN_READONLY`, `PRAGMA query_only`).
- Only rows with `is_from_me = 0` and `ROWID` above the saved high-water mark are considered.
- The first launch sets that mark to the current maximum `ROWID`, so existing history is not sent.
- Attachment **names** can be included at detail level Full. File bytes are never read or uploaded.
- One-time codes are skipped by default. A skipped row still advances the high-water mark and is logged only as `skipped otp rowid=N`.
- Logs do not contain message text. Sender handles are masked to the last four digits. The webhook URL and auth header are not logged.
- The webhook URL and auth header live in the Keychain (`com.jamesalmeida.imessage-relay`). Other settings live in UserDefaults.
- Default detail level is **Ping**, which posts only the event name, the date, and the detail level.

You are sending message metadata, and at Full level the message text, to whatever URL you configure. Protect that endpoint.

## Install

On the Mac that will run the app (Apple silicon, macOS 14 or later, Xcode / `swift` available):

```bash
./scripts/install-app.sh
```

That builds `build/iMessage Relay.app`, ad-hoc signs it as `com.jamesalmeida.imessage-relay`, copies it to `~/Applications`, and opens it. No sudo.

To build without installing:

```bash
./scripts/build-app.sh
```

## Full Disk Access

The app cannot see Messages until macOS allows it.

1. System Settings → Privacy & Security → Full Disk Access.
2. Click **+** and choose `~/Applications/iMessage Relay.app`. If the file picker hides it, press Shift-Command-G and enter that path.
3. Turn the switch on.

Or use **Open Full Disk Access settings** in the app’s Settings window.

Rebuilding changes the ad-hoc signature’s cdhash. The bundle id stays `com.jamesalmeida.imessage-relay`, but macOS often drops the Full Disk Access grant after a rebuild. Turn the switch on again for the new copy.

## Use

The menu-bar icon is a filled bubble while the relay is running and a dimmed slashed bubble otherwise.

| Menu item | What it does |
| --- | --- |
| Status | Running, Disabled, Not configured, Error: needs Full Disk Access, or Error: already running |
| Last forwarded | Time of the last successful POST. No message content. |
| Enabled | Pauses or resumes polling without quitting. |
| Detail level | Ping, Sender, or Full. |
| Skip one-time codes | On by default. |
| Settings… | Webhook, poll interval, dock, and login. |
| Open log | Opens the log file. |
| Quit | Stops polling and exits. |

In Settings, enter the webhook URL and an optional auth header (`Bearer …` or `Authorization: Bearer …`). **Save** stores both in the Keychain. **Test webhook** POSTs `{"event":"test"}` and shows the HTTP status. Nothing from that request is written to the log.

**Show in Dock** switches the process between a menu-bar-only agent and a normal Dock app. The default is menu-bar only.

**Launch at login** uses `SMAppService` and is on by default.

### When you turn Enabled back on

- **Skip missed** (default) sets the high-water mark to the current maximum `ROWID`. Texts that arrived while the relay was paused are not sent.
- **Catch up** leaves the saved mark alone, so those texts are forwarded.

Quitting is different. The next launch resumes from the saved mark, so messages that arrived while the app was not running are forwarded. The skip/catch choice applies only to the Enabled switch.

A failed POST is retried with backoff. The mark does not move past that message.

### Detail levels

Every payload includes `detail_level`.

**Ping** (default):

```json
{"event":"message.received","date":"2026-11-12T10:00:00-08:00","detail_level":"ping"}
```

**Sender** adds `service`, `sender` (`handle`, `name`), `chat` (`name`, `is_group`), and `attachment_count`. It does not include text, attachment names, participants, row ids, or GUIDs.

**Full** adds the chat GUID and identifier, participants, text, attachment names, the message GUID, `rowid`, and `associated_message_type`. A non-zero associated type is usually a tapback; the receiver can ignore it. Group chats are style 43 or more than one participant.

One-time-code skipping applies at every level. The detector looks for a 4–8 digit token, or a token like `G-123456`, near words such as code, verification, OTP, or “do not share”. If a future Messages database has a real OTP column, a non-zero value is skipped too. `is_spam`, `schedule_type`, and `is_auto_reply` are not treated as OTP flags.

## Logs, state, and stop

Log file:

```bash
tail -f ~/Library/Logs/imessage-relay/relay.log
```

High-water mark:

```text
~/Library/Application Support/imessage-relay/state.json
```

Stop the relay from the menu with **Quit**, or turn **Enabled** off to pause without quitting.

To uninstall:

1. Turn off **Launch at login**.
2. **Quit**.
3. Delete `~/Applications/iMessage Relay.app`.

The support folder, the log, and the Keychain items (service `com.jamesalmeida.imessage-relay`) are left in place. Delete those yourself if you want them gone. Keychain Access can remove the generic password items for that service.

## Command-line debug

The same binary can drain once without opening the menu bar. Point it at a mode-600 JSON file if you do not want the app’s Keychain item. `config.example.json` shows the shape. An optional **Import config.json…** button in Settings fills the form from a file like that; you still press Save to put the secrets in the Keychain.

```bash
./build/iMessage\ Relay.app/Contents/MacOS/imessage-relay --help
./build/iMessage\ Relay.app/Contents/MacOS/imessage-relay --dry-run --once --config /path/to/config.json
```

`--show-text` prints message text in a dry run. It still does not write text to the log.

## Development

Core logic (dates, attributed-body fallback, phone normalization, config permissions, auth-header parsing, OTP detection, payloads, high-water behavior) is covered by:

```bash
swift test
swift build -c release
```

The SwiftUI app, Keychain, Full Disk Access, and `SMAppService` are macOS-only. `swift test` on Linux does not launch the app.
