import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Screen for audio-based Morse decoding via microphone.
///
/// Implements the audio decoding pipeline:
/// AudioCapture → AudioDecoder (calibration → Goertzel lock →
/// envelope → timing) → MorseDecoder → text output.
///
/// When listening starts, the decoder calibrates for ~2 s to
/// detect the dominant tone in 400-1000 Hz. The locked
/// frequency is shown in the status bar.
class ListenScreen extends StatefulWidget {
  const ListenScreen({
    required this.themeMode,
    required this.onThemeToggle,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  late final DecodingController _controller;
  late final ShareService _shareService;
  late final FeedbackService _feedbackService;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<DecodingController>();
    _shareService = GetIt.instance<ShareService>();
    _feedbackService = GetIt.instance<FeedbackService>();
    _controller.init(DecodingMode.audio);
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
            'Microphone permission is required to decode '
            'Morse audio.',
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
                        _buildStatusBar(context),
                        const SizedBox(height: 16),
                        _buildDecodedTextInput(context),
                        const SizedBox(height: 8),
                        _buildShareButtons(context),
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.mic, size: 28),
        const SizedBox(width: 12),
        Text('Hear', style: theme.textTheme.headlineSmall),
      ],
    );
  }

  /// Combined status bar showing status indicator, locked
  /// frequency, and WPM on one line.
  Widget _buildStatusBar(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final (color, label) = switch (ctrl.status) {
          DecodingStatus.idle => (
            theme.colorScheme.outline,
            'Idle',
          ),
          DecodingStatus.listening => (
            ctrl.isCalibrating
                ? theme.colorScheme.tertiary
                : theme.colorScheme.primary,
            ctrl.isCalibrating ? 'Calibrating…' : 'Listening…',
          ),
          DecodingStatus.paused => (
            theme.colorScheme.tertiary,
            'Paused',
          ),
        };

        return Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
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
            ),
            if (ctrl.lockedFrequency > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Locked at ${ctrl.lockedFrequency.round()} Hz',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            if (ctrl.currentWpm > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.speed,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${ctrl.currentWpm} WPM',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
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
          maxLines: 6,
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

  /// Start/Pause/Resume and Clear buttons side by side,
  /// consistent with Send screens.
  Widget _buildActionButtons(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final isStart = ctrl.isIdle;
        final isPause = ctrl.isListening;

        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
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
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: ctrl.decodedText.isEmpty && ctrl.isIdle
                    ? null
                    : _onClearPressed,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ),
          ],
        );
      },
    );
  }
}
