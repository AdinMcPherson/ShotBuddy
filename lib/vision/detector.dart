import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/models.dart';
import 'coco_labels.dart';

/// Wraps the on-device object detector.
///
/// Phase 1 runs a stock COCO EfficientDet-Lite0, which already knows the class
/// `sports ball` — that is what makes shot detection possible tonight without
/// training anything. A purpose-trained two-class ball+rim model replaces it in
/// a later phase (docs/ROADMAP.md); this class is the seam where that swap
/// happens, and nothing above it needs to change.
class BallDetector {
  BallDetector._(this._interpreter, this._inputSize, this._inputIsFloat);

  final Interpreter _interpreter;
  final int _inputSize;
  final bool _inputIsFloat;

  int get inputSize => _inputSize;

  /// The detection head emits a fixed number of candidate boxes per frame.
  late final int _maxDetections;

  /// Index of each output tensor. TFLite's detection post-process op emits four
  /// tensors whose order is conventional but not guaranteed, so we identify
  /// them by shape and then sanity-check at first inference.
  late int _boxesIdx;
  late int _classesIdx;
  late int _scoresIdx;
  int? _countIdx;

  bool _orderVerified = false;

  static Future<BallDetector> load({
    String asset = 'assets/models/efficientdet_lite0.tflite',
  }) async {
    // NNAPI is the fastest path on most Android hardware, but it is also the
    // one most likely to fail on a specific device/driver combination. Fall
    // back rather than refusing to start.
    Interpreter interpreter;
    try {
      interpreter = await Interpreter.fromAsset(
        asset,
        options: InterpreterOptions()
          ..threads = 4
          ..useNnApiForAndroid = true,
      );
    } catch (e) {
      debugPrint('ShotBuddy: NNAPI delegate unavailable ($e); using CPU.');
      interpreter = await Interpreter.fromAsset(
        asset,
        options: InterpreterOptions()..threads = 4,
      );
    }
    return BallDetector._fromInterpreter(interpreter);
  }

  /// Build a detector from model bytes rather than an asset path.
  ///
  /// The detection isolate uses this: `Interpreter.fromAsset` goes through the
  /// root asset bundle over a platform channel, which a spawned isolate has no
  /// messenger for. Reading the bytes once on the main isolate and shipping
  /// them across is simpler than wiring up a background messenger, and the
  /// model is read exactly once either way.
  static BallDetector fromBuffer(Uint8List modelBytes) {
    Interpreter interpreter;
    try {
      interpreter = Interpreter.fromBuffer(
        modelBytes,
        options: InterpreterOptions()
          ..threads = 4
          ..useNnApiForAndroid = true,
      );
    } catch (e) {
      debugPrint('ShotBuddy: NNAPI delegate unavailable ($e); using CPU.');
      interpreter = Interpreter.fromBuffer(
        modelBytes,
        options: InterpreterOptions()..threads = 4,
      );
    }
    return BallDetector._fromInterpreter(interpreter);
  }

  static BallDetector _fromInterpreter(Interpreter interpreter) {
    final inputTensor = interpreter.getInputTensor(0);
    final inputSize = inputTensor.shape[1];
    final isFloat = inputTensor.type == TensorType.float32;

    return BallDetector._(interpreter, inputSize, isFloat).._mapOutputs();
  }

  void _mapOutputs() {
    final tensors = _interpreter.getOutputTensors();

    int? boxes;
    final flat = <int>[];

    for (var i = 0; i < tensors.length; i++) {
      final shape = tensors[i].shape;
      if (shape.length == 3 && shape.last == 4) {
        boxes = i;
      } else if (shape.length == 2) {
        flat.add(i);
      } else if (shape.length == 1) {
        _countIdx = i;
      }
    }

    if (boxes == null || flat.length < 2) {
      throw StateError(
        'Unexpected detector output signature: '
        '${tensors.map((t) => t.shape).toList()}',
      );
    }

    _boxesIdx = boxes;
    // Conventional order from TFLite_Detection_PostProcess: classes then
    // scores. Verified against real output on the first inference below.
    _classesIdx = flat[0];
    _scoresIdx = flat[1];
    _maxDetections = tensors[boxes].shape[1];
  }

  /// Run one frame. [rgb] must be `inputSize * inputSize * 3` bytes.
  ///
  /// Returns every detection above [threshold], newest boxes in normalized
  /// image coordinates.
  List<Detection> run(Uint8List rgb, {double threshold = 0.25}) {
    final Object input;
    if (_inputIsFloat) {
      final floats = Float32List(rgb.length);
      for (var i = 0; i < rgb.length; i++) {
        // EfficientDet's float variant expects [-1, 1].
        floats[i] = (rgb[i] - 127.5) / 127.5;
      }
      input = floats;
    } else {
      input = rgb;
    }

    _interpreter.getInputTensor(0).setTo(input);
    _interpreter.invoke();

    final boxes = _readFloats(_boxesIdx, _maxDetections * 4);
    final classes = _readFloats(_classesIdx, _maxDetections);
    final scores = _readFloats(_scoresIdx, _maxDetections);

    if (!_orderVerified) {
      _verifyOrder(classes, scores);
      _orderVerified = true;
      // Re-read under the corrected mapping so the very first frame is usable.
      return run(rgb, threshold: threshold);
    }

    // The model pads its output to a fixed length; the count tensor says how
    // many of those slots are real. Respecting it avoids walking stale rows
    // left over from a previous frame.
    var valid = _maxDetections;
    final countIdx = _countIdx;
    if (countIdx != null) {
      final count = _readFloats(countIdx, 1).first.round();
      if (count >= 0 && count < valid) valid = count;
    }

    final results = <Detection>[];
    for (var i = 0; i < valid; i++) {
      final score = scores[i];
      if (score < threshold) continue;

      final classIndex = classes[i].round();
      final label = (classIndex >= 0 && classIndex < cocoLabels.length)
          ? cocoLabels[classIndex]
          : 'class $classIndex';

      // Detection post-process emits [ymin, xmin, ymax, xmax].
      final ymin = boxes[i * 4].clamp(0.0, 1.0);
      final xmin = boxes[i * 4 + 1].clamp(0.0, 1.0);
      final ymax = boxes[i * 4 + 2].clamp(0.0, 1.0);
      final xmax = boxes[i * 4 + 3].clamp(0.0, 1.0);

      results.add(
        Detection(
          label: label,
          score: score,
          box: NormRect(xmin, ymin, xmax, ymax),
        ),
      );
    }
    return results;
  }

  /// TFLite's post-process op emits scores in descending order. If the tensor
  /// we assumed held classes looks sorted and bounded to [0, 1] while the other
  /// does not, we guessed backwards — swap them.
  void _verifyOrder(List<double> classes, List<double> scores) {
    bool looksLikeScores(List<double> v) {
      var sorted = true;
      var bounded = true;
      for (var i = 0; i < v.length; i++) {
        if (v[i] < 0 || v[i] > 1) bounded = false;
        if (i > 0 && v[i] > v[i - 1] + 1e-6) sorted = false;
      }
      return sorted && bounded;
    }

    if (!looksLikeScores(scores) && looksLikeScores(classes)) {
      debugPrint('ShotBuddy: detector output order swapped; corrected.');
      final tmp = _classesIdx;
      _classesIdx = _scoresIdx;
      _scoresIdx = tmp;
    }
  }

  List<double> _readFloats(int tensorIndex, int length) {
    final buffer = Float32List(length);
    _interpreter.getOutputTensor(tensorIndex).copyTo(buffer);
    return buffer;
  }

  void close() => _interpreter.close();
}
