import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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
import 'package:simply_morse/features/info/presentation/screens/info_screen.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Screen for visual Morse decoding via camera.
///
/// The live preview (built by `_buildCameraArea`) is shared by both
/// orientations: letterboxed (contain-fit, no crop) so the full
/// captured frame is always visible, scaled to the largest size
/// that fits whatever box it's given, with black bars filling the
/// rest — on the sides in landscape, top/bottom in portrait.
/// Nothing outside the frame is ever hidden, so the full field of
/// view stays available for aiming. A centered corner-bracket
/// reticle shows where to aim the transmitting light — it sits
/// inside the decoder's scan area ([VideoDecoder.targetAreaFraction])
/// with margin to spare (see [VideoDecoder.reticleFraction]), and the
/// inside is clean so nothing blocks the view of the light — and a
/// debug aid drawn while the decoder is locked on the source (a
/// yellow circle of twice the detected spot's diameter, with a
/// dot/dash label above it showing the live classification of the
/// mark in progress; see [TrackedSpotPainter]) shares the same
/// coordinate space.
///
/// Everything else differs by orientation, since a bottom-heavy
/// phone-in-portrait layout doesn't suit a landscape grip:
/// - **Portrait** (`_buildPortraitBody`): the preview fills the
///   screen behind everything else, with the status line and
///   decoded text translucent-overlaid at the top and the four
///   actions (two rows of two) translucent-overlaid at the bottom
///   — sized so they never cover the reticle.
/// - **Landscape** (`_buildLandscapeBody`): a real side-by-side
///   split instead of overlays — status bar pinned to the top,
///   decoded text in a dedicated left panel (always visible,
///   unlike portrait's overlay it isn't gated on leftover space
///   above the reticle), the preview in the middle, and the four
///   actions stacked in a right-hand column within thumb reach of
///   a landscape grip.
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

    // TEMP DEBUG: see _showVideoDebugLogSnackBar's doc comment.
    // The path is set asynchronously inside VideoDebugLogger.start()
    // (it awaits getApplicationDocumentsDirectory()), so give it a
    // moment before reading it.
    if (_controller.isVideoDebugLoggingEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _showVideoDebugLogSnackBar();
    }
  }

  Future<void> _onPausePressed() async {
    await _feedbackService.lightImpact();
    _controller.pause();

    // TEMP DEBUG: re-offer the share action once there's actually
    // decoder data in the log (at Start, the file has only just
    // been created) — see _showVideoDebugLogSnackBar.
    if (_controller.isVideoDebugLoggingEnabled) {
      _showVideoDebugLogSnackBar();
    }
  }

  Future<void> _onResumePressed() async {
    await _feedbackService.lightImpact();
    _controller.resume();
  }

  /// TEMP DEBUG: offers to share the video debug log's CSV file.
  /// Remove this together with the `enabled: true` override in
  /// injection.dart once the video decoder investigation is done.
  ///
  /// The file lives in `getApplicationDocumentsDirectory()`, which
  /// on Android is app-PRIVATE internal storage (`/data/user/0/`
  /// followed by the package name, not anything under
  /// `/storage/emulated/0/`) — no Files app can browse it, and it
  /// isn't reachable over
  /// USB/MTP either. Showing the path alone (the previous approach
  /// here) is therefore useless without adb or a rooted device.
  /// Sharing the file directly via the system share sheet sidesteps
  /// needing filesystem access at all — the user can send it to
  /// email/Drive/etc. or open it with an app that understands CSV.
  void _showVideoDebugLogSnackBar() {
    final path = _controller.videoDebugLogPath;
    debugPrint('Video debug log: $path');
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Video debug log ready'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () {
            unawaited(
              SharePlus.instance.share(
                ShareParams(files: [XFile(path)]),
              ),
            );
          },
        ),
      ),
    );
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
    // The full AppBar (title + settings icon, kToolbarHeight tall)
    // is dropped in landscape — that fixed height is a much bigger
    // fraction of a landscape screen's already-short vertical space
    // than of a portrait one. Landscape gets just a small
    // translucent back button instead, folded into the status row
    // (see _buildLandscapeBody) rather than reserved app-bar space;
    // Settings becomes reachable by rotating to portrait.
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        appBar: isLandscape
            ? null
            : AppTopBar(
                titleText: 'Watch',
                onSettingsTap: () => _navigateToSettings(context),
                onInfoTap: () => _navigateToInfo(context),
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
        // Device-level orientation — NOT the shape of whatever box
        // a given piece of UI ends up with (the landscape layout's
        // camera area, for instance, is narrower than the full
        // screen once the side panels are subtracted, and could
        // even end up taller than wide on a small enough device;
        // that must not flip the sensor-rotation correction, which
        // depends on how the *device* — not some sub-box — is held).
        final isPortrait = constraints.maxHeight > constraints.maxWidth;
        return isPortrait
            ? _buildPortraitBody(
                context,
                ctrl,
                constraints,
                camController,
                previewReady,
              )
            : _buildLandscapeBody(context, ctrl, camController, previewReady);
      },
    );
  }

  /// Portrait layout: the live preview fills the screen behind
  /// everything else, with the status line + decoded text
  /// translucent-overlaid at the top and the four actions
  /// translucent-overlaid at the bottom.
  Widget _buildPortraitBody(
    BuildContext context,
    DecodingController ctrl,
    BoxConstraints constraints,
    CameraController? camController,
    bool previewReady,
  ) {
    final screenW = constraints.maxWidth;
    final screenH = constraints.maxHeight;

    // Contain-fit preview geometry, duplicated from _buildCameraArea
    // (which computes the same thing internally once it's given
    // this same full-screen box) — needed here ahead of time only
    // to size the reticle-relative gap that gates the decoded-text
    // overlay below.
    var scaledW = screenW;
    var scaledH = screenH;
    if (previewReady) {
      final sensorAspect = camController!.value.aspectRatio;
      final aspect = 1 / sensorAspect;
      if (screenW / screenH > aspect) {
        scaledH = screenH;
        scaledW = screenH * aspect;
      } else {
        scaledW = screenW;
        scaledH = screenW / aspect;
      }
    }
    final reticleSide = VideoDecoder.reticleFraction * min(scaledW, scaledH);
    // Vertical gap between the screen's top/bottom edge and the
    // reticle's bounding box — the overlays must stay inside it so
    // they never cover the target.
    final reticleEdgeGap = (screenH - reticleSide) / 2;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraArea(
          context,
          ctrl,
          camController,
          previewReady,
          isPortrait: true,
        ),

        // Top: status line + translucent decoded-text box. The
        // text box only shows if there's room left over above the
        // reticle without covering it — on a landscape screen this
        // gap can shrink to nothing (see _buildLandscapeBody, which
        // gives the text its own dedicated panel instead).
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
  }

  /// Width of the decoded-text panel in the landscape layout.
  static const double _landscapeTextPanelWidth = 240;

  /// Width of the action-button column in the landscape layout.
  static const double _landscapeButtonPanelWidth = 140;

  /// Landscape layout: a real side-by-side split rather than
  /// overlays on top of the camera, since overlaying left the
  /// decoded-text box with nowhere to go once the letterboxed
  /// preview stopped guaranteeing a tall gap above the reticle (it
  /// simply never showed — see the portrait branch's comment) and
  /// put the action buttons in a bottom strip that's awkward to
  /// reach one-handed in landscape. No AppBar (see [build]) — a
  /// small translucent back button sits directly left of the status
  /// bar instead, both pinned to the top; decoded text gets a
  /// dedicated left panel that's always visible; actions become a
  /// right-hand column, within thumb reach of a landscape grip.
  Widget _buildLandscapeBody(
    BuildContext context,
    DecodingController ctrl,
    CameraController? camController,
    bool previewReady,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBackButton(context),
                const SizedBox(width: 8),
                _buildStatusBar(context, ctrl),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _landscapeTextPanelWidth,
                    child: _buildDecodedTextBox(context, ctrl, expand: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCameraArea(
                      context,
                      ctrl,
                      camController,
                      previewReady,
                      isPortrait: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: _landscapeButtonPanelWidth,
                    child: _buildSideButtons(context, ctrl),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small translucent back button standing in for the AppBar that
  /// [build] omits in landscape — same action (`maybePop`) and
  /// tooltip as [AppTopBar]'s own back button, just without the
  /// fixed-height bar around it. Hidden when there's nowhere to pop
  /// back to (matching AppTopBar's own behavior).
  Widget _buildBackButton(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// The live preview with the targeting reticle and the
  /// tracked-spot debug overlay, contain-fitted (letterboxed) to
  /// whatever box it's given — reused by both the portrait
  /// (full-screen) and landscape (center panel) layouts.
  ///
  /// [isPortrait] must reflect the DEVICE's orientation, not this
  /// widget's own box shape — see the comment in [_buildBody].
  Widget _buildCameraArea(
    BuildContext context,
    DecodingController ctrl,
    CameraController? camController,
    bool previewReady, {
    required bool isPortrait,
  }) {
    if (!previewReady) return _buildCameraPlaceholder(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // camController.value.aspectRatio is always the camera's
        // raw SENSOR (landscape) aspect ratio, regardless of how
        // the phone is held — CameraPreview itself corrects for
        // this internally (see its `_isLandscape()` check), but
        // that correction only kicks in when CameraPreview is
        // given a loose box to size itself; the box handed to it
        // below needs the same correction applied up front.
        final sensorAspect = camController!.value.aspectRatio;
        final aspect = isPortrait ? 1 / sensorAspect : sensorAspect;

        return Center(
          // Contain-fit (BoxFit.contain): AspectRatio picks the
          // largest box of the right shape that fits within
          // whatever space this widget was given, so the full
          // field of view is always visible — black bars fill the
          // rest on whichever axis has room to spare. The overlays
          // inside the child Stack stay in the full frame's 1:1
          // coordinate space, so they line up regardless of how big
          // the letterboxed box ends up.
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(camController),
                Center(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final side =
                          VideoDecoder.reticleFraction *
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
                // Debug aid: while the decoder is locked on the
                // source, a yellow circle of twice the detected
                // spot's diameter marks the tracked region and a
                // dot/dash label shows the live mark
                // classification. Painted in the same coordinate
                // space as the full camera frame, so the
                // fraction-based telemetry maps 1:1.
                ValueListenableBuilder<TrackOverlayInfo?>(
                  valueListenable: ctrl.trackOverlay,
                  builder: (context, info, _) {
                    if (info == null) return const SizedBox.shrink();
                    return CustomPaint(
                      key: const Key('tracked-spot-overlay'),
                      painter: TrackedSpotPainter(
                        info: info,
                        isPortrait: isPortrait,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
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

  static const double _statusBarHorizontalPadding = 14;
  static const double _statusBarIconSize = 10;
  static const double _statusBarIconGap = 8;

  /// Status line: state, camera capture resolution, capture FPS,
  /// the sending speed that rate can decode cleanly ("up to N WPM",
  /// see [DecodingController.maxDecodableWpm]), and — once elements
  /// are arriving — the WPM actually being received.
  ///
  /// Adding the resolution alongside WPM/FPS made this line long
  /// enough to risk not fitting a narrow phone width — rather than
  /// silently ellipsizing away trailing detail (e.g. the FPS),
  /// measure it against the space actually available and fall back
  /// to a second line (state on top, details below) when it
  /// doesn't fit.
  Widget _buildStatusBar(BuildContext context, DecodingController ctrl) {
    final (color, label) = switch (ctrl.status) {
      DecodingStatus.idle => (Colors.white70, 'Idle'),
      DecodingStatus.listening => (Colors.greenAccent, 'Watching…'),
      DecodingStatus.paused => (Colors.amber, 'Paused'),
    };
    // The raw capture resolution — shown so a visibly cropped/
    // narrow field of view can be traced back to how low a
    // resolution ResolutionPreset.low actually granted, rather
    // than only to the letterbox/crop fit itself.
    final previewSize = _cameraCapture.controller?.value.previewSize;
    // The camera negotiates its capture rate as soon as it
    // initializes (see CameraCaptureImpl.initialize's fallback
    // chain) — well before Start is pressed — so that rate is
    // known, and worth showing, from Idle onward. Once actually
    // streaming, the MEASURED rate is more informative (it catches
    // a platform silently delivering less than it granted), so
    // switch to that instead.
    final fps = ctrl.isListening ? ctrl.captureFps : _cameraCapture.frameRate;
    // The sending speed this frame rate can decode cleanly. Shown so
    // the operator knows the ceiling up front — a faster transmission
    // is still accepted, just with more errors (see
    // DecodingController.maxDecodableWpm).
    final maxWpm = DecodingController.maxDecodableWpm(fps);
    final details = <String>[
      if (previewSize != null)
        '${previewSize.width.round()}×${previewSize.height.round()}',
      if (previewSize != null && fps > 0) '$fps FPS',
      if (previewSize != null && maxWpm > 0) 'up to $maxWpm WPM',
      if (ctrl.currentWpm > 0) '${ctrl.currentWpm} WPM now',
    ];
    final style = TextStyle(color: color, fontSize: 14);
    final detailsText = details.join(' · ');
    final oneLineText = details.isEmpty ? label : '$label · $detailsText';

    return LayoutBuilder(
      builder: (context, constraints) {
        final textBudget =
            constraints.maxWidth -
            _statusBarHorizontalPadding * 2 -
            _statusBarIconSize -
            _statusBarIconGap;
        final painter = TextPainter(
          text: TextSpan(text: oneLineText, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: max(0, textBudget));
        final fitsOneLine = !painter.didExceedMaxLines;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: _statusBarHorizontalPadding,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(24),
          ),
          child: fitsOneLine || details.isEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: _statusBarIconSize,
                      color: color,
                    ),
                    const SizedBox(width: _statusBarIconGap),
                    Flexible(
                      child: Text(
                        oneLineText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: _statusBarIconSize,
                          color: color,
                        ),
                        const SizedBox(width: _statusBarIconGap),
                        Text(label, style: style),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _statusBarIconSize + _statusBarIconGap,
                      ),
                      // Each detail is its own chip in a Wrap so the
                      // line breaks at the ` · ` separators and every
                      // field stays readable on a narrow phone —
                      // rather than one Text that ellipsizes the
                      // trailing fields (FPS, WPM) away entirely.
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (var i = 0; i < details.length; i++)
                            Text(
                              i == details.length - 1
                                  ? details[i]
                                  : '${details[i]} ·',
                              style: style,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// Half-transparent, editable box with the decoded text.
  ///
  /// [expand] makes the field fill whatever height its parent
  /// gives it instead of sizing to at most 3 lines — used for the
  /// landscape layout's dedicated text panel, which has real
  /// vertical room to spare (see [_buildLandscapeBody]).
  Widget _buildDecodedTextBox(
    BuildContext context,
    DecodingController ctrl, {
    bool expand = false,
  }) {
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
        expands: expand,
        maxLines: expand ? null : 3,
        minLines: expand ? null : 1,
        textAlignVertical: expand ? TextAlignVertical.top : null,
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

  /// Builds the four action buttons (Start/Pause/Resume, Clear,
  /// Copy, Share) as a list — each already `Expanded`, ready to
  /// drop into a `Row` (portrait, two per row) or a `Column`
  /// (landscape, one per row) without repeating their config.
  List<Widget> _buildActionButtons(
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

    return [
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
      action(
        onPressed: hasText || !ctrl.isIdle ? _onClearPressed : null,
        icon: Icons.clear,
        label: 'Clear',
      ),
      action(
        onPressed: hasText ? _onCopyPressed : null,
        icon: Icons.copy,
        label: 'Copy',
      ),
      action(
        onPressed: hasText ? _onSharePressed : null,
        icon: Icons.share,
        label: 'Share',
      ),
    ];
  }

  /// The four actions in two rows: Start/Pause + Clear on the
  /// first, Copy + Share on the second — each button stays wide
  /// enough to read and tap comfortably. Used in the portrait
  /// layout's bottom strip.
  Widget _buildBottomButtons(
    BuildContext context,
    DecodingController ctrl,
  ) {
    final actions = _buildActionButtons(context, ctrl);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [actions[0], const SizedBox(width: 8), actions[1]]),
        const SizedBox(height: 8),
        Row(children: [actions[2], const SizedBox(width: 8), actions[3]]),
      ],
    );
  }

  /// The four actions stacked vertically — used in the landscape
  /// layout's right-hand column, within thumb reach of a landscape
  /// grip rather than a bottom strip that's awkward to reach
  /// one-handed in that orientation.
  Widget _buildSideButtons(
    BuildContext context,
    DecodingController ctrl,
  ) {
    final actions = _buildActionButtons(context, ctrl);
    return Column(
      children: [
        actions[0],
        const SizedBox(height: 8),
        actions[1],
        const SizedBox(height: 8),
        actions[2],
        const SizedBox(height: 8),
        actions[3],
      ],
    );
  }

  /// Shown on web where camera frame streaming is unavailable.
  Widget _buildWebPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppTopBar(
        onSettingsTap: () => _navigateToSettings(context),
        onInfoTap: () => _navigateToInfo(context),
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

  void _navigateToInfo(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const InfoScreen()),
      ),
    );
  }
}

/// Draws the aiming reticle: four corner brackets and nothing
/// else — the inside of the target area stays clean so the
/// transmitting light is never visually blocked. (While the
/// decoder is locked on the source, the tracked-spot debug
/// circle is drawn there.)
///
/// The reticle marks a safe sub-region of the decoder's scan area
/// (see [VideoDecoder.reticleFraction]): a light kept within the
/// brackets is well inside the area scanning and tracking consider,
/// clear of its block-quantized edge.
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
/// Geometry: [TrackOverlayInfo] carries the region center as
/// fractions of the RAW processing buffer (80×60, always in SENSOR
/// — landscape — orientation, see `CameraCaptureImpl._processImage`)
/// and the region size in that same buffer's pixels. The preview
/// stack this painter lives in shows the buffer cover-fitted into a
/// box shaped for the *display* orientation, which in portrait is
/// rotated 90° relative to the buffer — so a raw fraction cannot be
/// read directly as a canvas fraction; see
/// [frameFractionToDisplayFraction].
class TrackedSpotPainter extends CustomPainter {
  TrackedSpotPainter({required this.info, required this.isPortrait});

  final TrackOverlayInfo info;

  /// Whether the canvas this painter draws into is portrait-shaped
  /// (taller than wide) rather than landscape — see
  /// [frameFractionToDisplayFraction].
  final bool isPortrait;

  /// Width of the processing frame the region size is expressed
  /// in — see `CameraCaptureImpl._processImage`.
  static const double _processingWidth = 80;

  /// Height of the processing frame — see [_processingWidth].
  static const double _processingHeight = 60;

  /// Rotates a fraction-of-processing-buffer point into a
  /// fraction-of-canvas point.
  ///
  /// The processing buffer is always captured in the camera's raw
  /// SENSOR orientation (landscape-shaped), regardless of how the
  /// phone is held. In landscape UI orientation the displayed
  /// picture is that same buffer un-rotated, so a buffer fraction
  /// already is a canvas fraction. In portrait, the display is
  /// rotated 90° relative to the buffer (the standard rear-camera
  /// mounting, sensorOrientation ≈ 90°), so the point must undergo
  /// the same rotation: a point at (fx, fy) in a 90°-clockwise-
  /// rotated image moves to (1 - fy, fx).
  ///
  /// This follows the standard sensor-mounting convention, but has
  /// not been checked against a physical device for every UI
  /// orientation — if the yellow tracking circle lands rotated or
  /// mirrored on a real phone, this is the formula to revisit.
  static Offset frameFractionToDisplayFraction(
    Offset frameFraction, {
    required bool isPortrait,
  }) {
    if (!isPortrait) return frameFraction;
    return Offset(1 - frameFraction.dy, frameFraction.dx);
  }

  /// Tracked-region center in preview coordinates.
  static Offset centerOf(
    TrackOverlayInfo info,
    Size size, {
    required bool isPortrait,
  }) {
    final f = frameFractionToDisplayFraction(
      Offset(info.centerX, info.centerY),
      isPortrait: isPortrait,
    );
    return Offset(f.dx * size.width, f.dy * size.height);
  }

  /// The debug circle's radius: twice the detected spot's
  /// *diameter*, i.e. the spot's full size serves as the radius.
  static double radiusOf(
    TrackOverlayInfo info,
    Size size, {
    required bool isPortrait,
  }) => spotDiameterOf(info, size, isPortrait: isPortrait);

  /// The detected spot's diameter in preview pixels.
  ///
  /// [TrackOverlayInfo.regionSizePx] is measured along the
  /// processing buffer's own axes. In portrait, the buffer axis
  /// that maps onto the canvas's *width* is the buffer's HEIGHT
  /// axis (60px) — the 90° rotation swaps them — not its width
  /// (80px); see [frameFractionToDisplayFraction].
  static double spotDiameterOf(
    TrackOverlayInfo info,
    Size size, {
    required bool isPortrait,
  }) {
    final referenceWidth = isPortrait ? _processingHeight : _processingWidth;
    return info.regionSizePx * size.width / referenceWidth;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerOf(info, size, isPortrait: isPortrait);
    final spotDiameter = spotDiameterOf(info, size, isPortrait: isPortrait);
    final circlePaint = Paint()
      // Dimmed while the decoder is only holding the lock through a
      // gap (no live signal to track) rather than actively tracking.
      ..color = info.holding
          ? Colors.yellow.withValues(alpha: 0.35)
          : Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Double the spot's diameter: the circle visually envelops
    // the light with a clear margin, so tracking quality is easy
    // to judge at a glance.
    canvas.drawCircle(
      center,
      radiusOf(info, size, isPortrait: isPortrait),
      circlePaint,
    );

    // Label: live classification of the mark in progress. Hidden
    // while the signal is off, and until enough marks have been
    // seen for a robust dit estimate (the decoder reports that via
    // markClassified rather than guessing).
    if (!info.signalOn || !info.markClassified) return;

    final label = info.isDash ? '-' : '.';
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
  bool shouldRepaint(TrackedSpotPainter old) =>
      old.info != info || old.isPortrait != isPortrait;
}
