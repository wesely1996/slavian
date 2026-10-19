# Push notifications

The server decides what to tell each player and when:

- **Pushed to the phone** (outside the player's quiet hours): a horde due at
  your village within 6 game hours, a battle at your village, a burned
  outpost, an Elder's Hall level or any building reaching level 5, and the
  daily digest itself.
- **Daily digest** at the player's digest hour (18:00 by default): builds
  finished, research done, battle results, deliveries from allies, settlers
  and hero news, summed up in one message.

Everything also lands in the in-app **Inbox** (top bar), with quiet hours and
the digest hour under its Settings. Without Firebase the inbox is all there
is; the server logs `Push notifications: off` at startup.

## Turning on pushes

Pushes go through **Firebase Cloud Messaging** (free). Two halves:

### 1. Server (ready now)

1. In the [Firebase console](https://console.firebase.google.com), create a
   project (Analytics not needed).
2. *Project settings → Service accounts → Generate new private key*. This
   downloads a JSON file. Keep it private.
3. Give it to the server, either as the whole JSON in `FCM_SERVICE_ACCOUNT`,
   or as a file path in `FCM_SERVICE_ACCOUNT_FILE`. For the playtest
   setup: save it as `ops/playtest/fcm.json` (git-ignored), uncomment the
   `volumes` lines in `ops/playtest/docker-compose.yml`, and add to `.env`:
   ```
   FCM_SERVICE_ACCOUNT_FILE=/run/secrets/fcm.json
   ```
4. Restart the server. It logs `Push notifications: Firebase Cloud Messaging`.

### 2. App

The app registers its push token with `POST /v1/me/devices`
`{ token, platform: "android" }` (`client/scripts/net/push.gd`, after login).
Android exports use the [godot-x/firebase](https://github.com/godot-x/firebase)
plugin (release 1.8.0, built for Godot 4.5) with Gradle builds:

- `client/google-services.json` is the Firebase Android app config for
  `com.slavian.game`. It is not secret; it ships inside the app.
- `ops/ci/setup-firebase-android.sh` downloads the plugin (checksum-pinned),
  enables it, installs Godot's Gradle template and adds the Google Services
  plugin. `ops/export-android.sh` runs it, so CI and local exports match. All
  it creates is git-ignored.
- Without the plugin (editor, desktop, tests) `Push` does nothing.
