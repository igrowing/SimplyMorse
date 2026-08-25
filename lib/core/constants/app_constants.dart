/// App-wide constants for SimplyMorse.
class AppConstants {
  AppConstants._();

  static const appName = 'SimplyMorse';
  static const appVersion = '0.0.5';

  // Encoding defaults
  static const defaultSpeedWpm = 7.0;
  static const minSpeedWpm = 1.0;
  static const maxSpeedWpm = 40.0;

  static const defaultToneHz = 700.0;
  static const minToneHz = 400.0;
  static const maxToneHz = 1000.0;

  // Storage keys
  static const speedKey = 'speed_wpm';
  static const toneKey = 'tone_hz';
  static const textHistoryKey = 'text_history';

  // Text history limits
  static const maxHistoryEntries = 20;

  // Audio
  static const sampleRate = 44100;
  static const fadeMs = 2.0;
}
