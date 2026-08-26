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
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

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
    required this.themeMode,
    required this.onThemeToggle,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

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
          themeMode: widget.themeMode,
          onThemeToggle: widget.onThemeToggle,
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
                        _buildPauseResumeButton(context),
                        const SizedBox(height: 12),
                        _buildClearButton(context),
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
        themeMode: widget.themeMode,
        onThemeToggle: widget.onThemeToggle,
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
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _onCopyPressed,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _onSharePressed,
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share'),
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

  Widget _buildPauseResumeButton(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        if (ctrl.isIdle) {
          return FilledButton.icon(
            onPressed: _onStartPressed,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          );
        }
        if (ctrl.isListening) {
          return FilledButton.icon(
            onPressed: _onPausePressed,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          );
        }
        return FilledButton.icon(
          onPressed: _onResumePressed,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
        );
      },
    );
  }

  Widget _buildClearButton(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        return OutlinedButton.icon(
          onPressed: ctrl.decodedText.isEmpty && ctrl.isIdle
              ? null
              : _onClearPressed,
          icon: const Icon(Icons.clear),
          label: const Text('Clear'),
        );
      },
    );
  }
}
