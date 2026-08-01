/// Core value types for the detection pipeline.
///
/// Everything here is pure Dart with no Flutter or plugin imports, so the shot
/// logic can be unit-tested without a device or a camera. See
/// docs/ARCHITECTURE.md.
library;

/// A rectangle in normalized image coordinates: 0..1 on both axes, with y
/// increasing downward (screen convention, not maths convention).
class NormRect {
  const NormRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;
}

/// One object found by the detector in one frame.
class Detection {
  const Detection({
    required this.label,
    required this.score,
    required this.box,
  });

  final String label;
  final double score;
  final NormRect box;
}

/// The single best `sports ball` among one frame's detections, or null.
///
/// Only one ball is tracked: in a pickup game there may be several on the
/// court, and following the highest-confidence one is far more stable than
/// trying to reason about all of them.
///
/// Lives here rather than on the detector because it is pure selection logic —
/// the detector runs in a background isolate, and this runs on whichever side
/// happens to hold the detections.
Detection? bestBall(List<Detection> detections) {
  Detection? best;
  for (final d in detections) {
    if (d.label != 'sports ball') continue;
    if (best == null || d.score > best.score) best = d;
  }
  return best;
}

/// The ball's position at a single instant, in normalized image coordinates.
class TrackPoint {
  const TrackPoint(this.x, this.y, this.t);

  final double x;
  final double y;

  /// Milliseconds since session start. Used for velocity, so that a dropped
  /// frame doesn't read as a sudden change in speed.
  final int t;
}

/// The rim, located once during calibration rather than detected every frame.
///
/// Stored normalized so it survives preview resizes and orientation reporting
/// differences between devices.
class RimCalibration {
  const RimCalibration({
    required this.centerX,
    required this.centerY,
    required this.halfWidth,
  });

  final double centerX;
  final double centerY;

  /// Half the rim's horizontal extent. The "gate" a made shot must pass
  /// through is [centerX] +/- this value.
  final double halfWidth;

  double get left => centerX - halfWidth;
  double get right => centerX + halfWidth;

  bool containsX(double x) => x >= left && x <= right;
}

/// The outcome of one shot attempt.
enum ShotResult { make, miss }

/// A single recorded attempt.
class Shot {
  Shot({
    required this.id,
    required this.result,
    required this.timestamp,
    required this.confidence,
    required this.correctedByUser,
    this.releaseX,
    this.releaseY,
  });

  final int id;
  final ShotResult result;
  final DateTime timestamp;

  /// Detector confidence at the moment of the rim crossing. Low values are
  /// surfaced in the UI so the user knows which calls to double-check.
  final double confidence;

  /// True once the user has manually flipped this shot. Separating model
  /// output from ground truth is what makes corrections useful as training
  /// data later (see docs/ARCHITECTURE.md).
  final bool correctedByUser;

  /// Where the ball was when the attempt started, if known.
  final double? releaseX;
  final double? releaseY;

  Shot copyWith({ShotResult? result, bool? correctedByUser}) => Shot(
    id: id,
    result: result ?? this.result,
    timestamp: timestamp,
    confidence: confidence,
    correctedByUser: correctedByUser ?? this.correctedByUser,
    releaseX: releaseX,
    releaseY: releaseY,
  );
}
