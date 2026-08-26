import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/morse_transmission_label.dart';

/// Screen for composing and transmitting Morse code.
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

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<EncodingController>();
    _feedbackService = GetIt.instance<FeedbackService>();
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
          ),
        ),
      ),
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
