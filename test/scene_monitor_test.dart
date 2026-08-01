import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shotbuddy/vision/scene_signature.dart';

const grid = 16;

/// A signature built from a function of cell position, so tests can describe a
/// scene rather than hand-write 256 numbers.
SceneSignature signature(int Function(int gx, int gy) luma) {
  final cells = Uint8List(grid * grid);
  for (var gy = 0; gy < grid; gy++) {
    for (var gx = 0; gx < grid; gx++) {
      cells[gy * grid + gx] = luma(gx, gy).clamp(0, 255);
    }
  }
  return SceneSignature(cells, grid);
}

/// A plausible gym: textured, with no direction you can slide it along and get
/// the same picture back.
///
/// That last part matters. A smooth vertical gradient would be the tempting
/// scene to write, but sliding one vertically just adds a constant to every
/// cell — which is precisely what [SceneSignature.differenceFrom] cancels as a
/// brightness change. Such a scene would make these tests pass for a bad reason
/// and fail for a good one. Real backboards, walls, and bleachers have detail;
/// this stands in for it.
/// Note the hash has to be genuinely non-linear. A linear one taken modulo a
/// constant — `(x * 73 + y * 151) % 180` — looks textured but shifts almost
/// uniformly, which lands back in the same trap one level down.
SceneSignature gymScene({int shiftX = 0, int shiftY = 0}) =>
    signature((gx, gy) => 30 + _hash(gx + shiftX, gy + shiftY) % 180);

int _hash(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)).abs();
}

/// Feed [n] frames of [scene] into [monitor], returning true if it ever fired.
bool feed(SceneMonitor monitor, SceneSignature scene, int n) {
  var fired = false;
  for (var i = 0; i < n; i++) {
    if (monitor.update(scene)) fired = true;
  }
  return fired;
}

void main() {
  group('SceneSignature difference', () {
    test('a scene compared with itself has no difference', () {
      final scene = gymScene();
      expect(scene.differenceFrom(scene), 0);
    });

    test('a uniform brightness change is not a difference', () {
      // Auto-exposure re-metering, a cloud, someone hitting the gym lights.
      // Every cell moves together and the camera has not budged.
      final before = gymScene();
      final after = signature((gx, gy) => before.cells[gy * grid + gx] + 35);
      expect(after.differenceFrom(before), lessThan(2));
    });

    test('a shifted camera is a large difference', () {
      expect(gymScene(shiftY: 3).differenceFrom(gymScene()), greaterThan(20));
    });

    test('a person moving through frame stays well under the alarm', () {
      // A rebounder crossing the bottom of the shot: a block of cells changes
      // completely, the rest are untouched. The median ignores them, which is
      // the entire reason it is a median.
      //
      // Not zero, and it should not be: enough saturated cells nudge the median
      // we center on, which offsets every other cell a little. What matters is
      // the margin to the decision boundary, so that is what this asserts.
      final before = gymScene();
      final after = signature((gx, gy) {
        final base = before.cells[gy * grid + gx];
        final inPerson = gx >= 2 && gx <= 5 && gy >= 11;
        return inPerson ? 250 : base;
      });
      expect(
        after.differenceFrom(before),
        lessThan(SceneMonitor.displacementThreshold),
      );
    });

    test('mismatched grid sizes read as maximally different', () {
      final odd = SceneSignature(Uint8List.fromList([1, 2, 3, 4]), 2);
      expect(gymScene().differenceFrom(odd), 255);
    });
  });

  group('SceneMonitor', () {
    test('does nothing until armed', () {
      final monitor = SceneMonitor();
      expect(monitor.armed, isFalse);
      expect(feed(monitor, gymScene(shiftY: 6), 100), isFalse);
      expect(monitor.lost, isFalse);
    });

    test('stays quiet while the scene holds still', () {
      final monitor = SceneMonitor()..arm(gymScene());
      expect(feed(monitor, gymScene(), 300), isFalse);
      expect(monitor.lost, isFalse);
    });

    test('fires once the shift is sustained', () {
      final monitor = SceneMonitor()..arm(gymScene());
      expect(
        feed(monitor, gymScene(shiftY: 6), SceneMonitor.framesToConfirm),
        isTrue,
      );
      expect(monitor.lost, isTrue);
    });

    test('does not fire on a brief disturbance', () {
      // Someone walks close past the lens and swamps the grid for a moment.
      // Shorter than the confirmation window, so it must not count.
      final monitor = SceneMonitor()..arm(gymScene());
      expect(
        feed(monitor, gymScene(shiftY: 6), SceneMonitor.framesToConfirm - 1),
        isFalse,
      );
      expect(monitor.lost, isFalse);
    });

    test('a settled frame resets the count toward confirmation', () {
      final monitor = SceneMonitor()..arm(gymScene());
      for (var burst = 0; burst < 5; burst++) {
        feed(monitor, gymScene(shiftY: 6), SceneMonitor.framesToConfirm - 1);
        feed(monitor, gymScene(), 1);
      }
      expect(
        monitor.lost,
        isFalse,
        reason: 'intermittent spikes must not accumulate into an alarm',
      );
    });

    test('fires exactly once, not on every frame after', () {
      final monitor = SceneMonitor()..arm(gymScene());
      final moved = gymScene(shiftY: 6);
      var fires = 0;
      for (var i = 0; i < 200; i++) {
        if (monitor.update(moved)) fires++;
      }
      expect(fires, 1);
    });

    test('cannot recover on its own — only re-arming clears it', () {
      final monitor = SceneMonitor()..arm(gymScene());
      feed(monitor, gymScene(shiftY: 6), SceneMonitor.framesToConfirm);
      expect(monitor.lost, isTrue);

      // Even if the original scene comes back, we do not quietly resume: we
      // have no way to know the rim is where it was.
      feed(monitor, gymScene(), 100);
      expect(monitor.lost, isTrue);

      monitor.arm(gymScene());
      expect(monitor.lost, isFalse);
    });

    test('disarming stops it watching', () {
      final monitor = SceneMonitor()..arm(gymScene());
      monitor.disarm();
      expect(monitor.armed, isFalse);
      expect(feed(monitor, gymScene(shiftY: 6), 100), isFalse);
    });
  });
}
