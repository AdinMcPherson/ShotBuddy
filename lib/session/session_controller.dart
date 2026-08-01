import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/make_miss.dart';
import '../domain/models.dart';
import '../domain/tracker.dart';
import '../vision/detection_isolate.dart';
import '../vision/frame_converter.dart';

/// How the screen should be behaving right now.
enum SessionMode {
  /// Camera is warming up.
  starting,

  /// Waiting for the user to mark where the rim is.
  calibrating,

  /// Watching for shots.
  running,

  /// Something went wrong and the user needs to know what.
  error,
}

/// Owns the camera, the detector, and the running tally for one shooting
/// session.
///
/// Deliberately a plain [ChangeNotifier]: the state here is one screen's worth
/// and the frame loop is the interesting part, so a heavier state solution
/// would add indirection without adding clarity.
class SessionController extends ChangeNotifier {
  SessionController();

  static const _storageKey = 'shotbuddy.session.v1';
  static const _rimKey = 'shotbuddy.rim.v1';

  CameraController? camera;
  DetectionWorker? _worker;

  final BallTracker tracker = BallTracker();
  MakeMissRules? _rules;

  SessionMode mode = SessionMode.starting;
  String? errorMessage;

  RimCalibration? rim;
  final List<Shot> shots = [];
  int _nextShotId = 1;
  DateTime? startedAt;

  /// Latest frame's detections, for the debug overlay.
  List<Detection> lastDetections = const [];
  Detection? lastBall;

  /// Rolling performance numbers, shown in the debug panel. If these are bad,
  /// everything else will be too, so they are always available rather than
  /// hidden behind a build flag.
  double fps = 0;
  int inferenceMs = 0;

  bool showDebug = false;

  /// Clockwise quarter-turns needed to bring a sensor frame into display
  /// orientation. Set by the UI, which is the only thing that knows how the
  /// phone is being held. Landscape is 0 — the sensor is already landscape —
  /// and portrait is 1.
  int _quarterTurns = 0;

  /// Called by the UI on every orientation change. Cheap and idempotent.
  void setDisplayRotation(int quarterTurns) {
    final turns = quarterTurns & 3;
    if (turns == _quarterTurns) return;
    _quarterTurns = turns;
    // The rim was marked in the old orientation and means nothing in the new
    // one, so ask for it again rather than silently scoring against a rim that
    // is no longer where the user pointed.
    if (rim != null) recalibrate();
  }

  int _framesSinceTick = 0;
  DateTime _lastTick = DateTime.now();

  int get attempts => shots.length;
  int get makes => shots.where((s) => s.result == ShotResult.make).length;
  int get misses => attempts - makes;
  double get percentage => attempts == 0 ? 0 : makes / attempts * 100;
  int get unresolved => _rules?.unresolved ?? 0;
  ShotPhase get phase => _rules?.phase ?? ShotPhase.idle;

  /// Makes in a row, counting back from the most recent shot.
  int get currentStreak {
    var n = 0;
    for (var i = shots.length - 1; i >= 0; i--) {
      if (shots[i].result != ShotResult.make) break;
      n++;
    }
    return n;
  }

  /// Longest run of makes this session.
  int get bestStreak {
    var best = 0;
    var run = 0;
    for (final s in shots) {
      run = s.result == ShotResult.make ? run + 1 : 0;
      if (run > best) best = run;
    }
    return best;
  }

  /// Shooting percentage over the last [n] attempts — a much better read on how
  /// you are shooting *right now* than a session average that a cold start
  /// keeps dragging down.
  double recentPercentage([int n = 10]) {
    if (shots.isEmpty) return 0;
    final window = shots.length <= n ? shots : shots.sublist(shots.length - n);
    final made = window.where((s) => s.result == ShotResult.make).length;
    return made / window.length * 100;
  }

  /// The most recent [n] shots, oldest first.
  List<Shot> recentShots([int n = 12]) =>
      shots.length <= n ? List.of(shots) : shots.sublist(shots.length - n);

  Duration get elapsed =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  Future<void> init() async {
    try {
      _worker = await DetectionWorker.spawn();

      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        // Medium is a deliberate choice: the model sees 320x320 regardless, so
        // a higher capture resolution costs conversion time and battery and
        // buys nothing.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      camera = controller;

      await _restore();

      mode = rim == null ? SessionMode.calibrating : SessionMode.running;
      if (rim != null) _rules = MakeMissRules(rim: rim!);

      startedAt ??= DateTime.now();
      await controller.startImageStream(_onFrame);
    } catch (e) {
      mode = SessionMode.error;
      errorMessage = '$e';
    }
    notifyListeners();
  }

  void _onFrame(CameraImage image) {
    final worker = _worker;
    if (worker == null) return;

    // Timing is measured around the whole convert+infer path, because a slow
    // colour conversion hurts exactly as much as a slow model.
    final started = DateTime.now();

    // Null means the worker is still on the previous frame. Drop this one and
    // return without touching the planes — that is the whole backpressure
    // policy, and it costs nothing.
    final pending = worker.process(
      YuvFrame.fromCameraImage(image),
      quarterTurns: _quarterTurns,
    );
    if (pending == null) return;

    unawaited(
      pending
          .then((detections) {
            if (_disposed) return;
            _applyDetections(detections, started);
          })
          .catchError((Object e) {
            debugPrint('ShotBuddy: frame failed: $e');
          }),
    );
  }

  /// Fold one frame's detections into the tracker and the rule engine.
  ///
  /// Runs on the UI isolate, but only over a handful of boxes — the expensive
  /// work is already done by the time this is called.
  void _applyDetections(List<Detection> detections, DateTime started) {
    lastDetections = detections;

    final ball = bestBall(detections);
    lastBall = ball;

    if (mode == SessionMode.running && _rules != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final point = tracker.update(ball, nowMs);
      final event = _rules!.update(
        point: point,
        tracker: tracker,
        nowMs: nowMs,
        confidence: ball?.score ?? 0,
      );
      if (event != null) _record(event);
    }

    inferenceMs = DateTime.now().difference(started).inMilliseconds;
    _tickFps();
    notifyListeners();
  }

  void _tickFps() {
    _framesSinceTick++;
    final elapsed = DateTime.now().difference(_lastTick);
    if (elapsed.inMilliseconds >= 1000) {
      fps = _framesSinceTick * 1000 / elapsed.inMilliseconds;
      _framesSinceTick = 0;
      _lastTick = DateTime.now();
    }
  }

  void _record(ShotEvent event) {
    shots.add(
      Shot(
        id: _nextShotId++,
        result: event.result,
        timestamp: DateTime.now(),
        confidence: event.confidence,
        correctedByUser: false,
        releaseX: event.releaseX,
        releaseY: event.releaseY,
      ),
    );
    unawaited(_persist());
  }

  /// Set the rim from a tap on the preview, in normalized coordinates.
  void calibrate(double x, double y, {double halfWidth = 0.055}) {
    rim = RimCalibration(centerX: x, centerY: y, halfWidth: halfWidth);
    _rules = MakeMissRules(rim: rim!);
    tracker.reset();
    mode = SessionMode.running;
    unawaited(_persistRim());
    notifyListeners();
  }

  void setRimWidth(double halfWidth) {
    final current = rim;
    if (current == null) return;
    rim = RimCalibration(
      centerX: current.centerX,
      centerY: current.centerY,
      halfWidth: halfWidth,
    );
    _rules = MakeMissRules(rim: rim!);
    unawaited(_persistRim());
    notifyListeners();
  }

  void recalibrate() {
    mode = SessionMode.calibrating;
    tracker.reset();
    _rules?.resetAll();
    notifyListeners();
  }

  /// Log a shot by hand.
  ///
  /// This is not a fallback for a broken feature — it is how the tally stays
  /// true when detection misses one, and it is available at all times.
  void addManual(ShotResult result) {
    shots.add(
      Shot(
        id: _nextShotId++,
        result: result,
        timestamp: DateTime.now(),
        confidence: 1.0,
        correctedByUser: true,
      ),
    );
    unawaited(_persist());
    notifyListeners();
  }

  /// Flip the most recent shot. Marks it as user-corrected, which separates
  /// ground truth from model output for future retraining.
  void flipLast() {
    if (shots.isEmpty) return;
    final last = shots.removeLast();
    shots.add(
      last.copyWith(
        result: last.result == ShotResult.make
            ? ShotResult.miss
            : ShotResult.make,
        correctedByUser: true,
      ),
    );
    unawaited(_persist());
    notifyListeners();
  }

  void undoLast() {
    if (shots.isEmpty) return;
    shots.removeLast();
    unawaited(_persist());
    notifyListeners();
  }

  void toggleDebug() {
    showDebug = !showDebug;
    notifyListeners();
  }

  Future<void> resetSession() async {
    shots.clear();
    _nextShotId = 1;
    startedAt = DateTime.now();
    tracker.reset();
    _rules?.resetAll();
    await _persist();
    notifyListeners();
  }

  // --- Persistence -------------------------------------------------------
  //
  // Shots are written to shared_preferences after every change so a crash or
  // an accidental back-swipe mid-game cannot lose a session. Drift replaces
  // this in Phase 2; the storage shape is deliberately trivial so that
  // migration is a one-time read of this key.

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'startedAt': startedAt?.toIso8601String(),
      'shots': [
        for (final s in shots)
          {
            'id': s.id,
            'made': s.result == ShotResult.make,
            'at': s.timestamp.toIso8601String(),
            'confidence': s.confidence,
            'corrected': s.correctedByUser,
          },
      ],
    });
    await prefs.setString(_storageKey, payload);
  }

  Future<void> _persistRim() async {
    final current = rim;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _rimKey,
      jsonEncode({
        'x': current.centerX,
        'y': current.centerY,
        'hw': current.halfWidth,
      }),
    );
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();

    final rimJson = prefs.getString(_rimKey);
    if (rimJson != null) {
      final m = jsonDecode(rimJson) as Map<String, dynamic>;
      rim = RimCalibration(
        centerX: (m['x'] as num).toDouble(),
        centerY: (m['y'] as num).toDouble(),
        halfWidth: (m['hw'] as num).toDouble(),
      );
    }

    final sessionJson = prefs.getString(_storageKey);
    if (sessionJson == null) return;

    final m = jsonDecode(sessionJson) as Map<String, dynamic>;
    final at = m['startedAt'] as String?;
    startedAt = at == null ? null : DateTime.tryParse(at);

    for (final raw in (m['shots'] as List? ?? const [])) {
      final s = raw as Map<String, dynamic>;
      shots.add(
        Shot(
          id: s['id'] as int,
          result: (s['made'] as bool) ? ShotResult.make : ShotResult.miss,
          timestamp: DateTime.parse(s['at'] as String),
          confidence: (s['confidence'] as num).toDouble(),
          correctedByUser: s['corrected'] as bool? ?? false,
        ),
      );
    }
    _nextShotId = shots.isEmpty ? 1 : shots.last.id + 1;
  }

  /// Set before teardown so in-flight frame callbacks — which now outlive the
  /// synchronous frame handler — know not to touch a disposed controller.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    camera?.stopImageStream();
    camera?.dispose();
    _worker?.close();
    super.dispose();
  }
}
