# Pradakshina

Flutter app for GPS-assisted pradakshina counting, manual corrections, Hindi/English prayer reading and private session history.

Repository: [aeronixil/pradakshana_app](https://github.com/aeronixil/pradakshana_app).
Firebase Hosting project: `pradakshina-counter` (project number `1086978102641`).
The existing local checkout matches GitHub's original `main` commit `1c6137b`.

## Use

1. The full Hanuman Chalisa in Devanagari is prefilled in the large text box. Edit it or paste another prayer if desired. Temple name and minimum loop distance (80 m by default) are under **Place & loop settings**.
2. Tap **Read & start GPS** and allow precise location. Wait for the start-point confirmation before walking. **Read without GPS** opens the same reader without requesting location.
3. Complete a loop and return within 10 m of the start. The count, timestamp, measured distance and duration are saved automatically.
4. The count and GPS status remain above the full-height scrolling reading box. Use the text-size buttons, or **Edit** / **Done** to change the text; edits save in the session and GPS updates preserve the reading position. The app requests a screen wake lock while reading, where supported.
5. Both **pradakshinas** and **readings** have visible + / − controls. Manual pradakshina corrections reset any partial GPS loop to prevent counting it twice; reading corrections do not interrupt GPS.
6. Select **English meaning** in the reader for a complete plain-English translation, or **हिंदी** for the original. Custom prayers are preserved under **Your text**. English is a meaning translation, not a pronunciation guide.
7. Scroll from top to bottom to automatically count one reading. Scroll back to the top, or tap **Read again**, for another. Bottom bouncing, programmatic jumps, editing and language/font changes do not add a reading. The detector requires continuous progress and rejects jumps skipping more than 20% of the text. Short text that fits without scrolling needs a manual reading count. This estimates scrolling completion, not attention or actual recitation.
8. Tap **Insights** for **Summary**, **Paths** and **Timeline**. Summary shows session counts, elapsed time, recorded distance, average GPS loop duration, a seven-day graph and individual loop duration bars. Paths lets you select the whole session or one detected GPS loop and scrub through timestamped positions. Timeline separates GPS, scrolling and manual events. Finishing a session opens Insights automatically; saved sessions remain selectable.
9. Pause when taking a break; resume establishes a new start point. The top-right **Session controls** button has **Finish session**. Keep the page visible while walking.

The app does not automatically activate location on launch. Tracking is explicitly started and can be stopped. Reopening an interrupted session restores counts in a paused state.

Older unfinished sessions with an empty prayer receive the Hanuman Chalisa; existing custom text is preserved. The original hymn by Tulsidas is public-domain text, checked against [Sanskrit Documents](https://sanskritdocuments.org/doc_z_otherlang_hindi/chaalisa.html). The English meaning is an original rendering included with this app. A bundled Noto Sans Devanagari font keeps the Hindi reading independent of runtime font downloads; its SIL Open Font License is included in `assets/fonts/OFL.txt`.

## Detection and limitations

`lib/lap_tracker.dart` is independent of the device GPS plugin and can be tested with recorded/simulated positions. A counted loop must have:

- Fresh, increasing timestamps and reported horizontal accuracy of 10 m or better.
- An excursion at least 25 m from the starting point, then a return within 10 m.
- At least the configured distance and 30 seconds of walking.
- Sufficient enclosed polygon area to reject ordinary out-and-back movement (at least 100 square metres and 1.5% of path length squared).

GPS jumps above 4.5 m/s and gaps over 20 seconds reset the partial loop. Stationary steps under 2 m do not accumulate distance. No-reading periods show a signal warning. Noisy stationary movement, incomplete loops, and ordinary out-and-back traces are covered by tests. These thresholds are conservative heuristics, not a guarantee: complex paths, multipath reflections and poor reception can still cause missed or incorrect counts. GPS cannot reliably resolve small indoor circuits. Use manual counting there.

Android uses a user-started foreground location service with a visible notification and wake lock. Start it while the app is visible. Device battery restrictions or force-stopping the app can interrupt tracking. Web and iOS tracking pauses when hidden and resumes only on request; keep the screen awake and page visible. Web location requires HTTPS or localhost. iOS needs a Mac/Xcode build and device validation before distribution. Other desktop targets have not been validated.

## Data

Counts, reading events, timestamps, session names, prayers, completed-loop distance/duration and accepted GPS coordinates are stored locally using `shared_preferences`, under `pradakshina.sessions.v1`. Existing history is migrated with empty reading/path lists; older routes cannot be reconstructed. Paths record only fixes accepted by the same accuracy/freshness/movement filter as loop detection. Pauses, manual lap corrections, gaps and jumps start disconnected segments. Route distance excludes connections across those segments; elapsed session time includes pauses. Completed GPS detections remain in history even after a manual count correction.

Path snapshots are saved every five accepted fixes and on counts, pauses and finish; an abrupt browser/process exit can lose the last four unsaved points. A limit of 12,000 points across saved sessions bounds coordinate storage. At that limit counting continues and Paths displays a notice; **Remove saved path** frees coordinates while retaining counts/events. Storage failures are visible with a retry action. Clearing app/browser data removes history. Use one active tab. Preview and production URLs have separate storage. This is personal local history, not a backed-up record system.

Firebase is used only for web hosting; no login or cloud database is required, and saved paths are not uploaded. **Show map** explicitly loads OpenStreetMap tiles, whose requests reveal the viewed area to the tile service. No map tiles are requested from the reading screen or Summary. The map uses flutter_map 8.2.2's browser/native HTTP caching, a native app user-agent, visible linked attribution, and no tile prefetch/offline-download feature. Maps need internet; saved counts and coordinates remain local. See the [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/) and [flutter_map caching documentation](https://docs.fleaflet.dev/layers/tile-layer/caching).

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

Windows needs Developer Mode for Flutter desktop plugin symlinks. A failed `pub get` can leave stale plugin registrations even when packages downloaded successfully: complete dependency setup before building. On this workstation, setup completed with the unused Windows/Linux scaffolds temporarily relocated within the ignored `.local/` directory and then restored. Verify that generated Android/web registrants include Geolocator, shared preferences and Wakelock before using `--no-pub`. Flutter 3.29 may also need its generated `web_entrypoint.stamp` removed after adding a web plugin so the registrant is regenerated. Set `android/local.properties` to your SDK paths; it is ignored by Git.

The debug APK is for device testing. The inherited Android release configuration signs with a debug key; configure a private release keystore before store distribution.

## Firebase Hosting

`firebase.json` serves `build/web`, so deployment uses the current Flutter build instead of the old checked-in `public/` copy. The legacy folder is retained for reference and is not deployed.

The bootstrap is inlined into HTML, the JavaScript entrypoint uses Flutter's build fingerprint, and hosting assets must revalidate. This prevents a cached copy of the old counter from hiding an update after refresh.

```sh
firebase login
flutter build web --release --pwa-strategy=none
firebase hosting:channel:deploy gps-tracking --expires 30d --project pradakshina-counter
# Only when ready to replace the production site:
firebase deploy --only hosting --project pradakshina-counter
```

## Validation before production

The expanded suite has 28 tests, including repeated top-to-bottom reading gestures, no counts on programmatic scroll/language changes, independent manual counters, translation preservation, old-session migration, persisted coordinate timestamps, disconnected paths, map loop selection and the timestamp slider. Widget map tests use synthetic coordinates and disable network tiles. A separate ignored local demo verifies real map tiles without adding synthetic paths to production history.

Automated tests cover clockwise/anticlockwise circuits, stationary jitter, partial circuits, out-and-back paths, distance thresholds, bad/stale/duplicate fixes, jumps, signal gaps, permission denial, cancellation during permission requests, persistence/recovery, corrupt history and the narrow-phone manual workflow. Test the APK outdoors on an actual temple path against a manual count, including screen lock, permission revocation and battery-saving mode. Physical GPS and iOS builds cannot be validated by simulated tests alone.

Location integration follows the [Geolocator documentation](https://pub.dev/packages/geolocator/versions/13.0.4); local persistence uses [shared_preferences](https://pub.dev/packages/shared_preferences).
