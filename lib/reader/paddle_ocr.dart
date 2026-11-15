import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

/// Minimal PaddleOCR (PP-OCRv5 mobile det + latin rec, ONNX), same steps as the author's Python prototype:
/// axis-aligned boxes from connected components of the detection map, one crop per recognition run.
/// Models ship in assets/ocr and are copied to the app's files on first use (OcrRulesReader).
class PaddleOcr {
  final OrtSession _det, _rec;
  final List<String> _chars;

  /// Lines per recognition run.
  final int batch;

  PaddleOcr._(this._det, this._rec, this._chars, this.batch);

  /// [dir] holds det.onnx, rec.onnx and chars.txt (one character per line).
  static PaddleOcr load(String dir, {int threads = 4, int batch = 8, bool xnnpack = false}) {
    OrtEnv.instance.init();
    final o = OrtSessionOptions()..setIntraOpNumThreads(threads);
    if (xnnpack) o.appendXnnpackProvider();
    final det = OrtSession.fromFile(File('$dir/det.onnx'), o);
    final rec = OrtSession.fromFile(File('$dir/rec.onnx'), o);
    final chars = File('$dir/chars.txt').readAsStringSync().split('\n');
    if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
    return PaddleOcr._(det, rec, [...chars, ' '], batch);
  }

  void close() {
    _det.release();
    _rec.release();
  }

  static Float32List _norm(img.Image im) {
    final w = im.width, h = im.height, px = im.getBytes(order: img.ChannelOrder.rgb);
    final out = Float32List(3 * w * h);
    for (var i = 0; i < w * h; i++) {
      for (var c = 0; c < 3; c++) {
        out[c * w * h + i] = px[i * 3 + c] / 127.5 - 1;
      }
    }
    return out;
  }

  /// The package's tensor API boxes every number into Dart lists (seconds for a 3 MP map); these two helpers
  /// copy straight from/to native memory instead.
  static OrtValueTensor _tensor(Float32List data, List<int> shape) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final dataPtr = calloc<ffi.Float>(data.length)..asTypedList(data.length).setAll(0, data);
    final shapePtr = calloc<ffi.Int64>(shape.length)..asTypedList(shape.length).setAll(0, shape);
    final infoPP = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
    final outPP = calloc<ffi.Pointer<bg.OrtValue>>();
    try {
      _check(
        api.AllocatorGetInfo.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtAllocator>, ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)
        >()(OrtAllocator.instance.ptr, infoPP),
      );
      _check(
        api.CreateTensorWithDataAsOrtValue.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtMemoryInfo>,
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<ffi.Int64>,
            int,
            int,
            ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
          )
        >()(
          infoPP.value,
          dataPtr.cast(),
          data.length * 4,
          shapePtr,
          shape.length,
          ONNXTensorElementDataType.float.value,
          outPP,
        ),
      );
      return OrtValueTensor(outPP.value, dataPtr.cast()); // release() frees dataPtr
    } finally {
      calloc.free(shapePtr);
      calloc.free(infoPP);
      calloc.free(outPP);
    }
  }

  static void _check(bg.OrtStatusPtr st) {
    if (st != ffi.nullptr) throw Exception('onnxruntime error');
  }

  /// Copy of a float output tensor + its shape.
  static (Float32List, List<int>) _floats(OrtValue v) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final infoPP = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    final nP = calloc<ffi.Size>();
    final dataPP = calloc<ffi.Pointer<ffi.Void>>();
    try {
      _check(
        api.GetTensorTypeAndShape.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)
        >()(v.ptr, infoPP),
      );
      final info = infoPP.value;
      _check(
        api.GetDimensionsCount.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Size>)
        >()(info, nP),
      );
      final nd = nP.value;
      final dims = calloc<ffi.Int64>(nd);
      _check(
        api.GetDimensions.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Int64>, int)
        >()(info, dims, nd),
      );
      final shape = List<int>.from(dims.asTypedList(nd));
      calloc.free(dims);
      api.ReleaseTensorTypeAndShapeInfo.asFunction<void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(info);
      _check(
        api.GetTensorMutableData.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)
        >()(v.ptr, dataPP),
      );
      final n = shape.fold(1, (a, b) => a * b);
      return (Float32List.fromList(dataPP.value.cast<ffi.Float>().asTypedList(n)), shape);
    } finally {
      calloc.free(infoPP);
      calloc.free(nP);
      calloc.free(dataPP);
    }
  }

  (Float32List, List<int>) _run(OrtSession s, Float32List data, List<int> shape) {
    final t = _tensor(data, shape);
    final ro = OrtRunOptions();
    final r = s.run(ro, {'x': t});
    t.release();
    ro.release();
    try {
      return _floats(r.first!);
    } finally {
      for (final o in r) {
        o?.release();
      }
    }
  }

  /// Timings of the last [read] in ms (for the eval log).
  final timing = <String, int>{};

  /// Like [read], but sideways photos are turned upright: if many boxes are taller than wide, also read the
  /// image turned 90° both ways and keep the read with the most confident text (same rule as ocr_pipeline.py).
  (List<List<List<double>>>, List<String>, List<double>) readOriented(img.Image im) {
    var best = read(im);
    if (!_vertical(best.$1)) return best;
    final t0 = Map.of(timing);
    for (final angle in [90, -90]) {
      final r = read(img.copyRotate(im, angle: angle));
      if (_quality(r) > _quality(best)) best = r;
    }
    timing
      ..clear()
      ..addAll(t0)
      ..['rotated'] = 1;
    return best;
  }

  static bool _vertical(List<List<List<double>>> boxes) {
    if (boxes.isEmpty) return true;
    final tall = boxes.where((b) => (b[3][1] - b[0][1]) > (b[1][0] - b[0][0])).length;
    return tall > 0.4 * boxes.length;
  }

  static double _quality((List<List<List<double>>>, List<String>, List<double>) r) {
    var q = 0.0;
    for (var i = 0; i < r.$2.length; i++) {
      if (r.$3[i] > 0.7) q += r.$2[i].length * r.$3[i];
    }
    return q;
  }

  /// Returns boxes (4 corner points, image pixels) and texts, like RapidOCR.
  (List<List<List<double>>>, List<String>, List<double>) read(img.Image im) {
    final W = im.width, H = im.height;
    final s = max(1.0, 736 / min(W, H));
    final w32 = max(32, (W * s / 32).round() * 32), h32 = max(32, (H * s / 32).round() * 32);
    final small = img.copyResize(im, width: w32, height: h32, interpolation: img.Interpolation.linear);
    final sw = Stopwatch()..start();
    timing.clear();
    void lap(String k) {
      timing[k] = (timing[k] ?? 0) + sw.elapsedMilliseconds;
      sw.reset();
    }

    final input = _norm(small);
    lap('prep');
    final (prob, _) = _run(_det, input, [1, 3, h32, w32]);
    lap('det');

    // threshold + 2x2 dilation
    final mask = Uint8List(w32 * h32);
    for (var y = 0; y < h32; y++) {
      for (var x = 0; x < w32; x++) {
        final i = y * w32 + x;
        if (prob[i] > 0.3 ||
            (x > 0 && prob[i - 1] > 0.3) ||
            (y > 0 && prob[i - w32] > 0.3) ||
            (x > 0 && y > 0 && prob[i - w32 - 1] > 0.3)) {
          mask[i] = 1;
        }
      }
    }

    lap('mask');
    final boxes = <List<List<double>>>[], txts = <String>[], scores = <double>[];
    final lines = <(img.Image, List<List<double>>)>[];
    final seen = Uint8List(w32 * h32);
    final sx = W / w32, sy = H / h32;
    for (var start = 0; start < mask.length; start++) {
      if (mask[start] == 0 || seen[start] == 1) continue;
      // BFS, 4-connected
      var x0 = w32, y0 = h32, x1 = 0, y1 = 0;
      final q = Queue<int>()..add(start);
      seen[start] = 1;
      while (q.isNotEmpty) {
        final i = q.removeFirst(), x = i % w32, y = i ~/ w32;
        x0 = min(x0, x);
        y0 = min(y0, y);
        x1 = max(x1, x + 1);
        y1 = max(y1, y + 1);
        for (final n in [if (y + 1 < h32) i + w32, if (y > 0) i - w32, if (x + 1 < w32) i + 1, if (x > 0) i - 1]) {
          if (mask[n] == 1 && seen[n] == 0) {
            seen[n] = 1;
            q.add(n);
          }
        }
      }
      final bw = x1 - x0, bh = y1 - y0;
      if (min(bw, bh) < 3) continue;
      var sum = 0.0, n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          if (mask[y * w32 + x] == 1) {
            sum += prob[y * w32 + x];
            n++;
          }
        }
      }
      lap('boxes');
      if (sum / n < 0.5) continue;
      final d = bw * bh * 1.6 / (2 * (bw + bh)); // unclip
      final X0 = max(0.0, (x0 - d) * sx), Y0 = max(0.0, (y0 - d) * sy);
      final X1 = min(W.toDouble(), (x1 + d) * sx), Y1 = min(H.toDouble(), (y1 + d) * sy);
      final cx = X0.floor(), cy = Y0.floor(), cw0 = X1.ceil() - cx, ch0 = Y1.ceil() - cy;
      if (cw0 < 2 || ch0 < 2) continue;
      final crop = img.copyCrop(im, x: cx, y: cy, width: cw0, height: ch0);
      final cw = max(8, min(3200, (48 * cw0 / ch0).round()));
      lines.add((
        img.copyResize(crop, width: cw, height: 48, interpolation: img.Interpolation.linear),
        [
          [X0, Y0],
          [X1, Y0],
          [X1, Y1],
          [X0, Y1],
        ],
      ));
      lap('crop');
    }

    // Recognition in batches of similar width (like PaddleOCR): one model run per [batch] lines,
    // narrower lines padded with 0 on the right.
    final order = List.generate(lines.length, (i) => i)..sort((a, b) => lines[a].$1.width.compareTo(lines[b].$1.width));
    final texts = List<(String, double)?>.filled(lines.length, null);
    for (var b0 = 0; b0 < order.length; b0 += batch) {
      final idx = order.sublist(b0, min(order.length, b0 + batch));
      final bw = idx.map((i) => lines[i].$1.width).reduce(max);
      final plane = 48 * bw;
      final data = Float32List(idx.length * 3 * plane);
      for (var k = 0; k < idx.length; k++) {
        final li = lines[idx[k]].$1, w = li.width, px = li.getBytes(order: img.ChannelOrder.rgb);
        for (var y = 0; y < 48; y++) {
          for (var x = 0; x < w; x++) {
            final s = (y * w + x) * 3, d = k * 3 * plane + y * bw + x;
            data[d] = px[s] / 127.5 - 1;
            data[d + plane] = px[s + 1] / 127.5 - 1;
            data[d + 2 * plane] = px[s + 2] / 127.5 - 1;
          }
        }
      }
      lap('crop');
      final (seq, shape) = _run(_rec, data, [idx.length, 3, 48, bw]); // [B, T, C]
      lap('rec');
      final steps = shape[1], nCls = shape[2];
      for (var k = 0; k < idx.length; k++) {
        var t = '', last = 0, conf = 0.0, nc = 0;
        for (var st = 0; st < steps; st++) {
          final o = (k * steps + st) * nCls;
          var bi = 0;
          for (var c = 1; c < nCls; c++) {
            if (seq[o + c] > seq[o + bi]) bi = c;
          }
          if (bi != 0 && bi != last) {
            t += _chars[bi - 1];
            conf += seq[o + bi];
            nc++;
          }
          last = bi;
        }
        texts[idx[k]] = (t, nc > 0 ? conf / nc : 0);
      }
      lap('decode');
    }
    for (var i = 0; i < lines.length; i++) {
      final (t, c) = texts[i]!;
      if (t.trim().isEmpty || c < 0.5) continue;
      boxes.add(lines[i].$2);
      txts.add(t);
      scores.add(c);
    }
    return (boxes, txts, scores);
  }
}
