import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shotbuddy/vision/frame_converter.dart';

/// An 8x8 grey frame with one bright pixel, at source (bx, by).
///
/// Chroma is pinned to neutral so the YUV→RGB maths collapses to r = g = b = y
/// and the test is about geometry only.
YuvFrame frameWithBrightPixel(int bx, int by, {int edge = 8}) {
  final y = Uint8List(edge * edge);
  y[by * edge + bx] = 255;

  final uvEdge = edge ~/ 2;
  final neutral = Uint8List(uvEdge * uvEdge)
    ..fillRange(0, uvEdge * uvEdge, 128);

  return YuvFrame(
    y: y,
    u: neutral,
    v: Uint8List.fromList(neutral),
    width: edge,
    height: edge,
    yRowStride: edge,
    uvRowStride: uvEdge,
    uvPixelStride: 1,
  );
}

/// Red channel of the destination pixel at (x, y).
int redAt(Uint8List rgb, int x, int y, {int edge = 8}) =>
    rgb[(y * edge + x) * 3];

/// The single brightest destination pixel, as (x, y).
(int, int) brightestPixel(Uint8List rgb, {int edge = 8}) {
  var bestX = -1;
  var bestY = -1;
  var best = -1;
  for (var y = 0; y < edge; y++) {
    for (var x = 0; x < edge; x++) {
      final v = redAt(rgb, x, y, edge: edge);
      if (v > best) {
        best = v;
        bestX = x;
        bestY = y;
      }
    }
  }
  return (bestX, bestY);
}

void main() {
  // Portrait support hangs entirely on this rotation being right: the detector
  // is handed frames in display orientation, so if a turn is backwards the ball
  // boxes and the rim tap disagree and every shot is scored against the wrong
  // part of the frame.
  group('FrameConverter rotation', () {
    final converter = FrameConverter(size: 8);

    test('leaves the frame alone at zero quarter-turns', () {
      final rgb = converter.convert(frameWithBrightPixel(0, 0));
      expect(brightestPixel(rgb), (0, 0));
    });

    test('one quarter-turn moves the top-left corner to the top-right', () {
      final rgb = converter.convert(
        frameWithBrightPixel(0, 0),
        quarterTurns: 1,
      );
      expect(brightestPixel(rgb), (7, 0));
    });

    test('two quarter-turns move the top-left corner to the bottom-right', () {
      final rgb = converter.convert(
        frameWithBrightPixel(0, 0),
        quarterTurns: 2,
      );
      expect(brightestPixel(rgb), (7, 7));
    });

    test('three quarter-turns move the top-left corner to the bottom-left', () {
      final rgb = converter.convert(
        frameWithBrightPixel(0, 0),
        quarterTurns: 3,
      );
      expect(brightestPixel(rgb), (0, 7));
    });

    test('rotation is clockwise, not counter-clockwise', () {
      // The corner test alone cannot tell the two apart for 180 degrees, and
      // gets it right by luck for a symmetric frame. An off-axis pixel can.
      final rgb = converter.convert(
        frameWithBrightPixel(1, 0),
        quarterTurns: 1,
      );
      // Clockwise sends (1, 0) to (6, 1); counter-clockwise would send it to
      // (1, 6).
      expect(brightestPixel(rgb), (7, 1));
    });

    test('four quarter-turns is the identity', () {
      final rgb = converter.convert(
        frameWithBrightPixel(2, 5),
        quarterTurns: 4,
      );
      expect(brightestPixel(rgb), (2, 5));
    });
  });

  group('FrameConverter output shape', () {
    test('emits exactly size * size * 3 bytes', () {
      final rgb = FrameConverter(size: 8).convert(frameWithBrightPixel(0, 0));
      expect(rgb.length, 8 * 8 * 3);
    });

    test('stretches a non-square frame to a square without crashing', () {
      // Real frames are 4:3 and get squashed; the point is that the sampler
      // stays inside both planes while doing it.
      final y = Uint8List(16 * 8);
      final uv = Uint8List(8 * 4)..fillRange(0, 8 * 4, 128);
      final frame = YuvFrame(
        y: y,
        u: uv,
        v: uv,
        width: 16,
        height: 8,
        yRowStride: 16,
        uvRowStride: 8,
        uvPixelStride: 1,
      );
      for (var turns = 0; turns < 4; turns++) {
        expect(
          FrameConverter(size: 8).convert(frame, quarterTurns: turns).length,
          8 * 8 * 3,
        );
      }
    });
  });
}
