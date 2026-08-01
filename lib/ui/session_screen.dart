import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../domain/make_miss.dart';
import '../domain/models.dart';
import '../session/session_controller.dart';
import 'overlay_painter.dart';

/// The whole app, for now: a camera preview with a scoreboard on it.
///
/// Layout targets a phone propped on the floor or a bag several metres away, so
/// the numbers are deliberately oversized — if you can't read the score from the
/// free-throw line, the app hasn't done its job.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final SessionController _controller = SessionController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return switch (_controller.mode) {
            SessionMode.starting => const _Centered(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            ),
            SessionMode.error => _ErrorView(message: _controller.errorMessage),
            _ => _buildCamera(context),
          };
        },
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    final camera = _controller.camera;
    if (camera == null || !camera.value.isInitialized) {
      return const _Centered(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: camera.value.previewSize?.height ?? size.width,
                height: camera.value.previewSize?.width ?? size.height,
                child: CameraPreview(camera),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                if (_controller.mode != SessionMode.calibrating) return;
                _controller.calibrate(
                  details.localPosition.dx / size.width,
                  details.localPosition.dy / size.height,
                );
              },
              child: CustomPaint(
                painter: OverlayPainter(
                  rim: _controller.rim,
                  ball: _controller.lastBall,
                  trail: _controller.tracker.points,
                  detections: _controller.lastDetections,
                  showDebug: _controller.showDebug,
                  phase: ShotPhase.values.indexOf(_controller.phase),
                ),
              ),
            ),
            if (_controller.mode == SessionMode.calibrating)
              const _CalibrationPrompt(),
            if (_controller.mode == SessionMode.running) ...[
              _Scoreboard(controller: _controller),
              _Controls(controller: _controller),
            ],
            if (_controller.showDebug) _DebugPanel(controller: _controller),
          ],
        );
      },
    );
  }
}

class _CalibrationPrompt extends StatelessWidget {
  const _CalibrationPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app, color: Colors.orangeAccent, size: 56),
          SizedBox(height: 16),
          Text(
            'Tap the rim',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Prop the phone so the whole hoop and the arc of the shot are in '
            'frame, then tap the front of the rim. Keep the phone still after '
            'that — if it moves, tap Recalibrate.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      left: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${controller.makes} / ${controller.attempts}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${controller.percentage.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (controller.unresolved > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${controller.unresolved} unclear — add by hand',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 16,
      bottom: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              _MiniButton(
                icon: Icons.bug_report,
                onTap: controller.toggleDebug,
                active: controller.showDebug,
              ),
              const SizedBox(width: 8),
              _MiniButton(
                icon: Icons.center_focus_strong,
                onTap: controller.recalibrate,
              ),
              const SizedBox(width: 8),
              _MiniButton(
                icon: Icons.restart_alt,
                onTap: () => _confirmReset(context),
              ),
            ],
          ),
          // Manual logging always available. Detection is good, not perfect,
          // and a wrong tally is worse than a slow one.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BigButton(
                label: 'MAKE',
                color: Colors.greenAccent.shade700,
                onTap: () => controller.addManual(ShotResult.make),
              ),
              const SizedBox(height: 10),
              _BigButton(
                label: 'MISS',
                color: Colors.redAccent.shade700,
                onTap: () => controller.addManual(ShotResult.miss),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniButton(icon: Icons.undo, onTap: controller.undoLast),
                  const SizedBox(width: 8),
                  _MiniButton(
                    icon: Icons.swap_horiz,
                    onTap: controller.flipLast,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new session?'),
        content: const Text(
          'This clears the current tally. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok ?? false) await controller.resetSession();
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (active ? Colors.orangeAccent : Colors.black).withValues(
            alpha: 0.6,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final rim = controller.rim;
    return Positioned(
      left: 24,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'fps ${controller.fps.toStringAsFixed(1)}   '
              'infer ${controller.inferenceMs}ms   '
              'phase ${controller.phase.name}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'ball ${controller.lastBall == null ? '—' : '${(controller.lastBall!.score * 100).round()}%'}'
              '   objects ${controller.lastDetections.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            if (rim != null) ...[
              const SizedBox(height: 8),
              const Text(
                'rim width',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              SizedBox(
                width: 220,
                child: Slider(
                  value: rim.halfWidth,
                  min: 0.02,
                  max: 0.15,
                  onChanged: controller.setRimWidth,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(child: child);
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text(
              "Couldn't start the camera",
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
