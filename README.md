# Pradakshina

Flutter app for GPS-assisted pradakshina counting, manual corrections, Hindi/English prayer reading and private session history.

Repository: [aeronixil/pradakshana_app](https://github.com/aeronixil/pradakshana_app).
Firebase Hosting project: `pradakshina-counter` (project number `1086978102641`).
The existing local checkout matches GitHub's original `main` commit `1c6137b`.

## Use

1. Optionally enter the temple name and a prayer/mantra. Choose a minimum loop distance slightly below your actual route length (80 m by default).
2. Begin a session, tap **Start GPS tracking**, and allow precise location. Wait for the start-point confirmation before walking.
3. Complete a loop and return within 10 m of the start. The count, timestamp, measured distance and duration are saved automatically.
4. Pause when taking a break; resume establishes a new start point. Finish saves the session in history. Manual +1 / −1 adjustments are recorded separately and reset any partial GPS loop to prevent counting it twice.

The app does not automatically activate location on launch. Tracking is explicitly started and can be stopped. Reopening an interrupted session restores counts in a paused state.

## Detection and limitations

`lib/lap_tracker.dart` is independent of the device GPS plugin and can be tested with recorded/simulated positions. A counted loop must have:

- Fresh, increasing timestamps and reported horizontal accuracy of 10 m or better.
- An excursion at least 25 m from the starting point, then a return within 10 m.
- At least the configured distance and 30 seconds of walking.
- Sufficient enclosed polygon area to reject ordinary out-and-back movement (at least 100 square metres and 1.5% of path length squared).

GPS jumps above 4.5 m/s and gaps over 20 seconds reset the partial loop. Stationary steps under 2 m do not accumulate distance. No-reading periods show a signal warning. Noisy stationary movement, incomplete loops, and ordinary out-and-back traces are covered by tests. These thresholds are conservative heuristics, not a guarantee: complex paths, multipath reflections and poor reception can still cause missed or incorrect counts. GPS cannot reliably resolve small indoor circuits. Use manual counting there.

Android uses a user-started foreground location service with a visible notification and wake lock. Start it while the app is visible. Device battery restrictions or force-stopping the app can interrupt tracking. Web and iOS tracking pauses when hidden and resumes only on request; keep the screen awake and page visible. Web location requires HTTPS or localhost. iOS needs a Mac/Xcode build and device validation before distribution. Other desktop targets have not been validated.

## Data

Counts, event timestamps, session names, prayers and completed-loop distance/duration are stored locally using `shared_preferences`, under `pradakshina.sessions.v1`. Raw coordinates are used only in memory; routes are not stored or uploaded. Firebase is used only for web hosting; no login or cloud database is required. History belongs to this device and browser origin, and is lost when app/browser data is cleared. Use one active browser tab. Preview and production URLs have separate storage. Writes are serialized and failures display a retry option. This is personal local history, not a backed-up record system.

## Development

Validated SDK: Flutter 3.29.3 / Dart 3.7.2. Android uses JDK 17, SDK 36, NDK 27.0.12077973, Gradle 8.11.1, AGP 8.9.1 and Kotlin 2.1.0. Keep the committed `pubspec.lock` for reproducible dependency resolution.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web --release --pwa-strategy=none
flutter build apk --debug
```

Windows needs Developer Mode for Flutter desktop plugin symlinks. If dependency resolution completed but symlink creation failed, Android/web builds and tests can use `--no-pub` with the resolved packages. Set `android/local.properties` to your SDK paths; it is ignored by Git.

The debug APK is for device testing. The inherited Android release configuration signs with a debug key; configure a private release keystore before store distribution.

## Firebase Hosting

`firebase.json` serves `build/web`, so deployment uses the current Flutter build instead of the old checked-in `public/` copy. The legacy folder is retained for reference and is not deployed.

```sh
firebase login
flutter build web --release --pwa-strategy=none
firebase hosting:channel:deploy gps-tracking --expires 30d --project pradakshina-counter
# Only when ready to replace the production site:
firebase deploy --only hosting --project pradakshina-counter
```

## Validation before production

Automated tests cover clockwise/anticlockwise circuits, stationary jitter, partial circuits, out-and-back paths, distance thresholds, bad/stale/duplicate fixes, jumps, signal gaps, permission denial, cancellation during permission requests, persistence/recovery, corrupt history and the narrow-phone manual workflow. Test the APK outdoors on an actual temple path against a manual count, including screen lock, permission revocation and battery-saving mode. Physical GPS and iOS builds cannot be validated by simulated tests alone.

Location integration follows the [Geolocator documentation](https://pub.dev/packages/geolocator/versions/13.0.4); local persistence uses [shared_preferences](https://pub.dev/packages/shared_preferences).
