import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Screen for visual Morse decoding via camera.
///
/// Implements the video decoding pipeline:
/// CameraCapture → VideoDecoder (region detection →
/// brightness tracking → timing) → MorseDecoder → text.
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
  bool _showLowFpsWarning = false;

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<DecodingController>();
    _cameraCapture = GetIt.instance<CameraCaptureImpl>();
    _shareService = GetIt.instance<ShareService>();
    _feedbackService = GetIt.instance<FeedbackService>();
    _controller.init(DecodingMode.video);
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

    if (!_controller.isHighFrameRate) {
      setState(() => _showLowFpsWarning = true);
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

  void _dismissLowFpsWarning() {
    setState(() => _showLowFpsWarning = false);
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
          onSettingsTap: () => _navigateToSettings(context),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth > 600 ? 48 : 16,
                  vertical: 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 500,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 16),
                        _buildStatusIndicator(context),
                        const SizedBox(height: 8),
                        _buildWpmDisplay(context),
                        const SizedBox(height: 16),
                        _buildDecodedTextInput(context),
                        const SizedBox(height: 8),
                        _buildShareButtons(context),
                        const SizedBox(height: 16),
                        _buildCameraPreview(context),
                        const SizedBox(height: 16),
                        _buildActionButtons(context),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.camera_alt, size: 28),
        const SizedBox(width: 12),
        Text(
          'Watch',
          style: theme.textTheme.headlineSmall,
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final (color, label) = switch (ctrl.status) {
          DecodingStatus.idle => (
            theme.colorScheme.outline,
            'Idle',
          ),
          DecodingStatus.listening => (
            theme.colorScheme.primary,
            'Watching…',
          ),
          DecodingStatus.paused => (
            theme.colorScheme.tertiary,
            'Paused',
          ),
        };
        return Row(
          children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWpmDisplay(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        if (ctrl.currentWpm == 0) return const SizedBox.shrink();
        return Row(
          children: [
            Icon(Icons.speed, size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              '${ctrl.currentWpm} WPM',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDecodedTextInput(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        _textController.text = ctrl.decodedText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        return TextField(
          controller: _textController,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Decoded text',
            alignLabelWithHint: true,
            hintText: 'Decoded text will appear here…',
          ),
          onChanged: ctrl.updateText,
        );
      },
    );
  }

  Widget _buildShareButtons(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        if (ctrl.decodedText.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _onCopyPressed,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _onSharePressed,
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final isActive = ctrl.isListening;
        final camController = _cameraCapture.controller;

        return AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (camController != null &&
                      camController.value.isInitialized)
                    CameraPreview(camController)
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Camera preview',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  if (isActive)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SCANNING',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  if (_showLowFpsWarning) _buildLowFpsWarning(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLowFpsWarning(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.scrim.withValues(alpha: 0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AlertDialog(
            title: const Text('Camera info'),
            content: const Text(
              'Your phone camera supports only '
              'decoding of 7 words per minute at '
              'maximum.',
            ),
            actions: [
              TextButton(
                onPressed: _dismissLowFpsWarning,
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Start/Pause/Resume and Clear buttons side by side,
  /// consistent with Send screens.
  Widget _buildActionButtons(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final isStart = ctrl.isIdle;
        final isPause = ctrl.isListening;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: isStart
                  ? _onStartPressed
                  : isPause
                  ? _onPausePressed
                  : _onResumePressed,
              icon: Icon(isPause ? Icons.pause : Icons.play_arrow),
              label: Text(
                isStart
                    ? 'Start'
                    : isPause
                    ? 'Pause'
                    : 'Resume',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: ctrl.decodedText.isEmpty && ctrl.isIdle
                  ? null
                  : _onClearPressed,
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToSettings(BuildContext context) {
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
    );
  }
}
