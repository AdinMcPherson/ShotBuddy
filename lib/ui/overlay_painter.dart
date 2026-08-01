import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Draws the rim gate, the ball box, and the trajectory trail over the preview.
///
/// This is not decoration. If the detector's coordinate space and the preview's
/// coordinate space disagree, the boxes land in the wrong place and the problem
/// is obvious in one second — which is why the overlay is on by default rather
/// than hidden behind debug mode.
class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.rim,
    required this.ball,
    required this.trail,
    required this.detections,
    required this.showDebug,
    required this.phase,
  });

  final RimCalibration? rim;
  final Detection? ball;
  final List<TrackPoint> trail;
  final List<Detection> detections;
  final bool showDebug;
  final int phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (rim != null) _paintRim(canvas, size, rim!);
    if (trail.length > 1) _paintTrail(canvas, size);
    if (ball != null) _paintBall(canvas, size, ball!);
    if (showDebug) _paintOtherDetections(canvas, size);
  }

  void _paintRim(Canvas canvas, Size size, RimCalibration rim) {
    final y = rim.centerY * size.height;
    final left = rim.left * size.width;
    final right = rim.right * size.width;

    // The gate the ball must fall through, drawn solid.
    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = Colors.orangeAccent
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // The rim plane extended, drawn faint — this is the line a miss falls
    // outside of, so seeing it makes the rules legible.
    final faint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(left, y), faint);
    canvas.drawLine(Offset(right, y), Offset(size.width, y), faint);

    for (final x in [left, right]) {
      canvas.drawLine(
        Offset(x, y - 10),
        Offset(x, y + 10),
        Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 3,
      );
    }
  }

  void _paintTrail(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < trail.length; i++) {
      final p = Offset(trail[i].x * size.width, trail[i].y * size.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _paintBall(Canvas canvas, Size size, Detection ball) {
    final rect = Rect.fromLTRB(
      ball.box.left * size.width,
      ball.box.top * size.height,
      ball.box.right * size.width,
      ball.box.bottom * size.height,
    );
    // Colour tracks the shot phase, so the state machine is visible without
    // reading any numbers: white idle, yellow armed, green mid-crossing.
    final color = switch (phase) {
      1 => Colors.yellowAccent,
      2 => Colors.greenAccent,
      _ => Colors.white,
    };
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _paintOtherDetections(Canvas canvas, Size size) {
    for (final d in detections) {
      if (d.label == 'sports ball') continue;
      final rect = Rect.fromLTRB(
        d.box.left * size.width,
        d.box.top * size.height,
        d.box.right * size.width,
        d.box.bottom * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${d.label} ${(d.score * 100).round()}',
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, rect.topLeft + const Offset(2, -12));
    }
  }

  @override
  bool shouldRepaint(covariant OverlayPainter old) => true;
}
