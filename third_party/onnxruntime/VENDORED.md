# Vendored copy of the `onnxruntime` Dart package 1.4.1 (pub.dev, MIT, see LICENSE)

Changed: the package bundled ONNX Runtime 1.15.1 as prebuilt .so files (2023, 4 KB page aligned, which Google
Play no longer accepts). Those are removed; `android/build.gradle` instead depends on Microsoft's official
`com.microsoft.onnxruntime:onnxruntime-android:1.32.0` from Maven Central, whose `libonnxruntime.so` the Dart FFI
bindings load. The bindings use ONNX Runtime's stable C API, which newer engines keep compatible.
Example and desktop/iOS folders removed.

To update the engine: change the version in android/build.gradle, rebuild, run the OCR tests on a phone.
