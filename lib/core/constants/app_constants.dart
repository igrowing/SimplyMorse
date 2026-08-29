/// App-wide constants for SimplyMorse.
class AppConstants {
  AppConstants._();

  static const appName = 'SimplyMorse';
  static const appVersion = '0.2.0';

  // Encoding defaults
  static const defaultSpeedWpm = 7.0;
  static const minSpeedWpm = 1.0;
  static const maxSpeedWpm = 40.0;

  static const defaultToneHz = 700.0;
  static const minToneHz = 400.0;
  static const maxToneHz = 1000.0;

  // Initial delay (seconds before transmission starts)
  static const defaultInitialDelaySec = 1.0;
  static const minInitialDelaySec = 0.0;
  static const maxInitialDelaySec = 20.0;

  // Repeat loop
  static const defaultRepeatLoop = false;
  static const defaultRepeatDelaySec = 2.0;
  static const minRepeatDelaySec = 1.0;
  static const maxRepeatDelaySec = 20.0;

  // Display lit timeout
  static const defaultDisplayTimeout = 'system'; // system | 3x | always

  // Storage keys
  static const speedKey = 'speed_wpm';
  static const toneKey = 'tone_hz';
  static const initialDelayKey = 'initial_delay_sec';
  static const textHistoryKey = 'text_history';
  static const repeatLoopKey = 'repeat_loop';
  static const repeatDelayKey = 'repeat_delay_sec';
  static const displayTimeoutKey = 'display_timeout';

  // Text history limits
  static const maxHistoryEntries = 20;

  // Audio
  static const sampleRate = 44100;
  static const fadeMs = 2.0;

  // Links
  static const buyMeCoffeeUrl = 'https://www.buymeacoffee.com/igrowing';
}
