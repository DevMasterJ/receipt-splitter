import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:convert';

import '../reader/ocr_rules_reader.dart';
import 'paddle_eval.dart';

/// Debug only: lets the PC start an eval run without touching the phone (adb can't unlock it).
/// `adb ... run-as <pkg> sh -c 'echo paddle > EXT/eval_trigger'` then `am start` the app.
/// The result lands in EXT/ocr_paddle (+ _log.txt); the trigger is deleted first so it runs once.
Future<void> runEvalTrigger() async {
  if (!kDebugMode) return;
  final base = (await getExternalStorageDirectory())?.path;
  if (base == null) return;
  final f = File('$base/eval_trigger');
  if (!f.existsSync()) return;
  final what = f.readAsStringSync().trim();
  f.deleteSync();
  if (what == 'rules') {
    // the app's quick reader end to end (asset models, decode, OCR, layout, rules) -> EXT/rules_out/NAME.json
    final dir = await OcrRulesReader.modelDirForEval();
    await Isolate.run(() => _rulesAll(base, dir));
  }
  if (what.startsWith('paddle')) {
    // "paddle" or "paddle:THREADS:BATCH:xnn"
    final a = what.split(':');
    final threads = a.length > 1 ? int.parse(a[1]) : 4, batch = a.length > 2 ? int.parse(a[2]) : 8;
    final xnn = a.length > 3 && a[3] == 'xnn';
    try {
      await Isolate.run(() => paddleEvalAll(base, threads: threads, batch: batch, xnnpack: xnn));
    } catch (e) {
      File('$base/ocr_paddle_error.txt').writeAsStringSync('$e');
    }
  }
}

void _rulesAll(String base, String modelDir) {
  final out = Directory('$base/rules_out');
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync();
  final log = <String>[];
  final files = Directory('$base/ocr_in').listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final sw = Stopwatch()..start();
    final name = f.uri.pathSegments.last.split('.').first;
    try {
      final r = OcrRulesReader.readFile(modelDir, f.path);
      File('${out.path}/$name.json').writeAsStringSync(
        jsonEncode({
          'store': '',
          'items': [
            for (final i in r.items) {'name': i.name, 'qty': i.qty, 'unit_price': i.unitPrice, 'price': i.price},
          ],
          'discounts': [
            for (final d in r.discounts) {'name': d.name, 'amount': d.amount},
          ],
          'total': r.total,
          'secs': sw.elapsedMilliseconds / 1000,
        }),
      );
      log.add('$name ${sw.elapsedMilliseconds} ms adds=${r.adds}');
    } catch (e) {
      log.add('$name ERROR $e');
    }
  }
  File('${out.path}/_log.txt').writeAsStringSync(log.join('\n'));
}
