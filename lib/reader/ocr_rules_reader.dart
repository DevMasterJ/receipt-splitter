import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'paddle_ocr.dart';
import 'receipt_reader.dart';
import 'receipt_text_rules.dart';

/// Fast reader without a language model (Photomath-style): PaddleOCR (12.7 MB, bundled) finds the text,
/// [parseReceiptText] turns it into items. ~1–4 s on the phone CPU, no heat.
/// The review screen checks the sum against the receipt total.
class OcrRulesReader implements ReceiptReader {
  @override
  String get name => 'Quick reader';

  @override
  Future<bool> isAvailable() async => true;

  static const _assets = ['det.onnx', 'rec.onnx', 'chars.txt'];

  static Future<String> modelDirForEval() => _modelDir();

  /// The isolate can't read assets, so copy the models to a folder once (per app version).
  static Future<String> _modelDir() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'ocr'));
    for (final a in _assets) {
      final f = File(p.join(dir.path, a));
      final data = await rootBundle.load('assets/ocr/$a');
      if (f.existsSync() && f.lengthSync() == data.lengthInBytes) continue;
      dir.createSync(recursive: true);
      f.writeAsBytesSync(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    return dir.path;
  }

  @override
  Stream<ReaderEvent> read(String imagePath) async* {
    yield const ReaderProgress('Reading text…');
    final dir = await _modelDir();
    final r = await _readInIsolate(dir, imagePath);
    for (final it in r.items) {
      yield ReaderItem(ParsedItem(name: it.name, qty: it.qty, unitPrice: it.unitPrice, price: it.price));
    }
    for (final d in r.discounts) {
      yield ReaderDiscount(d.name, d.amount);
    }
    if (r.total != null) yield ReaderTotal(r.total!);
  }

  // static so the closure doesn't capture anything unsendable
  static Future<TextReceipt> _readInIsolate(String dir, String path) => Isolate.run(() => readFile(dir, path));

  /// OCR + rules on one image file (also used by the eval).
  static TextReceipt readFile(String dir, String path) {
    final ocr = PaddleOcr.load(dir);
    try {
      final im = img.decodeImage(File(path).readAsBytesSync());
      if (im == null) throw Exception('Cannot open the photo');
      final (boxes, txts, _) = ocr.readOriented(img.bakeOrientation(im));
      return parseReceiptText(layout([for (var i = 0; i < boxes.length; i++) OcrBox(boxes[i], txts[i])]));
    } finally {
      ocr.close();
    }
  }
}
