import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Screen for visual Morse decoding via camera.
///
/// Phase 2 stub: full UI layout with editable text output,
/// camera preview placeholder, dynamic Pause/Resume button,
/// and Clear button. The actual camera capture and brightness
/// analysis pipeline will be wired in a later phase.
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
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<DecodingController>();
    _controller.init(DecodingMode.video);
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    super.dispose();
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
                        _buildStatusIndicator(context),
                        const SizedBox(height: 16),
                        _buildDecodedTextInput(context),
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.camera_alt, size: 28),
        const SizedBox(width: 12),
        Text('Watch', style: theme.textTheme.headlineSmall),
      ],
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final color = switch (ctrl.status) {
          DecodingStatus.idle => theme.colorScheme.outline,
          DecodingStatus.listening => theme.colorScheme.primary,
          DecodingStatus.paused => theme.colorScheme.tertiary,
        };
        final label = switch (ctrl.status) {
          DecodingStatus.idle => 'Idle',
          DecodingStatus.listening => 'Watching…',
          DecodingStatus.paused => 'Paused',
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

  Widget _buildCameraPreview(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        final isActive = ctrl.isListening;
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isActive)
                  // Placeholder for live camera feed
                  const Center(
                    child: CircularProgressIndicator(),
                  )
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
                // Scanning indicator
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPauseResumeButton(BuildContext context) {
    return Consumer<DecodingController>(
      builder: (context, ctrl, _) {
        if (ctrl.isIdle) {
          return FilledButton.icon(
            onPressed: ctrl.start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          );
        }
        if (ctrl.isListening) {
          return FilledButton.icon(
            onPressed: ctrl.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          );
        }
        return FilledButton.icon(
          onPressed: ctrl.resume,
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
              : ctrl.clear,
          icon: const Icon(Icons.clear),
          label: const Text('Clear'),
        );
      },
    );
  }
}
