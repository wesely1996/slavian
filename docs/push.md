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

### 2. App (needs the Firebase project first)

The app registers its push token with `POST /v1/me/devices`
`{ token, platform: "android" }`. Getting that token on Android needs:

1. In the same Firebase project, *Add app → Android*, package name
   `com.slavian.game`, then download `google-services.json`.
2. A Godot Firebase Cloud Messaging plugin built into the Android export,
   configured with that file.

Send me `google-services.json` (it is not secret; it ships inside the app)
and I'll wire the plugin into the client and the CI build.
