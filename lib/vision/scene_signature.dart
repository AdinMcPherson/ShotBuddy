import 'dart:typed_data';

import 'frame_converter.dart';

/// A coarse fingerprint of one frame's brightness, used to notice that the
/// phone has been moved.
///
/// The rim is calibrated once by tapping it and is then assumed to stay put. If
/// the phone gets bumped that assumption silently breaks, and every subsequent
/// shot is scored against a rim that is no longer where the user pointed. We
/// cannot re-find the rim visually — the stock COCO model has no rim class — but
/// we do not have to. Noticing that the *whole scene* shifted is enough to stop
/// and ask.
///
/// The signature is a grid of mean luma values, taken straight off the Y plane.
/// Chroma is ignored: it costs more to sample and adds nothing for this.
class SceneSignature {
  const SceneSignature(this.cells, this.gridSize);

  /// Mean luma per cell, row-major, `gridSize * gridSize` entries.
  final Uint8List cells;
  final int gridSize;

  /// Grid resolution. Coarse on purpose — fine enough that a real camera shift
  /// moves most cells, coarse enough that a ball crossing the frame moves only
  /// a few, and cheap enough to compute on every frame.
  static const int defaultGrid = 16;

  /// Summarize a frame by averaging luma within each cell.
  ///
  /// Samples rather than fully averaging: stepping a fixed number of taps per
  /// cell keeps the cost constant no matter the capture resolution, and for a
  /// brightness average a sample is as good as the full sum.
  factory SceneSignature.fromFrame(YuvFrame frame, {int grid = defaultGrid}) {
    final cells = Uint8List(grid * grid);
    const tapsPerAxis = 4;

    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        var sum = 0;
        var taken = 0;
        for (var ty = 0; ty < tapsPerAxis; ty++) {
          final sy =
              ((gy * tapsPerAxis + ty) * frame.height) ~/ (grid * tapsPerAxis);
          final row = sy * frame.yRowStride;
          for (var tx = 0; tx < tapsPerAxis; tx++) {
            final sx =
                ((gx * tapsPerAxis + tx) * frame.width) ~/ (grid * tapsPerAxis);
            final index = row + sx;
            if (index >= frame.y.length) continue;
            sum += frame.y[index];
            taken++;
          }
        }
        cells[gy * grid + gx] = taken == 0 ? 0 : sum ~/ taken;
      }
    }

    return SceneSignature(cells, grid);
  }

  /// How far this frame has drifted from [other], as the **median** per-cell
  /// difference in luma (0–255), after removing any overall brightness change.
  ///
  /// Two deliberate choices, both there to avoid crying wolf:
  ///
  /// *Median, not mean.* A person walking through shot, a rebounder, a ball
  /// arcing across the frame — each changes a minority of cells, sometimes
  /// drastically, and would drag a mean upward. A camera that actually moved
  /// changes nearly every cell at once, which is the only thing that moves a
  /// median. Without this the alarm would fire every time someone rebounded.
  ///
  /// *Brightness-centered, against the median.* Auto-exposure re-metering, a
  /// cloud, someone hitting the gym lights — these shift every cell together
  /// and would otherwise look exactly like a camera move. Centering each frame
  /// on its own brightness measures the *pattern* of the scene rather than its
  /// level, so a uniform change cancels.
  ///
  /// Centering on the median rather than the mean is not a detail. A mean is
  /// dragged by a minority of extreme cells, so someone stepping into frame in
  /// a white shirt would lift it — and every *untouched* cell would then read
  /// as different by that amount, manufacturing exactly the global shift the
  /// median difference above is built to ignore. The two robust steps only work
  /// as a pair.
  int differenceFrom(SceneSignature other) {
    if (other.gridSize != gridSize) return 255;

    final baseA = _median(cells);
    final baseB = _median(other.cells);

    final diffs = List<int>.filled(cells.length, 0);
    for (var i = 0; i < cells.length; i++) {
      final a = cells[i] - baseA;
      final b = other.cells[i] - baseB;
      diffs[i] = (a - b).abs();
    }
    diffs.sort();
    return diffs[diffs.length ~/ 2];
  }

  static int _median(Uint8List values) {
    final sorted = Uint8List.fromList(values)..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Watches for the phone being moved after the rim was calibrated.
///
/// Deliberately slow to fire and impossible to un-fire on its own. A false
/// alarm costs one recalibration tap; a missed one costs a whole session of
/// shots scored against the wrong rim, silently. Once displacement is
/// confirmed the only way out is [arm] — the user re-marking the rim — because
/// the app has no way to know where the rim went.
class SceneMonitor {
  /// Median per-cell luma difference above which a frame counts as displaced.
  ///
  /// Guessed from first principles, not measured in a gym. Too low and rebounds
  /// trip it; too high and a real bump slips through. This is the first number
  /// to tune against real footage.
  static const int displacementThreshold = 12;

  /// Consecutive displaced frames required before we believe it — roughly a
  /// second at the frame rates we expect. A hand passing close to the lens can
  /// swamp the grid for a few frames; a moved tripod never comes back.
  static const int framesToConfirm = 15;

  SceneSignature? _reference;
  int _displacedFrames = 0;
  bool _lost = false;

  /// True once displacement has been confirmed and shots should stop counting.
  bool get lost => _lost;

  /// True when a reference frame has been captured and we are actually
  /// watching.
  bool get armed => _reference != null;

  /// Adopt [signature] as the reference scene. Called when the rim is marked.
  void arm(SceneSignature signature) {
    _reference = signature;
    _displacedFrames = 0;
    _lost = false;
  }

  void disarm() {
    _reference = null;
    _displacedFrames = 0;
    _lost = false;
  }

  /// Fold in one frame. Returns true on the frame where displacement is first
  /// confirmed, so the caller can react once rather than every frame after.
  bool update(SceneSignature signature) {
    final reference = _reference;
    if (reference == null || _lost) return false;

    if (signature.differenceFrom(reference) >= displacementThreshold) {
      _displacedFrames++;
      if (_displacedFrames >= framesToConfirm) {
        _lost = true;
        return true;
      }
    } else {
      // Any single settled frame clears the count. The signal we care about is
      // sustained, so intermittent spikes should not accumulate toward it.
      _displacedFrames = 0;
    }
    return false;
  }
}
