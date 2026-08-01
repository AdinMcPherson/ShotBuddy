import 'package:flutter_test/flutter_test.dart';
import 'package:shotbuddy/domain/make_miss.dart';
import 'package:shotbuddy/domain/models.dart';
import 'package:shotbuddy/domain/tracker.dart';

/// The make/miss rules are pure geometry, so they can be exercised with
/// synthetic trajectories — no camera, no model, no device. These are the tests
/// that have to keep passing when the detector is swapped for a purpose-trained
/// model in a later phase.
void main() {
  const rim = RimCalibration(centerX: 0.5, centerY: 0.4, halfWidth: 0.05);

  /// Feed a sequence of ball positions through the tracker and the rules,
  /// returning whatever the rules decided.
  ShotEvent? play(List<(double, double)> path, {int stepMs = 33}) {
    final tracker = BallTracker();
    final rules = MakeMissRules(rim: rim);
    ShotEvent? result;

    var t = 0;
    for (final (x, y) in path) {
      final detection = Detection(
        label: 'sports ball',
        score: 0.9,
        box: NormRect(x - 0.02, y - 0.02, x + 0.02, y + 0.02),
      );
      final point = tracker.update(detection, t);
      final event = rules.update(
        point: point,
        tracker: tracker,
        nowMs: t,
        confidence: 0.9,
      );
      result ??= event;
      t += stepMs;
    }
    return result;
  }

  /// A ball rising to an apex and falling to [endX], passing the rim line on
  /// the way down.
  ///
  /// 30 steps rather than a handful: at 33ms per frame, a coarser sample makes
  /// the ball appear to move faster than the tracker's plausibility limit and
  /// the points get rejected as a different object. Real frames are dense
  /// enough; the test has to be too.
  List<(double, double)> arc({required double endX, int steps = 30}) {
    final path = <(double, double)>[];
    const startX = 0.5;
    for (var i = 0; i < steps; i++) {
      final p = i / (steps - 1);
      final x = startX + (endX - startX) * p;
      // Starts below the rim (0.7), peaks well above it (~0.1), and finishes
      // clearly below it (0.9) so the fall is unambiguous.
      final y = 0.7 - 2.6 * p + 2.8 * p * p;
      path.add((x, y));
    }
    return path;
  }

  test('a ball falling through the gate is a make', () {
    final event = play(arc(endX: 0.5));
    expect(event, isNotNull);
    expect(event!.result, ShotResult.make);
  });

  test('a ball falling well outside the gate is a miss', () {
    final event = play(arc(endX: 0.85));
    expect(event, isNotNull);
    expect(event!.result, ShotResult.miss);
  });

  test('a ball that never rises above the rim is not a shot at all', () {
    // Dribbling: bobbing around below the rim line should produce nothing.
    final path = [
      for (var i = 0; i < 30; i++) (0.5, 0.75 + (i.isEven ? 0.03 : -0.03)),
    ];
    expect(play(path), isNull);
  });

  test('a rim-out is not counted as a make', () {
    // Crosses the rim plane inside the gate, then bounces back up and away.
    final path = <(double, double)>[
      for (var i = 0; i < 10; i++) (0.5, 0.6 - i * 0.045), // rise
      for (var i = 0; i < 5; i++) (0.5, 0.15 + i * 0.055), // fall to the rim
      for (var i = 0; i < 6; i++) (0.52 + i * 0.02, 0.42 - i * 0.03), // out
      for (var i = 0; i < 10; i++) (0.64 + i * 0.02, 0.24 + i * 0.06), // away
    ];
    final event = play(path);
    expect(event, isNotNull);
    expect(event!.result, ShotResult.miss);
  });

  group('BallTracker', () {
    test('rejects a candidate that jumps implausibly far', () {
      final tracker = BallTracker();
      tracker.update(_ball(0.5, 0.5), 0);
      // Another ball across the court, one frame later.
      final accepted = tracker.update(_ball(0.95, 0.1), 33);
      expect(accepted, isNull);
      expect(tracker.last!.x, 0.5);
    });

    test('drops the track after a long gap', () {
      final tracker = BallTracker(maxGapMs: 100);
      tracker.update(_ball(0.5, 0.5), 0);
      tracker.update(null, 500);
      expect(tracker.hasTrack, isFalse);
    });

    test('predicts through an occlusion with a parabolic fit', () {
      final tracker = BallTracker();
      // Sample a known parabola, then ask for a point beyond the samples.
      double y(double t) => 0.1 * t * t - 0.5 * t + 0.6;
      for (var i = 0; i < 8; i++) {
        final t = i * 0.1;
        tracker.update(_ball(0.5, y(t)), (t * 1000).round());
      }
      final predicted = tracker.predictY(1000);
      expect(predicted, isNotNull);
      expect(predicted!, closeTo(y(1.0), 0.01));
    });
  });
}

Detection _ball(double x, double y) => Detection(
  label: 'sports ball',
  score: 0.9,
  box: NormRect(x - 0.02, y - 0.02, x + 0.02, y + 0.02),
);
