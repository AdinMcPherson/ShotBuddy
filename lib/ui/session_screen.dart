import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../domain/make_miss.dart';
import '../domain/models.dart';
import '../session/session_controller.dart';
import 'overlay_painter.dart';

/// The whole app, for now: a camera preview with a scoreboard around it.
///
/// Works in both orientations. Landscape is how you would prop a phone against
/// a bag to film a hoop; portrait is how you hold it when you are the one
/// shooting and want to glance at the tally between reps. The two get genuinely
/// different layouts rather than one stretched to fit — in portrait the screen
/// is tall enough to give the controls their own band under the preview, and in
/// landscape it is not, so they float over it.
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The camera sensor is landscape on every phone we support, so portrait
    // needs the frame turned a quarter before the detector sees it. This is the
    // one place that knows which way up we are, so it is the one place that
    // decides.
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    _controller.setDisplayRotation(portrait ? 1 : 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return switch (_controller.mode) {
            SessionMode.starting => const _Centered(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            ),
            SessionMode.error => _ErrorView(message: _controller.errorMessage),
            _ => _buildSession(context),
          };
        },
      ),
    );
  }

  Widget _buildSession(BuildContext context) {
    final camera = _controller.camera;
    if (camera == null || !camera.value.isInitialized) {
      return const _Centered(child: CircularProgressIndicator());
    }

    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return SafeArea(
      child: portrait ? _portraitLayout(camera) : _landscapeLayout(camera),
    );
  }

  Widget _portraitLayout(CameraController camera) {
    return Column(
      children: [
        _StatsHeader(controller: _controller, compact: false),
        Expanded(child: _preview(camera)),
        _ShotStrip(controller: _controller),
        _ControlBar(controller: _controller),
      ],
    );
  }

  Widget _landscapeLayout(CameraController camera) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _preview(camera),
        Positioned(
          top: 12,
          left: 12,
          child: _StatsHeader(controller: _controller, compact: true),
        ),
        Positioned(
          right: 12,
          top: 12,
          bottom: 12,
          child: _ControlRail(controller: _controller),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: _ShotStrip(controller: _controller, floating: true),
        ),
      ],
    );
  }

  /// The preview, letterboxed to the camera's real aspect ratio.
  ///
  /// Deliberately `contain`, not `cover`. The detector sees the whole frame, so
  /// cropping the preview would put the ball boxes somewhere the user cannot
  /// see and — worse — would mean a tap on the rim landed on different pixels
  /// than the ones the detector is reasoning about. Letterboxing keeps one
  /// coordinate space end to end, and on a hoop you want the full field of view
  /// anyway.
  Widget _preview(CameraController camera) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final sensorAspect = camera.value.aspectRatio;
    final aspect = portrait ? 1 / sensorAspect : sensorAspect;

    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(camera),
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
                if (_controller.mode == SessionMode.rimLost)
                  _RimLostPrompt(onRecalibrate: _controller.recalibrate),
                if (_controller.showDebug)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _DebugPanel(controller: _controller),
                  ),
              ],
            );
          },
        ),
      ),
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
      padding: const EdgeInsets.all(24),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, color: Colors.orangeAccent, size: 48),
          SizedBox(height: 12),
          Text(
            'Tap the rim',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Prop the phone so the whole hoop and the arc of the shot are in '
            'frame, then tap the front of the rim. Keep the phone still after '
            'that — if it moves, tap Recalibrate.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Shown when the phone appears to have been moved after calibration.
///
/// Loud on purpose. The failure this guards against is silent — shots scored
/// against a rim that is no longer where the user pointed — so the recovery has
/// to be impossible to miss and impossible to ignore. Automatic counting is
/// already stopped by the time this appears; manual MAKE/MISS still works, so
/// the user is never stuck.
class _RimLostPrompt extends StatelessWidget {
  const _RimLostPrompt({required this.onRecalibrate});

  final VoidCallback onRecalibrate;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.screen_rotation_alt,
            color: Colors.redAccent,
            size: 44,
          ),
          const SizedBox(height: 12),
          const Text(
            'Rim lost — the phone moved',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Counting has stopped rather than score shots against a rim that '
            'is no longer where you marked it. Put the phone back or mark the '
            'rim again. Your tally so far is safe, and MAKE / MISS still work '
            'by hand.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRecalibrate,
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Mark the rim again'),
          ),
        ],
      ),
    );
  }
}

/// Makes, attempts, percentage, streak, and clock.
///
/// [compact] is the landscape variant: the same numbers in a floating card,
/// because in landscape there is no spare band to give them.
class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.controller, required this.compact});

  final SessionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pct = controller.percentage;
    final card = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: compact ? 0.55 : 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${controller.makes} / ${controller.attempts}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 40 : 46,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'makes / attempts',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: _pctColor(pct),
                  fontSize: compact ? 26 : 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'last 10 · ${controller.recentPercentage().toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (!compact) const Spacer(),
          if (!compact) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StreakChip(
                  current: controller.currentStreak,
                  best: controller.bestStreak,
                ),
                const SizedBox(height: 6),
                Text(
                  _clock(controller.elapsed),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (compact) return card;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          if (controller.unresolved > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(
                '${controller.unresolved} unclear — add by hand',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static Color _pctColor(double pct) {
    if (pct >= 60) return Colors.greenAccent.shade400;
    if (pct >= 40) return Colors.orangeAccent;
    return Colors.redAccent.shade200;
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.current, required this.best});

  final int current;
  final int best;

  @override
  Widget build(BuildContext context) {
    final hot = current >= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hot
            ? Colors.orangeAccent.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hot ? Icons.local_fire_department : Icons.trending_flat,
            size: 15,
            color: hot ? Colors.orangeAccent : Colors.white38,
          ),
          const SizedBox(width: 5),
          Text(
            '$current  ·  best $best',
            style: TextStyle(
              color: hot ? Colors.orangeAccent : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The last dozen shots as dots, newest on the right.
///
/// Cheap to read at a glance from the free-throw line, and it makes a cold or
/// hot run visible as a shape rather than a number you have to think about.
class _ShotStrip extends StatelessWidget {
  const _ShotStrip({required this.controller, this.floating = false});

  final SessionController controller;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final shots = controller.recentShots();
    if (shots.isEmpty) return const SizedBox.shrink();

    final strip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in shots)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.result == ShotResult.make
                    ? Colors.greenAccent.shade400
                    : Colors.redAccent.shade200,
                // A ring marks a call the user corrected by hand, so the strip
                // shows what the model got right, not just what the score is.
                border: s.correctedByUser
                    ? Border.all(color: Colors.white70, width: 1.5)
                    : null,
              ),
            ),
          ),
      ],
    );

    if (floating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: strip,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: strip,
    );
  }
}

/// Portrait controls: a band under the preview.
class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          // Manual logging always available. Detection is good, not perfect,
          // and a wrong tally is worse than a slow one.
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  label: 'MAKE',
                  icon: Icons.check,
                  color: Colors.greenAccent.shade700,
                  onTap: () => controller.addManual(ShotResult.make),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigButton(
                  label: 'MISS',
                  icon: Icons.close,
                  color: Colors.redAccent.shade700,
                  onTap: () => controller.addManual(ShotResult.miss),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _utilityButtons(context, controller),
          ),
        ],
      ),
    );
  }
}

/// Landscape controls: a rail down the right edge, over the preview.
class _ControlRail extends StatelessWidget {
  const _ControlRail({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in _utilityButtons(context, controller))
              Padding(padding: const EdgeInsets.only(left: 8), child: b),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 130,
              child: _BigButton(
                label: 'MAKE',
                icon: Icons.check,
                color: Colors.greenAccent.shade700,
                onTap: () => controller.addManual(ShotResult.make),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 130,
              child: _BigButton(
                label: 'MISS',
                icon: Icons.close,
                color: Colors.redAccent.shade700,
                onTap: () => controller.addManual(ShotResult.miss),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Undo, flip, recalibrate, debug, reset — shared by both layouts so the two
/// orientations cannot drift apart in what they offer.
List<Widget> _utilityButtons(
  BuildContext context,
  SessionController controller,
) => [
  _MiniButton(
    icon: Icons.undo,
    label: 'Undo',
    onTap: controller.undoLast,
    enabled: controller.attempts > 0,
  ),
  _MiniButton(
    icon: Icons.swap_horiz,
    label: 'Flip',
    onTap: controller.flipLast,
    enabled: controller.attempts > 0,
  ),
  _MiniButton(
    icon: Icons.center_focus_strong,
    label: 'Rim',
    onTap: controller.recalibrate,
  ),
  _MiniButton(
    icon: Icons.bug_report,
    label: 'Debug',
    onTap: controller.toggleDebug,
    active: controller.showDebug,
  ),
  _MiniButton(
    icon: Icons.restart_alt,
    label: 'Reset',
    onTap: () => _confirmReset(context, controller),
  ),
];

Future<void> _confirmReset(
  BuildContext context,
  SessionController controller,
) async {
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

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 62,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
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
    this.label,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tint = active ? Colors.orangeAccent : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: (active ? Colors.orangeAccent : Colors.black).withValues(
              alpha: active ? 0.25 : 0.55,
            ),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, color: tint, size: 22),
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: TextStyle(
                color: tint.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          ],
        ],
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
    return Container(
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
              width: 200,
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
