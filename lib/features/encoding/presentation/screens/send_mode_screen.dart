import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_flash_service.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/morse_transmission_label.dart';

/// Screen for composing and transmitting Morse code.
///
/// On web with Flash LED or Both mode, the screen is split:
/// left side shows the normal UI controls, right side shows
/// a black panel with an emulated LED circle that flashes
/// white/black during transmission.
class SendModeScreen extends StatefulWidget {
  const SendModeScreen({
    required this.mode,
    required this.themeMode,
    required this.onThemeToggle,
    super.key,
  });

  final EncodingMode mode;
  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

  @override
  State<SendModeScreen> createState() => _SendModeScreenState();
}

class _SendModeScreenState extends State<SendModeScreen> {
  late final EncodingController _controller;
  late final FeedbackService _feedbackService;
  final _textController = TextEditingController();

  /// Whether to show the split-screen LED emulation panel.
  late final bool _showLedPanel;

  /// The flash state notifier from [ScreenFlashService].
  /// Only non-null when [_showLedPanel] is true.
  ValueNotifier<bool>? _flashState;

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<EncodingController>();
    _feedbackService = GetIt.instance<FeedbackService>();

    final usesFlash =
        widget.mode == EncodingMode.flash || widget.mode == EncodingMode.both;
    _showLedPanel = kIsWeb && usesFlash;

    if (_showLedPanel) {
      _flashState = GetIt.instance<ScreenFlashService>().isFlashing;
    }

    _controller.init(widget.mode);
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSendPressed() async {
    await _feedbackService.heavyImpact();
    await _controller.send();
  }

  Future<void> _onClearPressed() async {
    await _feedbackService.lightImpact();
    await _controller.clear();
    _textController.clear();
  }

  Future<void> _onSpeedChanged(double value) async {
    await _feedbackService.selectionClick();
    await _controller.updateSpeed(value);
  }

  Future<void> _onToneChanged(double value) async {
    await _feedbackService.selectionClick();
    await _controller.updateTone(value);
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
          child: _showLedPanel
              ? _buildSplitLayout(context)
              : _buildNormalLayout(context),
        ),
      ),
    );
  }

  /// Split layout for web flash modes: left = UI, right = LED panel.
  Widget _buildSplitLayout(BuildContext context) {
    return Row(
      children: [
        // Left side — normal UI controls
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildSpeedSlider(context),
                    if (widget.mode.needsTone) ...[
                      const SizedBox(height: 8),
                      _buildToneSlider(context),
                    ],
                    const SizedBox(height: 16),
                    _buildHistoryDropdown(context),
                    const SizedBox(height: 8),
                    _buildTextInput(context),
                    const SizedBox(height: 16),
                    _buildActionButtons(context),
                    const SizedBox(height: 16),
                    _buildTransmissionLabel(context),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Right side — black LED emulation panel
        Expanded(
          flex: 2,
          child: _buildLedPanel(context),
        ),
      ],
    );
  }

  /// The black panel with an emulated LED circle.
  Widget _buildLedPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _flashState!,
              builder: (context, isFlashing, _) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 30),
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFlashing ? Colors.white : Colors.black,
                    border: Border.all(
                      color: Colors.grey,
                      width: 3,
                    ),
                    boxShadow: isFlashing
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.4),
                              blurRadius: 60,
                              spreadRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'LED',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Consumer<EncodingController>(
              builder: (context, ctrl, _) {
                if (!ctrl.isTransmitting) {
                  return Text(
                    'Ready',
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  );
                }
                return Text(
                  'Transmitting…',
                  style: TextStyle(
                    color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Normal (non-split) layout for mobile or sound-only mode.
  Widget _buildNormalLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth > 600 ? 48 : 16,
            vertical: 16,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 16),
                  _buildSpeedSlider(context),
                  if (widget.mode.needsTone) ...[
                    const SizedBox(height: 8),
                    _buildToneSlider(context),
                  ],
                  const SizedBox(height: 16),
                  _buildHistoryDropdown(context),
                  const SizedBox(height: 8),
                  _buildTextInput(context),
                  const SizedBox(height: 16),
                  _buildActionButtons(context),
                  const SizedBox(height: 16),
                  _buildTransmissionLabel(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(widget.mode.icon, size: 28),
        const SizedBox(width: 12),
        Text(
          widget.mode.label,
          style: theme.textTheme.headlineSmall,
        ),
      ],
    );
  }

  Widget _buildSpeedSlider(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Speed', style: theme.textTheme.titleSmall),
                Text(
                  '${ctrl.speedWpm.round()} WPM',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            Slider(
              value: ctrl.speedWpm,
              min: AppConstants.minSpeedWpm,
              max: AppConstants.maxSpeedWpm,
              divisions: 39,
              label: '${ctrl.speedWpm.round()}',
              onChanged: ctrl.isTransmitting ? null : _onSpeedChanged,
            ),
          ],
        );
      },
    );
  }

  Widget _buildToneSlider(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tone', style: theme.textTheme.titleSmall),
                Text(
                  '${ctrl.toneHz.round()} Hz',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            Slider(
              value: ctrl.toneHz,
              min: AppConstants.minToneHz,
              max: AppConstants.maxToneHz,
              divisions: 60,
              label: '${ctrl.toneHz.round()}',
              onChanged: ctrl.isTransmitting ? null : _onToneChanged,
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryDropdown(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        if (ctrl.history.isEmpty) return const SizedBox.shrink();
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'History',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.history, size: 20),
          ),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox.shrink(),
            hint: Text(
              'Choose a previous text',
              style: theme.textTheme.bodySmall,
            ),
            items: ctrl.history
                .map(
                  (text) => DropdownMenuItem(
                    value: text,
                    child: Text(
                      text.length > 40 ? '${text.substring(0, 40)}...' : text,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                ctrl.selectFromHistory(value);
                _textController.text = value;
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildTextInput(BuildContext context) {
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        return TextField(
          controller: _textController,
          maxLines: 4,
          enabled: !ctrl.isTransmitting,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Text to send',
            alignLabelWithHint: true,
          ),
          onChanged: ctrl.updateText,
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: ctrl.isTransmitting || ctrl.text.isEmpty
                    ? null
                    : _onSendPressed,
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    ctrl.isTransmitting ||
                        (ctrl.text.isEmpty && !ctrl.transmission.isCompleted)
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

  Widget _buildTransmissionLabel(BuildContext context) {
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        if (ctrl.text.isEmpty && !ctrl.transmission.isCompleted) {
          return const SizedBox.shrink();
        }
        return MorseTransmissionLabel(
          text: ctrl.text,
          state: ctrl.transmission,
        );
      },
    );
  }
}
