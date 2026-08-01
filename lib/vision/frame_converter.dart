import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Turns a camera frame into the square RGB buffer the detector wants.
///
/// The naive approach — convert the whole 1280x720 frame to RGB, then resize —
/// touches nearly a million pixels per frame and will not hold frame rate. We
/// sample straight from the YUV planes into the 320x320 destination instead, so
/// the work is bounded by the model's input size rather than the camera's
/// output size.
class FrameConverter {
  FrameConverter({required this.size});

  /// Model input edge length, in pixels.
  final int size;

  /// Convert a YUV420 camera frame to a tightly packed RGB byte buffer.
  ///
  /// Aspect ratio is not preserved: the frame is stretched to a square. The
  /// detector was trained on square inputs and the distortion is consistent
  /// across every frame, so it costs a little accuracy on box shape but nothing
  /// on whether the ball is found. Since we track box centers rather than box
  /// edges, this is a good trade.
  ///
  /// [quarterTurns] rotates the frame clockwise by that many 90-degree steps on
  /// the way out, so the buffer arrives in *display* orientation. The rotation
  /// is free: we are sampling into the destination anyway, so it costs an index
  /// permutation rather than a second pass over the pixels. Everything
  /// downstream — detections, the tracker, the rim — then lives in one
  /// coordinate space no matter how the phone is held.
  Uint8List convert(CameraImage image, {int quarterTurns = 0}) {
    final out = Uint8List(size * size * 3);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final srcWidth = image.width;
    final srcHeight = image.height;

    final turns = quarterTurns & 3;
    final maxX = srcWidth - 1;
    final maxY = srcHeight - 1;

    var o = 0;
    for (var dy = 0; dy < size; dy++) {
      for (var dx = 0; dx < size; dx++) {
        // Destination (dx, dy) is in display space; walk back to the source
        // pixel it came from. Rotating the *sampling* is the same as rotating
        // the image, without allocating one.
        final int gx;
        final int gy;
        switch (turns) {
          case 1: // source rotated 90 degrees clockwise
            gx = dy;
            gy = size - 1 - dx;
          case 2:
            gx = size - 1 - dx;
            gy = size - 1 - dy;
          case 3:
            gx = size - 1 - dy;
            gy = dx;
          default:
            gx = dx;
            gy = dy;
        }

        final sx = (gx * srcWidth ~/ size).clamp(0, maxX);
        final sy = (gy * srcHeight ~/ size).clamp(0, maxY);

        final yRow = sy * yRowStride;
        final uvRow = (sy >> 1) * uvRowStride;

        final yIndex = yRow + sx;
        final uvIndex = uvRow + (sx >> 1) * uvPixelStride;

        // Guard against short final rows, which some devices report.
        if (yIndex >= yBytes.length || uvIndex >= uBytes.length) {
          o += 3;
          continue;
        }

        final y = yBytes[yIndex];
        final u = uBytes[uvIndex] - 128;
        final v = vBytes[uvIndex] - 128;

        // BT.601 full-range YUV to RGB, in fixed point to avoid per-pixel
        // floating point.
        final r = (y + ((91881 * v) >> 16)).clamp(0, 255);
        final g = (y - ((22554 * u + 46802 * v) >> 16)).clamp(0, 255);
        final b = (y + ((116130 * u) >> 16)).clamp(0, 255);

        out[o++] = r;
        out[o++] = g;
        out[o++] = b;
      }
    }

    return out;
  }
}
