# iMessage Relay

macOS menu-bar app that watches Messages and POSTs each new incoming text to a webhook you choose. An AI agent on the other end can triage texts. The relay cannot send messages: it opens `~/Library/Messages/chat.db` read-only and has no send path.

It forwards iMessage, and SMS or RCS when those rows show up in the Mac’s Messages database (SMS arrives through Text Message Forwarding from an iPhone). Outgoing texts (`is_from_me != 0`) are ignored. Attachment file bytes are never read or uploaded.

## Requirements

- macOS 14 or later. The app’s minimum system version and the Swift package deployment target are both 14.
- A Mac that stays on and awake, signed into Messages. The relay only polls while the process is running. It does not wake the Mac.
- Xcode or the Xcode Command Line Tools, so `swift` and `codesign` are on `PATH`.
- Full Disk Access for `~/Applications/iMessage Relay.app`. Messages and Contacts live in protected folders. Without Full Disk Access the database open fails.

The webhook can be any `http` or `https` URL. Use HTTPS so the bearer token is not sent in the clear.

## Install

On the Mac that will run the relay:

```bash
git clone <repository-url>
cd <repository-directory>
./scripts/build-app.sh
./scripts/install-app.sh
```

`./scripts/build-app.sh` builds a Release binary, wraps it in `build/iMessage Relay.app`, and ad-hoc signs the bundle as `com.jamesalmeida.imessage-relay`.

`./scripts/install-app.sh` runs that build, copies the app to `~/Applications/iMessage Relay.app`, and opens it. It does not use `sudo`. Running the install script alone is enough; it calls the build script itself.

The first launch opens Settings when no webhook URL is stored yet.

### Full Disk Access

1. System Settings → Privacy & Security → Full Disk Access.
2. Click **+**, choose `~/Applications/iMessage Relay.app`, and turn the switch on. If the file picker hides the folder, press Shift-Command-G and enter that path.
3. Or click **Open Full Disk Access settings** in the app’s Settings window. That opens the same pane. You still add the app yourself.

An ad-hoc rebuild changes the signature cdhash. The bundle id stays `com.jamesalmeida.imessage-relay`, but macOS often drops the Full Disk Access grant. After `./scripts/install-app.sh` replaces the app, turn the switch on again. If the app is listed and the log still says the database is unreadable, remove the entry and add `~/Applications/iMessage Relay.app` again.

### Launch at login

**Launch at login** is on by default. The app registers itself with `SMAppService`. Turn it off in Settings if this Mac should not start the relay at login.

If registration fails, Settings shows: “Launch at login could not be changed. Install iMessage Relay.app in your Applications folder and try again.” The log line is `launch at login update failed`.

## Menu

The menu-bar icon is a filled bubble while status is Running, and a slashed bubble otherwise.

| Menu line | Meaning |
| --- | --- |
| Status: Running | The last finished batch read the database and had no webhook or state error. The first batch, which only records the high-water mark, counts. Later webhook retries leave the status here. |
| Status: Disabled | **Enabled** is off. Polling is paused. |
| Status: Not configured | No usable `http` or `https` webhook URL is in the Keychain. A launch that already has a high-water mark can also stay here while the first POST of this process is failing. The log line is `webhook failed`. |
| Status: Error: needs Full Disk Access | A webhook is saved, and `~/Library/Messages/chat.db` could not be opened. |
| Status: Error: already running | Another `imessage-relay` process holds the lock file. Quit the other copy. |
| Last forwarded | Time of the last HTTP success. No message content. `Last forwarded: never` until then. |
| Enabled | Pauses or resumes polling without quitting. |
| Detail level | Ping, Sender, or Full. |
| Skip one-time codes | On by default. |
| Settings… | Webhook, poll interval, re-enable behavior, Dock, login. |
| Open log | Opens the log file. |
| Quit | Stops polling and exits. Does not turn **Enabled** off. |

**Show in Dock** defaults to on. With it on, the process switches to a normal Dock app. Turn it off for a menu-bar-only agent. The bundle is marked as an agent (`LSUIElement`), and the process starts that way until this preference is applied.

## Webhook setup

Settings stores two Keychain items and nothing else about the endpoint:

| Keychain field | Value |
| --- | --- |
| Service | `com.jamesalmeida.imessage-relay` |
| Class | generic password |
| Accounts | `webhook_url`, `auth_header` |
| Accessibility | after first unlock |

Other settings are UserDefaults in the app domain `com.jamesalmeida.imessage-relay`. See [Defaults](#defaults).

The auth field accepts `Bearer <token>` or `Authorization: Bearer <token>`. A leading `Authorization:` is stripped, and the remainder is what is stored and later sent as the `Authorization` header. Leave the field empty to send no `Authorization` header; Save deletes that Keychain item.

**Save** writes the Keychain items. The poll loop reads the Keychain. **Test webhook** POSTs the URL and header currently in the form, including unsaved edits. A test does not change **Last forwarded**.

Every POST, including the test, is:

- Method `POST`
- `Content-Type: application/json`
- `User-Agent: imessage-relay`
- `Authorization` set only when a header value is present
- Success is any HTTP status from 200 through 299
- Request timeout 15 seconds

### Any HTTPS endpoint

Use an endpoint that expects a bearer token:

| Field | Example |
| --- | --- |
| Webhook URL | `https://example.com/hooks/messages` |
| Auth header | `Bearer replace-me` |

Paste those into Settings, click **Save**, leave **Enabled** on, then click **Test webhook**. A successful test shows `Test webhook returned HTTP 200.` (or another 2xx) in the Settings window. The test body is exactly:

```json
{"event":"test"}
```

That request is not written to the log.

Treat the URL as a secret if it contains a token in the query string. The URL is stored in the Keychain and is not written by the app’s log lines.

### Grok Bot routine

1. Create a Grok routine whose trigger is a webhook.
2. In the routine panel, copy the **Webhook URL** and the **Authorization** header.
3. Paste the URL into **Webhook URL** and the header into **Auth header**.
4. Click **Save**.
5. Leave **Enabled** on.
6. Click **Test webhook**. The routine receives `{"event":"test"}`. Confirm the HTTP status shown in Settings.

Do not paste the URL or the header into a chat, a commit, or a log.

### Optional config file

The menu-bar app does not read a config file on its own. **Import config.json…** loads a mode `600` (or stricter) JSON file into the form. You still click **Save** to put the URL and header in the Keychain. Import also applies `detail_level`, `skip_one_time_codes`, and `poll_seconds` from the file.

`config.example.json` is the shape. Copy it aside and `chmod 600` the copy. The default CLI path is `~/.config/imessage-relay/config.json`, or the path in `IMESSAGE_RELAY_CONFIG`.

```json
{
  "webhook_url": "https://example.com/hooks/messages",
  "auth_header": "Bearer replace-me",
  "poll_seconds": 3,
  "skip_one_time_codes": true,
  "detail_level": "ping"
}
```

`detail_level` is `ping`, `sender`, or `full`. `poll_seconds` must be greater than 0 and at most 86400. Omitted optionals use the defaults (ping, skip codes, 3 seconds).

## Payload reference

JSON keys are sorted. Unknown optional strings are omitted. Empty arrays are sent as `[]`. Dates are the message date in the Mac’s current time zone, `YYYY-MM-DDTHH:MM:SS±HH:MM`, with no fractional seconds. Messages stores that instant as seconds or nanoseconds since 2001-01-01 UTC; the relay converts it.

`service` is whatever Messages stored, commonly `iMessage`, `SMS`, or `RCS`.

A chat is a group when its style is 43 or it has more than one participant. If a message is linked to several chats, the relay prefers a group, then the chat with more participants, then the lowest chat row id. Participant handles are ordered by handle id. Contact names come from the local Address Book and are included only at Sender and Full. Ping does not read contacts. Names are refreshed at most every 10 minutes. If the Address Book cannot be read, the log records `contact names unavailable` once and `name` is omitted.

### `message.received` at `ping` (default)

Only the event, the detail level, and the message date leave the Mac:

```json
{"date":"2026-11-12T15:04:05-08:00","detail_level":"ping","event":"message.received"}
```

No sender, text, chat, attachment count, row id, or GUID.

### `message.received` at `sender`

Adds service, sender handle, contact name when one matches, chat display name, whether the chat is a group, and an attachment count. No text, attachment names, participants, row id, or GUIDs.

```json
{"attachment_count":1,"chat":{"is_group":false,"name":"Example Chat"},"date":"2026-11-12T15:04:05-08:00","detail_level":"sender","event":"message.received","sender":{"handle":"+15555550123","name":"Example Sender"},"service":"iMessage"}
```

With no contact name and no chat display name those keys are absent:

```json
{"attachment_count":0,"chat":{"is_group":true},"date":"2026-11-12T15:04:05-08:00","detail_level":"sender","event":"message.received","sender":{"handle":"person@example.com"},"service":"SMS"}
```

### `message.received` at `full`

Adds message text, attachment **file names** (the last path component of `transfer_name`, otherwise `filename`), chat GUID and identifier, participants, the message GUID, `rowid`, and `associated_message_type`.

```json
{"associated_message_type":0,"attachments":["photo.jpg"],"chat":{"guid":"example-chat-guid","identifier":"example-chat-id","is_group":true,"name":"Example Chat","participants":[{"handle":"+15555550123","name":"Example Sender"},{"handle":"person@example.com"}]},"date":"2026-11-12T15:04:05-08:00","detail_level":"full","event":"message.received","guid":"example-message-guid","rowid":12004,"sender":{"handle":"+15555550123","name":"Example Sender"},"service":"SMS","text":"Running late. Can you reply?"}
```

`associated_message_type` is copied from Messages. `0` is a normal message. A non-zero value is an associated item, usually a tapback. The relay does not drop those rows. The receiver can ignore them.

`text` is the `text` column, or the decoded attributed body when `text` is empty. When both are empty, `text` is omitted.

### Test event

```json
{"event":"test"}
```

This body is a fixed string. It has no `detail_level` and no date. It is not written to `relay.log`.

### Starting point and duplicates

The high-water mark is `last_rowid` in:

```text
~/Library/Application Support/imessage-relay/state.json
```

```json
{
  "last_rowid" : 12003
}
```

The file mode is `600`. The directory mode is `700`.

On the first batch with no state file, the relay sets `last_rowid` to `MAX(ROWID)` across the whole `message` table and does not POST existing history. The log line is `initialized high-water to N; history will not be forwarded`. The menu can already say Running. Only later rows are candidates, and only incoming ones (`is_from_me = 0` and `ROWID` greater than the mark).

That first batch happens when a webhook URL is saved, **Enabled** is on, and the database is readable. Launching the app before it is configured does not create the mark.

A posted row and a skipped one-time code both advance `last_rowid` before the next row. After a restart the relay loads the file and continues after that id, so a delivered row is not sent again.

A failed POST does not advance the mark past that row. The same payload is retried. If the POST succeeded but the state file could not be saved, the next batch saves that id before posting anything else (`saved high-water rowid=N after earlier delivery`), so the message is not posted twice.

Changing detail level does not rewind the mark. Rows already passed are not sent again at the new level.

A corrupt `state.json` is not reset. The log reports `state file is corrupt at <path>; refusing to reset it.` Restore `last_rowid` from a `rowid=` line in the log, or delete the file only if skipping every message already in `chat.db` is acceptable. Deleting it causes the next batch to initialize at the current maximum again.

### Re-enable: skip missed or catch up

This choice applies only when **Enabled** is turned back on. It does not apply to Quit.

| Setting | Default | What happens |
| --- | --- | --- |
| Skip missed | yes | The mark moves to the current maximum `ROWID` if that is ahead of the saved mark. Texts that arrived while the relay was paused are not sent. The mark never moves backward. Log: `re-enabled; high-water set to N`. |
| Catch up | | The saved mark is left alone, so texts that arrived while the relay was paused are forwarded. Log: `re-enabled; resuming from the saved high-water mark`. If no state file exists yet, the following batch still initializes the mark at the current maximum. |

Quit leaves the saved mark and the **Enabled** flag untouched. The next launch resumes from `last_rowid`, so texts that arrived while the app was not running are forwarded even when Skip missed is selected.

If Skip missed cannot read the database, the mark is left unchanged and the log says so.

### Retries

A non-2xx status, a network error, or a timeout keeps the mark at the last successful row. The log line is:

```text
webhook failed rowid=N attempt=1 status=401
webhook failed rowid=N attempt=2 error=network
webhook failed rowid=N attempt=3 error=timeout
```

The next wait is 1, 2, 4, 8, 16, 32, 64, 128, 256 seconds, then 300 seconds for every later attempt. The menu does not gain a separate “webhook failed” status. Before the first fully successful batch it stays **Not configured**. After a success it stays **Running** during retries.

A state-file failure is logged as `state save failed rowid=N attempt=A error=state` and uses the same delays.

Polling after a clean batch waits **Poll seconds** (default 3, stepper 1–3600). Each batch reads up to 50 incoming rows.

### One-time codes

**Skip one-time codes** is on by default and applies at every detail level, including ping. The text is read on the Mac to make the decision. A skipped row is not POSTed. The mark still advances. The only log line is `skipped otp rowid=N`.

Turn the menu item off to forward those rows. With the filter off, a database OTP flag does not skip the row either.

Detection is either of:

1. **Database flag.** If the `message` table has a column whose name looks like a one-time-code indicator and the value is non-zero, the row is skipped. Matching names contain `otp`, `one_time`, `onetime`, `verification_code`, `verify_code`, `2fa`, `two_factor`, or `passcode`. Names containing `not_otp`, `no_otp`, or `non_otp` do not match. `is_spam`, `schedule_type`, `schedule_state`, `is_auto_reply`, `is_system_message`, `is_service_message`, and `expressive_send_style_id` are not OTP flags.
2. **Text.** A 4–8 digit token, or a token shaped like `G-123456` (one letter, a hyphen, then 4–8 digits), with at most 80 characters between it and a keyword. Keywords are code, verification, verify, passcode, otp, login, authentication, confirm, 2fa, one-time, one time, security code, sign-in, sign in, “do not share”, “don't share”, and “is your”. Phone numbers, clock times, money amounts, street addresses, and dates are blanked before the code search, so those numbers do not count. A code with no nearby keyword is forwarded. A keyword with no 4–8 digit or letter-hyphen-digit token is forwarded.

## Privacy and security

What leaves the Mac, besides the HTTP headers above:

| Detail level | Sent |
| --- | --- |
| Ping (default) | `event`, `detail_level`, message `date` |
| Sender | Ping fields, plus `service`, sender `handle` and contact `name`, chat `name`, `is_group`, `attachment_count` |
| Full | Sender fields, plus `text`, attachment file names, chat `guid` and `identifier`, participants, message `guid`, `rowid`, `associated_message_type` |

Ping is the default so a text body stays on the Mac. The webhook only learns that a message arrived and when. An agent that needs the body reads Messages on that Mac, with its own Full Disk Access. Sender and Full put more of the conversation on the wire. You are sending that data to whatever URL you saved. Protect that endpoint.

The database is opened with `file:…?mode=ro`, `SQLITE_OPEN_READONLY`, and `PRAGMA query_only = ON`. The relay never writes `chat.db` and never sends a text.

Message text, sender names, chat names, attachment names, and handles are untrusted input. A sender can put instructions in a text. The receiving agent must treat payload fields as data, not as orders, and must not send messages. See [AGENTS.md](AGENTS.md).

Logs never contain message text. A delivery line looks like:

```text
rowid=12004 service=iMessage is_group=false sender=***0123 status=200
```

Handles are masked to the last four digits when the handle has at least four digits, otherwise to the last four characters, otherwise `***`. Any log message containing `bearer ` (any case) is dropped and not written. The webhook URL and the auth header are not logged. Test-webhook results stay in the Settings window.

### Rotate the key

1. Regenerate the webhook secret in the receiver (for a Grok routine, use the routine panel).
2. Paste the new URL and the new Authorization value into Settings.
3. Click **Save**. Save overwrites the Keychain items.

Until Save, the poll loop keeps using the previous secret. Send a new text after Save, or click **Test webhook**, to confirm the receiver accepts the new value.

## Troubleshooting

Log:

```bash
tail -f ~/Library/Logs/imessage-relay/relay.log
```

State:

```text
~/Library/Application Support/imessage-relay/state.json
```

Lock file, same folder: `relay.lock`.

| What you see | What it means |
| --- | --- |
| `database unreadable; Full Disk Access is required` | Grant Full Disk Access to the installed app, then wait for the next poll. Settings shows **Needs Full Disk Access** next to the database path until the open succeeds (**Readable**). |
| Status: Not configured, and the log has no `webhook settings saved` | Click **Save**. The poll loop reads the Keychain. |
| Status: Not configured, log has `webhook failed … status=401` or `status=403` | The receiver rejected the Authorization value. Paste the current header and Save. |
| `webhook failed … status=404` or any other non-2xx | The URL is wrong or the endpoint is down. The mark does not move. Fix the URL and Save. The same row is retried. |
| `error=network` or `error=timeout` | The host was unreachable or slower than the 15 second request timeout. The relay keeps retrying. |
| `initialized high-water to N` and no `rowid=` line | Expected on first configuration. History stays on the Mac. Send a new text from a different sender. Messages this account sent, from this Mac or another device, stay local. |
| `skipped otp rowid=N` | The one-time-code filter dropped it. Turn **Skip one-time codes** off to forward those. |
| Status: Error: already running | Quit the other menu-bar app or CLI process, then open this copy again. |
| `state file is corrupt` | Do not expect the app to recreate a fresh mark over the bad file. See [Starting point and duplicates](#starting-point-and-duplicates). |
| Launch at login failed | Confirm the app is `~/Applications/iMessage Relay.app` and toggle the setting again. |

### Pause, stop, uninstall

- **Pause:** turn **Enabled** off. The log says `paused`. The process stays open. Turning it back on uses Skip missed or Catch up.
- **Stop:** **Quit**. The log says `stopping`. The next launch follows the saved **Enabled** flag and the saved high-water mark.
- **Uninstall:**
  1. Turn off **Launch at login**.
  2. **Quit**.
  3. Delete `~/Applications/iMessage Relay.app`.

The support folder, `relay.log`, and the Keychain items are left behind. Delete the two folders if you want the mark and the log gone. In Keychain Access, remove the generic-password items whose service is `com.jamesalmeida.imessage-relay`.

## Command-line debug

The same binary can drain once without the menu bar. It reads a mode `600` config file instead of the Keychain.

```bash
./build/iMessage\ Relay.app/Contents/MacOS/imessage-relay --help
./build/iMessage\ Relay.app/Contents/MacOS/imessage-relay --dry-run --once --config /path/to/config.json
```

`--dry-run` prints payloads and does not POST or update state. Message text is replaced with `[redacted]` unless you also pass `--show-text`. `--show-text` still does not write text to the log. `--backfill N` is CLI-only: it starts far enough back to include the last N incoming rows, once per process, and only moves the mark backward when that start is behind the saved mark. The Settings window has no backfill control. `--once` exits after the pending rows.

There is no send flag.

## Defaults

| Setting | UserDefaults key | Default |
| --- | --- | --- |
| Enabled | `enabled` | on |
| Detail level | `detailLevel` | `ping` |
| Skip one-time codes | `skipOneTimeCodes` | on |
| Poll seconds | `pollSeconds` | `3` (values outside 0–86400 fall back to 3; the stepper is 1–3600) |
| Show in Dock | `showInDock` | on |
| Launch at login | `launchAtLogin` | on |
| When re-enabled | `reenableBehavior` | `skipMissed` (`catchUp` is the other value) |
| Last forwarded | `lastForwardedAt` | unset until a POST succeeds |

## Development

Core behavior (dates, attributed-body fallback, phone normalization, config permissions, auth-header parsing, OTP detection, payloads, high-water behavior) is covered by:

```bash
swift test
swift build -c release
```

The SwiftUI app, Keychain, Full Disk Access, and `SMAppService` are macOS-only. `swift test` on Linux does not launch the app.

An agent that is setting the relay up for someone should follow [AGENTS.md](AGENTS.md).
