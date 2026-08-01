import 'models.dart';
import 'tracker.dart';

/// Where a shot attempt currently is in its life cycle.
enum ShotPhase {
  /// No attempt in progress.
  idle,

  /// The ball has risen above the rim line. From here, whatever comes down is
  /// an attempt.
  armed,

  /// The ball crossed the rim plane inside the gate. Not called a make yet —
  /// this state exists purely to catch rim-outs, which are the most common way
  /// a naive implementation over-counts.
  pending,
}

/// What the rules decided this frame, if anything.
class ShotEvent {
  const ShotEvent({
    required this.result,
    required this.confidence,
    this.releaseX,
    this.releaseY,
  });

  final ShotResult result;
  final double confidence;
  final double? releaseX;
  final double? releaseY;
}

/// Decides make or miss from geometry rather than from a second neural network.
///
/// The detector tells us where the ball is; the rim is known from calibration.
/// Whether the ball went through is then a question about a trajectory crossing
/// a plane, which is debuggable, needs no training data, and fails in ways we
/// can explain. See docs/DECISIONS.md D-003.
class MakeMissRules {
  MakeMissRules({
    required this.rim,
    this.armMargin = 0.04,
    this.confirmDrop = 0.05,
    this.gateSlack = 1.15,
    this.resolveTimeoutMs = 1500,
  });

  final RimCalibration rim;

  /// How far above the rim the ball must rise before we treat what follows as
  /// an attempt. Stops a ball being dribbled or held near rim height from
  /// generating phantom shots.
  final double armMargin;

  /// How far below the rim the ball must keep falling before a crossing is
  /// confirmed as a make.
  final double confirmDrop;

  /// The horizontal gate is the rim's half-width scaled by this. Slightly wider
  /// than the rim itself, because the tracked point is the ball's center and
  /// the detector's box is imprecise; a shot that clips the near side still
  /// goes in.
  final double gateSlack;

  /// If an armed attempt never resolves within this window, it is abandoned
  /// rather than guessed at.
  final int resolveTimeoutMs;

  ShotPhase _phase = ShotPhase.idle;
  int _armedAtMs = 0;
  double? _releaseX;
  double? _releaseY;
  double _crossingConfidence = 0;

  /// Attempts that went up and never came down in view. Not counted as makes
  /// or misses — guessing would quietly corrupt the stats — but surfaced in the
  /// UI so the user can add them by hand.
  int unresolved = 0;

  ShotPhase get phase => _phase;

  bool _inGate(double x) =>
      (x - rim.centerX).abs() <= rim.halfWidth * gateSlack;

  /// Advance the state machine by one frame.
  ///
  /// [point] is the ball this frame, or null if it wasn't detected.
  /// Returns a [ShotEvent] on the frame a shot resolves, otherwise null.
  ShotEvent? update({
    required TrackPoint? point,
    required BallTracker tracker,
    required int nowMs,
    required double confidence,
  }) {
    if (_phase != ShotPhase.idle && nowMs - _armedAtMs > resolveTimeoutMs) {
      if (_phase == ShotPhase.pending) {
        // It crossed the gate and then we lost it. A ball that passes through
        // the hoop and disappears into the net is the overwhelmingly likely
        // explanation, so this one we do call.
        final event = ShotEvent(
          result: ShotResult.make,
          confidence: _crossingConfidence * 0.8,
          releaseX: _releaseX,
          releaseY: _releaseY,
        );
        _reset();
        return event;
      }
      unresolved++;
      _reset();
      return null;
    }

    if (point == null) return null;

    switch (_phase) {
      case ShotPhase.idle:
        if (point.y < rim.centerY - armMargin) {
          _phase = ShotPhase.armed;
          _armedAtMs = nowMs;
          _releaseX = point.x;
          _releaseY = point.y;
        }

      case ShotPhase.armed:
        final falling = (tracker.verticalVelocity() ?? 0) > 0;
        if (!falling) break;

        if (point.y >= rim.centerY) {
          if (_inGate(point.x)) {
            _phase = ShotPhase.pending;
            _crossingConfidence = confidence;
          } else if (point.y > rim.centerY + confirmDrop) {
            // Came down clearly outside the rim. That's a miss.
            final event = ShotEvent(
              result: ShotResult.miss,
              confidence: confidence,
              releaseX: _releaseX,
              releaseY: _releaseY,
            );
            _reset();
            return event;
          }
        }

      case ShotPhase.pending:
        if (point.y > rim.centerY + confirmDrop) {
          if (_inGate(point.x)) {
            final event = ShotEvent(
              result: ShotResult.make,
              confidence: _crossingConfidence,
              releaseX: _releaseX,
              releaseY: _releaseY,
            );
            _reset();
            return event;
          }
          // Dropped below the rim but drifted outside the gate on the way —
          // it caught the rim and fell away.
          final event = ShotEvent(
            result: ShotResult.miss,
            confidence: confidence,
            releaseX: _releaseX,
            releaseY: _releaseY,
          );
          _reset();
          return event;
        }

        if (point.y < rim.centerY - armMargin) {
          // Bounced back up off the rim. Not resolved yet — re-arm and wait to
          // see where it comes down.
          _phase = ShotPhase.armed;
        }
    }

    return null;
  }

  void _reset() {
    _phase = ShotPhase.idle;
    _releaseX = null;
    _releaseY = null;
    _crossingConfidence = 0;
  }

  void resetAll() {
    _reset();
    unresolved = 0;
  }
}
