import 'dart:math' as math;

import 'models.dart';

/// Follows the ball across frames and fills in the gaps.
///
/// The detector will not find the ball in every frame — it disappears behind
/// the backboard, blurs at speed, and gets lost against a bright sky. Rather
/// than requiring a detection per frame, we keep a short history and fit a
/// parabola to it, which is what a ball in flight actually follows. That makes
/// dropped frames a loss of precision instead of a loss of correctness.
class BallTracker {
  BallTracker({
    this.maxGapMs = 400,
    this.historyLength = 24,
    this.maxJumpPerSecond = 4.0,
  });

  /// How long the ball can go undetected before the track is abandoned.
  final int maxGapMs;

  /// How many points to keep. ~24 points at 15-30 FPS covers roughly a second,
  /// which is about the length of a shot arc.
  final int historyLength;

  /// Rejection threshold for association, in normalized units per second. A
  /// candidate further away than this is assumed to be a different object
  /// (another player's ball, a false positive) rather than our ball having
  /// teleported.
  final double maxJumpPerSecond;

  final List<TrackPoint> _points = [];

  List<TrackPoint> get points => List.unmodifiable(_points);
  bool get hasTrack => _points.isNotEmpty;
  TrackPoint? get last => _points.isEmpty ? null : _points.last;

  /// Feed the frame's best ball candidate, or null if none was found.
  ///
  /// Returns the accepted point, or null if the candidate was rejected or
  /// absent.
  TrackPoint? update(Detection? ball, int nowMs) {
    _expire(nowMs);

    if (ball == null) return null;

    final candidate = TrackPoint(ball.box.centerX, ball.box.centerY, nowMs);

    final previous = last;
    if (previous != null) {
      final dtSeconds = math.max(1, nowMs - previous.t) / 1000.0;
      final distance = _distance(previous, candidate);
      if (distance / dtSeconds > maxJumpPerSecond) {
        // Too far, too fast to be the same ball. Ignore it rather than let it
        // corrupt the track.
        return null;
      }
    }

    _points.add(candidate);
    if (_points.length > historyLength) _points.removeAt(0);
    return candidate;
  }

  void reset() => _points.clear();

  void _expire(int nowMs) {
    if (_points.isNotEmpty && nowMs - _points.last.t > maxGapMs) {
      _points.clear();
    }
  }

  double _distance(TrackPoint a, TrackPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  /// Vertical velocity in normalized units per second, positive downward.
  ///
  /// Measured over the last few points rather than the last two, so a single
  /// noisy detection doesn't flip the sign and confuse the state machine.
  double? verticalVelocity() {
    if (_points.length < 3) return null;
    final recent = _points.sublist(math.max(0, _points.length - 5));
    final first = recent.first;
    final last = recent.last;
    final dtSeconds = (last.t - first.t) / 1000.0;
    if (dtSeconds <= 0) return null;
    return (last.y - first.y) / dtSeconds;
  }

  /// Fit y = a*t^2 + b*t + c over the tracked points and predict y at [atMs].
  ///
  /// This is what lets the make/miss rules see through an occlusion: if the
  /// ball vanishes behind the net for four frames, the arc is still known.
  /// Returns null when there aren't enough points to fit.
  double? predictY(int atMs) {
    if (_points.length < 4) return null;

    // Times are re-based to the first point to keep the numbers small; a raw
    // millisecond epoch squared loses precision fast.
    final t0 = _points.first.t;
    final n = _points.length.toDouble();

    double sT = 0, sT2 = 0, sT3 = 0, sT4 = 0;
    double sY = 0, sTY = 0, sT2Y = 0;

    for (final p in _points) {
      final t = (p.t - t0) / 1000.0;
      final t2 = t * t;
      sT += t;
      sT2 += t2;
      sT3 += t2 * t;
      sT4 += t2 * t2;
      sY += p.y;
      sTY += t * p.y;
      sT2Y += t2 * p.y;
    }

    // Normal equations for a quadratic least-squares fit, solved by Cramer's
    // rule on the 3x3 system.
    final m = [
      [sT4, sT3, sT2],
      [sT3, sT2, sT],
      [sT2, sT, n],
    ];
    final v = [sT2Y, sTY, sY];

    final det = _det3(m);
    if (det.abs() < 1e-12) return null;

    final a = _det3(_replaceColumn(m, 0, v)) / det;
    final b = _det3(_replaceColumn(m, 1, v)) / det;
    final c = _det3(_replaceColumn(m, 2, v)) / det;

    final t = (atMs - t0) / 1000.0;
    return a * t * t + b * t + c;
  }

  double _det3(List<List<double>> m) =>
      m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
      m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
      m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

  List<List<double>> _replaceColumn(
    List<List<double>> m,
    int column,
    List<double> v,
  ) {
    return [
      for (var r = 0; r < 3; r++)
        [for (var c = 0; c < 3; c++) c == column ? v[r] : m[r][c]],
    ];
  }
}
