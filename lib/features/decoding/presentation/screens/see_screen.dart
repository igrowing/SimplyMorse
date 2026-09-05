import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/domain/models/track_overlay_info.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Screen for visual Morse decoding via camera.
///
/// Full-screen camera preview with a targeting overlay:
/// - the live preview fills the screen (letterboxed, so the
///   full frame stays visible and the reticle maps 1:1 to the
///   decoder's target area),
/// - a centered reticle shows where to aim the transmitting
///   light — scanning is confined to this area by
///   [VideoDecoder.targetAreaFraction],
/// - a debug aid drawn while the decoder is locked on the source:
///   a yellow circle of twice the detected spot's diameter tracks
///   the brightness-reading region, with a dot/dash label above
///   it showing the live classification of the mark in progress
///   (see [TrackedSpotPainter]),
/// - the top holds the status line (state, WPM, measured FPS)
///   and a translucent box with the decoded text,
/// - the bottom holds all four actions: start/pause, clear,
///   copy, share.
///
/// The top and bottom overlays are sized so they never cover
/// the reticle.
///
/// On web, camera frame streaming is not supported — the
/// screen displays an informational message instead.
class SeeScreen extends StatefulWidget {
  const SeeScreen({
    required this.themeController,
    required this.screenTimeoutService,
    required this.displayTimeout,
    required this.onDisplayTimeoutChanged,
    super.key,
  });

  final ThemeController themeController;
  final ScreenTimeoutService screenTimeoutService;
  final DisplayTimeout displayTimeout;
  final ValueChanged<DisplayTimeout> onDisplayTimeoutChanged;

  @override
  State<SeeScreen> createState() => _SeeScreenState();
}

class _SeeScreenState extends State<SeeScreen> {
  late final DecodingController _controller;
  late final CameraCaptureImpl _cameraCapture;
  late final ShareService _shareService;
  late final FeedbackService _feedbackService;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<DecodingController>();
    _cameraCapture = GetIt.instance<CameraCaptureImpl>();
    _shareService = GetIt.instance<ShareService>();
    _feedbackService = GetIt.instance<FeedbackService>();
    _controller.init(DecodingMode.video);

    // Show the live preview as soon as the camera permission is
    // granted — the user needs to see through the camera to aim
    // at the transmitting light before pressing Start.
    unawaited(
      _controller.checkPermission().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onStartPressed() async {
    await _feedbackService.mediumImpact();
    final granted = await _controller.checkPermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is required to '
            'decode visual Morse code.',
          ),
        ),
      );
      return;
    }

    _controller.start();
  }

  Future<void> _onPausePressed() async {
    await _feedbackService.lightImpact();
    _controller.pause();
  }

  Future<void> _onResumePressed() async {
    await _feedbackService.lightImpact();
    _controller.resume();
  }

  Future<void> _onClearPressed() async {
    await _feedbackService.lightImpact();
    _controller.clear();
    _textController.clear();
  }

  Future<void> _onCopyPressed() async {
    await _feedbackService.lightImpact();
    await _shareService.copyToClipboard(_controller.decodedText);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _onSharePressed() async {
    await _feedbackService.lightImpact();
    await _shareService.share(_controller.decodedText);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebPlaceholder(context);
    }
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        appBar: AppTopBar(
          titleText: 'Watch',
          onSettingsTap: () => _navigateToSettings(context),
        ),
        backgroundColor: Colors.black,
        body: Consumer<DecodingController>(
          builder: (context, ctrl, _) => _buildBody(context, ctrl),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DecodingController ctrl) {
    final camController = _cameraCapture.controller;
    final previewReady =
        camController != null && camController.value.isInitialized;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        // Letterboxed (BoxFit.contain) preview rect — the full
        // frame stays visible, so the centered reticle maps
        // exactly onto the decoder's target area in frame
        // coordinates.
        var previewW = screenW;
        var previewH = screenH;
        if (previewReady) {
          final aspect = camController.value.aspectRatio;
          if (screenW / screenH > aspect) {
            previewH = screenH;
            previewW = previewH * aspect;
          } else {
            previewW = screenW;
            previewH = previewW / aspect;
          }
        }
        final reticleSide =
            VideoDecoder.defaultTargetAreaFraction * min(previewW, previewH);
        // Vertical gap between the screen's top/bottom edge and
        // the reticle's bounding box — the overlays must stay
        // inside it so they never cover the target.
        final reticleEdgeGap = (screenH - reticleSide) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Live preview with the targeting reticle.
            if (previewReady)
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 100,
                    height: 100 / camController.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(camController),
                        Center(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final side =
                                  VideoDecoder.defaultTargetAreaFraction *
                                  min(box.maxWidth, box.maxHeight);
                              return CustomPaint(
                                key: const Key('targeting-reticle'),
                                size: Size.square(side),
                                painter: TargetReticlePainter(
                                  color: ctrl.isListening
                                      ? Colors.greenAccent
                                      : Colors.white,
                                ),
                              );
                            },
                          ),
                        ),
                        // Debug aid: while the decoder is locked on
                        // the source, a yellow circle of twice the
                        // detected spot's diameter marks the tracked
                        // region and a dot/dash label shows the live
                        // mark classification. Painted in the same
                        // coordinate space as the full camera frame,
                        // so the fraction-based telemetry maps 1:1.
                        ValueListenableBuilder<TrackOverlayInfo?>(
                          valueListenable: ctrl.trackOverlay,
                          builder: (context, info, _) {
                            if (info == null) {
                              return const SizedBox.shrink();
                            }
                            return CustomPaint(
                              key: const Key('tracked-spot-overlay'),
                              painter: TrackedSpotPainter(info: info),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              _buildCameraPlaceholder(context),

            // Top: status line + translucent decoded-text box.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusBar(context, ctrl),
                      if (reticleEdgeGap > 120) ...[
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: reticleEdgeGap - 120,
                          ),
                          child: _buildDecodedTextBox(context, ctrl),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Bottom: all four actions in one row.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildBottomButtons(context, ctrl),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Shown when the camera is not available yet.
  Widget _buildCameraPlaceholder(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 64, color: Colors.white54),
          SizedBox(height: 12),
          Text(
            'Camera preview',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// Status line: state, WPM, and the measured capture FPS
  /// while decoding.
  Widget _buildStatusBar(BuildContext context, DecodingController ctrl) {
    final (color, label) = switch (ctrl.status) {
      DecodingStatus.idle => (Colors.white70, 'Idle'),
      DecodingStatus.listening => (Colors.greenAccent, 'Watching…'),
      DecodingStatus.paused => (Colors.amber, 'Paused'),
    };
    final details = <String>[
      if (ctrl.currentWpm > 0) '${ctrl.currentWpm} WPM',
      if (ctrl.isListening && ctrl.captureFps > 0) '${ctrl.captureFps} FPS',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              details.isEmpty ? label : '$label  ·  ${details.join('  ·  ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Half-transparent, editable box with the decoded text.
  Widget _buildDecodedTextBox(
    BuildContext context,
    DecodingController ctrl,
  ) {
    if (_textController.text != ctrl.decodedText) {
      _textController.text = ctrl.decodedText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _textController,
        style: const TextStyle(color: Colors.white),
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: 'Decoded text will appear here…',
          hintStyle: TextStyle(color: Colors.white38),
        ),
        onChanged: ctrl.updateText,
      ),
    );
  }

  /// Start/Pause, Clear, Copy, Share — all four actions in a
  /// single bottom row.
  Widget _buildBottomButtons(
    BuildContext context,
    DecodingController ctrl,
  ) {
    final isStart = ctrl.isIdle;
    final isPause = ctrl.isListening;
    final hasText = ctrl.decodedText.isNotEmpty;

    Widget action({
      required VoidCallback? onPressed,
      required IconData icon,
      required String label,
      bool primary = false,
    }) {
      final style = primary
          ? FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            )
          : OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            );
      final child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
      return Expanded(
        child: primary
            ? FilledButton(
                onPressed: onPressed,
                style: style,
                child: child,
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: style,
                child: child,
              ),
      );
    }

    return Row(
      children: [
        action(
          onPressed: isStart
              ? _onStartPressed
              : isPause
              ? _onPausePressed
              : _onResumePressed,
          icon: isPause ? Icons.pause : Icons.play_arrow,
          label: isStart
              ? 'Start'
              : isPause
              ? 'Pause'
              : 'Resume',
          primary: true,
        ),
        const SizedBox(width: 8),
        action(
          onPressed: hasText || !ctrl.isIdle ? _onClearPressed : null,
          icon: Icons.clear,
          label: 'Clear',
        ),
        const SizedBox(width: 8),
        action(
          onPressed: hasText ? _onCopyPressed : null,
          icon: Icons.copy,
          label: 'Copy',
        ),
        const SizedBox(width: 8),
        action(
          onPressed: hasText ? _onSharePressed : null,
          icon: Icons.share,
          label: 'Share',
        ),
      ],
    );
  }

  /// Shown on web where camera frame streaming is unavailable.
  Widget _buildWebPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppTopBar(
        onSettingsTap: () => _navigateToSettings(context),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Watch mode is not available on web',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Camera frame streaming is not supported in '
                'browsers. Use the Hear mode for audio-based '
                'Morse decoding, or run the app on a mobile '
                'device for video decoding.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            themeController: widget.themeController,
            screenTimeoutService: widget.screenTimeoutService,
            themeMode: widget.themeController.mode,
            displayTimeout: widget.displayTimeout,
            onDisplayTimeoutChanged: widget.onDisplayTimeoutChanged,
          ),
        ),
      ),
    );
  }
}

/// Draws the aiming reticle: four corner brackets, a faint full
/// square outline, and a small center dot.
///
/// The reticle marks the decoder's target area — scanning and
/// tracking only consider pixels inside it, so the user must
/// keep the transmitting light within the brackets.
class TargetReticlePainter extends CustomPainter {
  TargetReticlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bracket = size.width * 0.22;
    final backPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final outline = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rect = Offset.zero & size;

    // Faint outline of the full target area.
    canvas.drawRect(rect, outline);

    final paths = <Path>[
      Path()
        ..moveTo(0, bracket)
        ..lineTo(0, 0)
        ..lineTo(bracket, 0),
      Path()
        ..moveTo(size.width - bracket, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, bracket),
      Path()
        ..moveTo(size.width, size.height - bracket)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width - bracket, size.height),
      Path()
        ..moveTo(bracket, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, size.height - bracket),
    ];
    for (final p in paths) {
      canvas
        ..drawPath(p, backPaint)
        ..drawPath(p, paint);
    }

    // Center dot.
    final center = Offset(size.width / 2, size.height / 2);
    final dotBack = Paint()..color = Colors.black54;
    final dot = Paint()..color = color;
    canvas
      ..drawCircle(center, 4, dotBack)
      ..drawCircle(center, 2.5, dot);
  }

  @override
  bool shouldRepaint(TargetReticlePainter old) => old.color != color;
}

/// Debug aid drawn over the live preview while the decoder is
/// locked on the transmitting light: a yellow circle of **twice**
/// the detected spot's diameter, centered on the tracked
/// brightness-reading region, and — while a mark is in progress —
/// a dot/dash label above it showing the live classification.
///
/// The overlay exists to answer two debugging questions at a
/// glance: *is the signal locked?* (the circle is only drawn in
/// the locked state) and *how well is it being tracked?* (the
/// circle should hug the light as it moves; lag or jitter shows
/// tracking trouble).
///
/// Geometry: [TrackOverlayInfo] carries the region center as frame
/// fractions and the region size in processing-frame pixels
/// (80×60). The preview stack this painter lives in shows the full
/// captured frame 1:1, so center = fraction × canvas size and the
/// spot's diameter = `regionSizePx / 80 × canvas.width`. Both the
/// processing frame and the captured frame are 4:3, so the
/// horizontal scale maps the region square faithfully.
class TrackedSpotPainter extends CustomPainter {
  TrackedSpotPainter({required this.info});

  final TrackOverlayInfo info;

  /// Width of the processing frame the region size is expressed
  /// in — see `CameraCaptureImpl._processImage`.
  static const double _processingWidth = 80;

  /// Tracked-region center in preview coordinates.
  ///
  /// The preview stack shows the full captured frame 1:1, so a
  /// fraction of the frame is the same fraction of the canvas.
  static Offset centerOf(TrackOverlayInfo info, Size size) => Offset(
    info.centerX * size.width,
    info.centerY * size.height,
  );

  /// The debug circle's radius: twice the detected spot's
  /// *diameter*, i.e. the spot's full size serves as the radius.
  static double radiusOf(TrackOverlayInfo info, Size size) =>
      spotDiameterOf(info, size);

  /// The detected spot's diameter in preview pixels.
  static double spotDiameterOf(TrackOverlayInfo info, Size size) =>
      info.regionSizePx * size.width / _processingWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerOf(info, size);
    final spotDiameter = spotDiameterOf(info, size);
    final circlePaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Double the spot's diameter: the circle visually envelops
    // the light with a clear margin, so tracking quality is easy
    // to judge at a glance.
    canvas.drawCircle(center, radiusOf(info, size), circlePaint);

    // Label: live classification of the mark in progress. Hidden
    // while the signal is off, and until enough marks have been
    // seen for a robust dit estimate (the decoder reports that via
    // markClassified rather than guessing).
    if (!info.signalOn || !info.markClassified) return;

    final label = info.isDash ? 'dash' : 'dot';
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const pad = 4.0;
    final textTop = (center.dy - spotDiameter - text.height - 2 * pad - 6)
        .clamp(0.0, size.height - text.height - 2 * pad);
    final textLeft = (center.dx - text.width / 2 - pad).clamp(
      0.0,
      size.width - text.width - 2 * pad,
    );

    final scrimRect = Rect.fromLTWH(
      textLeft,
      textTop,
      text.width + 2 * pad,
      text.height + 2 * pad,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scrimRect, const Radius.circular(4)),
      Paint()..color = Colors.black54,
    );
    text.paint(canvas, Offset(textLeft + pad, textTop + pad));
  }

  @override
  bool shouldRepaint(TrackedSpotPainter old) => old.info != info;
}
