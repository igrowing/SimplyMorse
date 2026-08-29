import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_flash_service.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/morse_transmission_label.dart';

/// Screen for composing and transmitting Morse code.
///
/// On web with light output, the screen is split:
/// left side shows normal UI controls, right side (40%)
/// shows a visual transmission panel.
///
/// The panel shows:
/// - Flash LED → black panel with emulated LED circle.
/// - Display → entire panel blinks white/black.
/// - Both → both LED circle and full panel blink.
///
/// On mobile with Display light method, active transmission
/// shows a full-screen blink overlay with only a Pause button.
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

  /// Whether to show the split-screen visual panel (web only,
  /// when the mode includes light output).
  late final bool _showVisualPanel;

  /// The flash state notifier from [ScreenFlashService].
  /// Only non-null on web where the torch is emulated.
  ValueNotifier<bool>? _ledFlashState;

  @override
  void initState() {
    super.initState();
    _controller = GetIt.instance<EncodingController>();
    _feedbackService = GetIt.instance<FeedbackService>();

    _showVisualPanel = kIsWeb && widget.mode.needsLight;

    if (kIsWeb) {
      _ledFlashState = GetIt.instance<ScreenFlashService>().isFlashing;
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

  Future<void> _onPausePressed() async {
    await _feedbackService.lightImpact();
    await _controller.pause();
  }

  Future<void> _onSpeedChanged(double value) async {
    await _feedbackService.selectionClick();
    await _controller.updateSpeed(value);
  }

  Future<void> _onToneChanged(double value) async {
    await _feedbackService.selectionClick();
    await _controller.updateTone(value);
  }

  Future<void> _onInitialDelayChanged(double value) async {
    await _feedbackService.selectionClick();
    await _controller.updateInitialDelay(value);
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
        body: Stack(
          children: [
            _showVisualPanel
                ? _buildSplitLayout(context)
                : _buildNormalLayout(context),
            _buildCountdownOverlay(context),
          ],
        ),
      ),
    );
  }

  /// Initial-delay countdown overlay.
  ///
  /// Shown while [EncodingController.countdownRemaining] is non-null.
  /// Displays an instruction label adapted to the active light method
  /// (or a generic message for sound-only mode) and a large
  /// counting-down number.
  Widget _buildCountdownOverlay(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: _controller.countdownRemaining,
      builder: (context, remaining, _) {
        if (remaining == null) return const SizedBox.shrink();

        final label = _countdownLabel();

        return Positioned.fill(
          child: Container(
            color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.85),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.5, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    key: ValueKey(remaining),
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Text(
                      '$remaining',
                      style: TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _onPausePressed,
                    icon: const Icon(Icons.cancel_outlined, size: 28),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54, width: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 24,
                      ),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Returns the instruction label shown during the countdown,
  /// adapted to the current mode and light method.
  String _countdownLabel() {
    if (!widget.mode.needsLight) {
      return 'Get ready to transmit';
    }
    return switch (_controller.lightMethod) {
      LightMethod.flashLed => 'Point the flash LED toward your target',
      LightMethod.display => 'Point the screen toward your target',
      LightMethod.both => 'Point the flash LED and screen toward your target',
    };
  }

  /// Split layout for web light modes: left = UI, right = panel.
  Widget _buildSplitLayout(BuildContext context) {
    return SafeArea(
      child: Row(
        children: [
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
                    children: _buildControls(context),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _buildVisualPanel(context),
          ),
        ],
      ),
    );
  }

  /// The visual panel for web (right 40% of split layout).
  Widget _buildVisualPanel(BuildContext context) {
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        final method = ctrl.lightMethod;
        final needsDisplayBlink =
            method == LightMethod.display || method == LightMethod.both;
        final showLedCircle =
            method == LightMethod.flashLed || method == LightMethod.both;

        return ValueListenableBuilder<bool>(
          valueListenable: _controller.displayBlink,
          builder: (context, isDisplayBlinking, _) {
            final panelColor = needsDisplayBlink && isDisplayBlinking
                ? Colors.white
                : Colors.black;
            final textColor = needsDisplayBlink && isDisplayBlinking
                ? Colors.black54
                : Colors.grey;
            final textOnColor = needsDisplayBlink && isDisplayBlinking
                ? Colors.black87
                : Theme.of(context).colorScheme.primary;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 30),
              color: panelColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showLedCircle) ...[
                      ValueListenableBuilder<bool>(
                        valueListenable: _ledFlashState!,
                        builder: (context, isFlashing, _) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 30),
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFlashing
                                  ? Colors.white
                                  : Colors.transparent,
                              border: Border.all(
                                color: Colors.grey,
                                width: 3,
                              ),
                              boxShadow: isFlashing
                                  ? [
                                      BoxShadow(
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
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
                    ],
                    Text(
                      method.label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!ctrl.isTransmitting)
                      Text(
                        'Ready',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      )
                    else
                      Text(
                        'Transmitting…',
                        style: TextStyle(
                          color: textOnColor.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Normal (non-split) layout for mobile or sound-only mode.
  ///
  /// Includes a fullscreen display blink overlay when
  /// transmitting with the Display light method on mobile.
  Widget _buildNormalLayout(BuildContext context) {
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        // On mobile, show fullscreen blink overlay when
        // transmitting with Display or Both light method.
        final showDisplayOverlay =
            !kIsWeb &&
            ctrl.isTransmitting &&
            (ctrl.lightMethod == LightMethod.display ||
                ctrl.lightMethod == LightMethod.both);

        if (showDisplayOverlay) {
          return _buildDisplayOverlay(context);
        }

        return SafeArea(
          child: LayoutBuilder(
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
                      children: _buildControls(context),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Full-screen blink overlay for mobile display transmission.
  /// Shows a Stop button.
  Widget _buildDisplayOverlay(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.displayBlink,
      builder: (context, isBlinking, _) {
        return Container(
          color: isBlinking ? Colors.white : Colors.black,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                FilledButton.icon(
                  onPressed: _onPausePressed,
                  icon: const Icon(Icons.stop, size: 36),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Stop', style: TextStyle(fontSize: 20)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isBlinking ? Colors.black87 : Colors.white,
                    foregroundColor: isBlinking ? Colors.white : Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 20,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shared control list used by both split and normal layouts.
  List<Widget> _buildControls(BuildContext context) {
    return [
      _buildHeader(context),
      const SizedBox(height: 16),
      _buildSpeedSlider(context),
      if (widget.mode.needsTone) ...[
        const SizedBox(height: 8),
        _buildToneSlider(context),
      ],
      const SizedBox(height: 8),
      _buildInitialDelaySlider(context),
      if (widget.mode.needsLight) ...[
        const SizedBox(height: 12),
        _buildLightMethodSelector(context),
      ],
      const SizedBox(height: 16),
      _buildHistoryDropdown(context),
      const SizedBox(height: 8),
      _buildTextInput(context),
      const SizedBox(height: 16),
      _buildActionButtons(context),
      const SizedBox(height: 16),
      _buildTransmissionLabel(context),
    ];
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

  Widget _buildInitialDelaySlider(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Initial delay', style: theme.textTheme.titleSmall),
                Text(
                  '${ctrl.initialDelaySec.round()} s',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            Slider(
              value: ctrl.initialDelaySec,
              min: AppConstants.minInitialDelaySec,
              max: AppConstants.maxInitialDelaySec,
              divisions: 20,
              label: '${ctrl.initialDelaySec.round()}',
              onChanged: ctrl.isTransmitting ? null : _onInitialDelayChanged,
            ),
          ],
        );
      },
    );
  }

  /// Triple selector for Flash LED / Display / Both.
  Widget _buildLightMethodSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<EncodingController>(
      builder: (context, ctrl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Light method', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<LightMethod>(
              segments: LightMethod.values
                  .map(
                    (m) => ButtonSegment(
                      value: m,
                      label: Text(m.label),
                      icon: Icon(m.icon),
                    ),
                  )
                  .toList(),
              selected: {ctrl.lightMethod},
              onSelectionChanged: ctrl.isTransmitting
                  ? null
                  : (value) => _controller.updateLightMethod(value.first),
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
        if (ctrl.isTransmitting) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _onPausePressed,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: ctrl.text.isEmpty ? null : _onSendPressed,
              icon: const Icon(Icons.send),
              label: const Text('Send'),
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
              onPressed: ctrl.text.isEmpty && !ctrl.transmission.isCompleted
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
