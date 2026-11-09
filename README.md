# MANGACA — Android app (Flutter)

Read Beyond The Illusion. Manga, novels and classics with the iReader engine,
plus **full TV & movie streaming** — the app is the streaming surface: every
request (catalog, posters, streams, partner players) goes out from **your own
device and connection**, never from a shared server.

- Package: `app.orubus.mangaca`
- Live backend: same production runtime as the web app (`mangaca.pages.dev`)
- Identity: genjutsu passwordless — get a link code from [@orubus_bot](https://t.me/orubus_bot) (`/genjutsu`)
- Releases: signed APKs under [Releases](../../releases) (v0.0.1 is the first)

## Structure

```
lib/
  main.dart            app shell — top bar, bottom tabs, auth sheets
  api.dart             runtime client (session cookie, all /api endpoints)
  store.dart           on-device state (same shapes as the web app)
  fp.dart              device fingerprint for account binding
  sources.dart         the hidden extension layer (server + device-direct lanes)
  reader.dart          iReader engine — webtoon / paged LTR-RTL / text themes
  pages/               browse, tv, tv_show, details, library, updates,
                       history, more, legal, search
  player/
    vault_player.dart  native gesture player (double-tap seek, hold speed,
                       quality menu, fullscreen) for the in-house film lane
    embed_player.dart  partner-player WebView lane with SERVER 1/2/3 chips
android-overlay/       applied over the CI-generated android scaffold:
                       applicationId, signing config, manifest, launcher icons
```

## Build

CI does everything (`.github/workflows/release.yml`): scaffold android,
apply overlay, restore the signing keystore from Actions secrets, build the
release APK, publish it on a GitHub Release for the pushed tag.

The keystore and passwords live **only** in Actions secrets
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`)
— never in the repo.

## Fonts

Archivo Black, Space Grotesk and IBM Plex Mono — all SIL OFL 1.1
(see `assets/fonts/OFL.txt`).
