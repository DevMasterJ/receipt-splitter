# Receipt Splitter

Android app for splitting a bar or restaurant bill. Take a photo of the receipt, the app reads the items
on the phone (no internet, no account), you tap who had what, and it shows what everyone owes.
Friends can follow the bill live on their own phones by scanning a QR code.

Made for **Croatian receipts** (Croatian words, prices in euros). Receipts from other countries are read
poorly or not at all, but you can type items in by hand anywhere. See [Adapting it to your country](#adapting-it-to-your-country).

Website and privacy policy: <https://webmasterj.dev/receipt-splitter/>

## How it works

- **Reading receipts** (`lib/reader/`): PaddleOCR (PP-OCRv5 mobile detection + Latin recognition, ONNX Runtime)
  finds the text, `layout()` turns the text boxes into lines, and plain rules in `receipt_text_rules.dart` pick out
  the item rows (quantity × unit price = price), the total and discounts. No language model. A banner warns when
  the items don't add up to the receipt total.
- **Live bill** (`lib/live/`): the host phone runs a small HTTP/WebSocket server. Guests scan a QR code and see
  the bill in the app or in a browser (`assets/live/guest.html`), over the host's local-only hotspot or the same Wi-Fi.
  A random key in the QR code keeps others out.
- **QR scanning**: zxing-cpp via [flutter_zxing](https://pub.dev/packages/flutter_zxing), on the phone.
- **Data**: everything stays on the phone (SQLite) and is excluded from Android backups. Nothing is sent to
  any server; the app has no analytics or tracking libraries.

## Build

Needs Flutter (stable) and the Android SDK/NDK.

```sh
flutter test
flutter build apk --release           # direct install: adb install -r build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release     # Google Play
```

Release signing reads `android/key.properties` (not in git, see the Flutter docs on app signing). Without it
the build is signed with the debug key, which is fine for trying it out.

If you publish your own version, change the application ID (`dev.webmasterj.receiptsplitter` in
`android/app/build.gradle.kts`, the Kotlin package folder, `lib/live/live_server.dart` and `assets/live/guest.html`)
and the app name.

## Adapting it to your country

Most of the work is in the receipt rules; splitting, the live bill and the UI don't care about the country.

1. **Words on the receipt** – the patterns at the top of `lib/reader/receipt_text_rules.dart`: column headers
   (`_header`, `_headerCol`: *artikl, kol, količina, cijena, iznos* = item, qty, price, amount), the total line
   (`_total`: *ukupno, za platiti* = total, to pay), payment lines (`_pay`: *gotovina* = cash, *kartice* = cards),
   lines to ignore (`_skip`, `_taxHead`: *PDV* = VAT, *porez* = tax, and the fiscal codes *ZKI, JIR, OIB*),
   discounts (`_discountLine`) and bottle deposits (`_deposit`). Add your language's words next to them.
2. **OCR alphabet** – the bundled recognition model (`assets/ocr/rec.onnx` + `chars.txt`) is PaddleOCR's Latin
   model. For Cyrillic, Greek, Arabic etc. swap in the matching PP-OCR recognition model and its character list.
3. **Accent repair** – `lib/reader/croatian_words.dart` fixes Croatian words that receipt printers mangle
   (č/ć/š/ž/đ). Replace the word list with your own or drop it.
4. **Money** – prices are euros with a decimal comma (`parsePrice` in `lib/models/models.dart`, the `€` in the
   screens). Change the currency symbol and, if your receipts use a decimal point, check `parsePrice` and the
   number patterns in the rules.
5. **Tests** – `test/receipt_rules_sample_test.dart` has made-up Croatian receipts. Add a few typical receipts from
   your country (as OCR text) and adjust the rules until they pass.

## Licence

MIT, see [LICENSE](LICENSE). Third-party parts and their licences are listed in [NOTICE.md](NOTICE.md).
