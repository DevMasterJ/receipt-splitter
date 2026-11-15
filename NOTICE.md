# Third-party components

Receipt Splitter is MIT licensed (see LICENSE). It includes or uses:

| Component | Used for | Licence |
|---|---|---|
| [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) PP-OCRv5 mobile detection + Latin recognition models (`assets/ocr/`, converted to ONNX) | reading receipts | Apache-2.0 |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) via [onnxruntime](https://pub.dev/packages/onnxruntime) (Dart) | running the OCR models | MIT |
| [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) via [flutter_zxing](https://pub.dev/packages/flutter_zxing) | scanning QR codes | Apache-2.0 / MIT |
| Flutter and the Dart/Flutter packages in `pubspec.yaml` | the app | see each package (BSD-3-Clause / MIT / Apache-2.0) |

Run `flutter pub deps` for the full list of packages.
