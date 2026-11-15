import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import '../reader/paddle_ocr.dart';

/// Eval: PaddleOCR on every image in BASE/ocr_in -> BASE/ocr_paddle/NAME.json + _log.txt
/// (scored on the PC by the author's evaluation scripts). Runs in a background isolate.
List<String> paddleEvalAll(String base, {int threads = 4, int batch = 8, bool xnnpack = false}) {
  final sw = Stopwatch()..start();
  final ocr = PaddleOcr.load('$base/ocr_models', threads: threads, batch: batch, xnnpack: xnnpack);
  final log = ['threads $threads batch $batch xnnpack $xnnpack', 'models loaded in ${sw.elapsedMilliseconds} ms'];
  final outDir = Directory('$base/ocr_paddle');
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  outDir.createSync();
  final files = Directory('$base/ocr_in').listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final t = Stopwatch()..start();
    final im = img.decodeJpg(f.readAsBytesSync())!;
    final decode = t.elapsedMilliseconds;
    final (boxes, txts, scores) = ocr.readOriented(im);
    final name = f.uri.pathSegments.last.split('.').first;
    File('${outDir.path}/$name.json').writeAsStringSync(
      jsonEncode({'boxes': boxes, 'txts': txts, 'scores': scores, 'secs': t.elapsedMilliseconds / 1000, 'rot': 0}),
    );
    log.add('$name: ${txts.length} boxes, ${t.elapsedMilliseconds} ms (decode $decode, ${ocr.timing})');
  }
  ocr.close();
  File('${outDir.path}/_log.txt').writeAsStringSync(log.join('\n'));
  return log;
}
