# LocalCast (Flutter 2.1.0-12.2.pre compatible port)

Same app, same functionality, same security model as the current-Flutter
version — cross-platform PC/mobile media sharing over WiFi with HTTPS,
certificate pinning, and PIN/QR pairing. This version is adjusted to build
against **Flutter 2.1.0-12.2.pre**, a pre-release build from early 2021,
which predates a number of APIs the newer version used.

## ⚠️ Read this first — uncertainty is higher here than usual

The original version already had one flagged uncertain file
(`cert_service.dart`, since I can't compile-check anything in this
sandbox). Porting to a specific ~4-year-old pre-release build compounds
that: I'm working from memory of what package APIs looked like at a
specific point in time, across *several* packages, not just one. I'm
confident in the overall approach; I'm much less certain that every exact
version constraint below is precisely right for `2.1.0-12.2.pre`'s bundled
Dart SDK. Treat the version ranges in `pubspec.yaml` as informed starting
points, and let `flutter pub get`'s solver do the real work of finding
what's actually compatible — it will refuse any package version that
declares a newer minimum SDK than what you have installed.

If you hit a resolution failure, the fix is almost always: loosen or lower
that one package's constraint, not restructure the code.

## What changed from the current-Flutter version, and why

| Area | Current-Flutter version | This version | Why |
|---|---|---|---|
| Theme | `useMaterial3: true`, `colorSchemeSeed` | Plain `ThemeData(primarySwatch: ...)` | Material 3 support didn't exist yet |
| Buttons | `FilledButton` / `FilledButton.icon` | `ElevatedButton` / `ElevatedButton.icon` | `FilledButton` is a Material 3 widget, added later |
| Widget `key` param | `const Foo({super.key})` | `const Foo({Key? key}) : super(key: key)` | The `super.key` shorthand needs Dart 2.17+; this targets 2.12 |
| QR code display | `qr_flutter` v4 `QrImageView` | `qr_flutter` v3.x `QrImage` | v4 renamed the widget; pinned `qr_flutter: '>=3.0.1 <4.0.0'` to keep the old name |
| QR code scanning | `mobile_scanner` | `qr_code_scanner` (`QRView`/`QRViewController`) | `mobile_scanner` didn't exist yet in this window |
| Video source | `VideoPlayerController.networkUrl(Uri)` | `VideoPlayerController.network(String)` | The `Uri`-based constructor came later; the `String` one was standard then |
| Icons | `Icons.podcasts`, `Icons.wifi_tethering_off`, `Icons.play_circle` | `Icons.cast`, `Icons.power_settings_new`, `Icons.play_circle_filled` | Swapped for icons I'm confident predate this era, rather than risk a missing-icon build error |
| Lints | `flutter_lints` | *(omitted)* | `flutter_lints` wasn't published yet; add `pedantic` yourself if you want linting |

Everything else — `dart:io` `HttpServer`/`SecurityContext`/`HttpClient`
usage, the folder scanner, the relay server, the pairing/pinning logic —
is unchanged, since `dart:io` has been stable for this whole span.

## Building it

```bash
flutter --version   # confirm you're actually on 2.1.0-12.2.pre or close to it
flutter pub get
flutter analyze
flutter run
```

If `flutter pub get` can't resolve one of the pinned ranges in
`pubspec.yaml`, that package's actual release history around early 2021 is
the thing to check (its pub.dev "Versions" tab, filtered to that date) —
adjust just that one line, not the surrounding code.

## Everything else

Security model, project layout rationale, the local-relay explanation for
why native video/audio players can't use certificate pinning directly, and
the known limitations (Android scoped storage, no transcoding, PIN-based
access) are all identical to the current-Flutter version — see that
version's README for the full writeup; nothing about the *design*
changed here, only which APIs implement it.
