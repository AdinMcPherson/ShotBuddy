import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/models.dart';
import 'detector.dart';
import 'frame_converter.dart';
import 'scene_signature.dart';

/// What the worker sends back for one frame.
class FrameResult {
  const FrameResult(this.detections, this.signature);

  final List<Detection> detections;

  /// Brightness fingerprint of the same frame, computed in the worker because
  /// that is where the raw planes already are — shipping them back to the UI
  /// isolate just to summarize them would defeat the point.
  final SceneSignature? signature;

  static const empty = FrameResult(<Detection>[], null);
}

/// Runs colour conversion and inference on a background isolate.
///
/// Both halves of that sentence matter. Inference is the obvious cost, but
/// YUV→RGB conversion walks 300k pixels per frame and is pure Dart, so leaving
/// it on the UI isolate would still jank the preview even if the model ran
/// elsewhere. They travel together.
///
/// Backpressure is *drop*, never queue — see docs/ARCHITECTURE.md. If inference
/// takes 60ms and frames arrive every 33ms, a queue grows without bound and the
/// overlay ends up seconds behind the ball. [process] returns null immediately
/// when the worker is busy, and the caller simply lets that frame go. The
/// tracker's parabolic fit is what makes this safe: a gap costs precision, not
/// correctness.
class DetectionWorker {
  DetectionWorker._(
    this._isolate,
    this._fromWorker,
    this._toWorker,
    this.inputSize,
  );

  final Isolate _isolate;
  final ReceivePort _fromWorker;
  final SendPort _toWorker;

  /// Model input edge length, reported by the worker once it has loaded.
  final int inputSize;

  Completer<FrameResult>? _inFlight;
  bool _closed = false;

  /// True while a frame is being processed.
  bool get busy => _inFlight != null;

  static Future<DetectionWorker> spawn({
    String asset = 'assets/models/efficientdet_lite0.tflite',
  }) async {
    // Read the model here rather than in the worker: a spawned isolate has no
    // binary messenger, so rootBundle is not available to it.
    final modelBytes = (await rootBundle.load(asset)).buffer.asUint8List();

    final fromWorker = ReceivePort();
    final handshake = Completer<Object?>();
    late final DetectionWorker worker;

    fromWorker.listen((message) {
      if (!handshake.isCompleted) {
        handshake.complete(message);
        return;
      }
      worker._onResult(message);
    });

    final isolate = await Isolate.spawn(
      _workerMain,
      _Boot(fromWorker.sendPort, modelBytes),
      debugName: 'shotbuddy-detector',
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
    );

    final ready = await handshake.future;
    if (ready is! _WorkerReady) {
      isolate.kill(priority: Isolate.immediate);
      fromWorker.close();
      throw StateError(
        ready is _WorkerFailed
            ? 'Detector isolate failed to start: ${ready.message}'
            : 'Detector isolate failed to start: $ready',
      );
    }

    worker = DetectionWorker._(
      isolate,
      fromWorker,
      ready.toWorker,
      ready.inputSize,
    );
    return worker;
  }

  void _onResult(Object? message) {
    final pending = _inFlight;
    _inFlight = null;
    if (pending == null || pending.isCompleted) return;
    // A failed frame resolves as "nothing detected" rather than as an error.
    // A dropped ball for one frame is exactly what the tracker is built to
    // ride through, and throwing here would only give the caller a harder
    // version of the same problem.
    pending.complete(message is FrameResult ? message : FrameResult.empty);
  }

  /// Hand one frame to the worker.
  ///
  /// Returns null — immediately, without copying anything — if the previous
  /// frame is still in flight or the worker is closed.
  Future<FrameResult>? process(YuvFrame frame, {int quarterTurns = 0}) {
    if (_closed || _inFlight != null) return null;

    final completer = Completer<FrameResult>();
    _inFlight = completer;
    _toWorker.send(_FrameRequest.from(frame, quarterTurns));
    return completer.future;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final pending = _inFlight;
    _inFlight = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(FrameResult.empty);
    }
    _isolate.kill(priority: Isolate.immediate);
    _fromWorker.close();
  }
}

// --- Messages ------------------------------------------------------------

class _Boot {
  const _Boot(this.toMain, this.modelBytes);
  final SendPort toMain;
  final Uint8List modelBytes;
}

class _WorkerReady {
  const _WorkerReady(this.toWorker, this.inputSize);
  final SendPort toWorker;
  final int inputSize;
}

class _WorkerFailed {
  const _WorkerFailed(this.message);
  final String message;
}

/// A frame on its way to the worker.
///
/// The planes travel as [TransferableTypedData], which moves the buffers rather
/// than copying them. At 640x480 that is roughly 460 KB per frame, thirty times
/// a second — worth not copying. Transferring ownership is safe because the
/// camera plugin hands us a fresh Dart copy for every frame; nothing on this
/// side reads those planes again.
class _FrameRequest {
  const _FrameRequest({
    required this.y,
    required this.u,
    required this.v,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.quarterTurns,
  });

  factory _FrameRequest.from(YuvFrame f, int quarterTurns) => _FrameRequest(
    y: TransferableTypedData.fromList([f.y]),
    u: TransferableTypedData.fromList([f.u]),
    v: TransferableTypedData.fromList([f.v]),
    width: f.width,
    height: f.height,
    yRowStride: f.yRowStride,
    uvRowStride: f.uvRowStride,
    uvPixelStride: f.uvPixelStride,
    quarterTurns: quarterTurns,
  );

  final TransferableTypedData y;
  final TransferableTypedData u;
  final TransferableTypedData v;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int quarterTurns;

  YuvFrame materialize() => YuvFrame(
    y: y.materialize().asUint8List(),
    u: u.materialize().asUint8List(),
    v: v.materialize().asUint8List(),
    width: width,
    height: height,
    yRowStride: yRowStride,
    uvRowStride: uvRowStride,
    uvPixelStride: uvPixelStride,
  );
}

// --- Worker --------------------------------------------------------------

void _workerMain(_Boot boot) {
  final BallDetector detector;
  try {
    detector = BallDetector.fromBuffer(boot.modelBytes);
  } catch (e) {
    boot.toMain.send(_WorkerFailed('$e'));
    return;
  }

  final converter = FrameConverter(size: detector.inputSize);
  final toWorker = ReceivePort();
  boot.toMain.send(_WorkerReady(toWorker.sendPort, detector.inputSize));

  toWorker.listen((message) {
    if (message is! _FrameRequest) return;
    try {
      final frame = message.materialize();
      final rgb = converter.convert(frame, quarterTurns: message.quarterTurns);
      boot.toMain.send(
        FrameResult(detector.run(rgb), SceneSignature.fromFrame(frame)),
      );
    } catch (e) {
      // One bad frame must not take the worker down with it — the session
      // keeps running and the next frame gets a clean attempt.
      boot.toMain.send(_WorkerFailed('$e'));
    }
  });
}
