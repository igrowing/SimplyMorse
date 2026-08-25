import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:simply_morse/core/constants/app_constants.dart';

/// Local storage data source backed by SharedPreferences.
class LocalStorageDatasource {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _instance {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError(
        'LocalStorageDatasource not initialized. '
        'Call init() before using.',
      );
    }
    return prefs;
  }

  Future<double> getSpeed() async {
    return _instance.getDouble(AppConstants.speedKey) ??
        AppConstants.defaultSpeedWpm;
  }

  Future<void> saveSpeed(double wpm) async {
    await _instance.setDouble(AppConstants.speedKey, wpm);
  }

  Future<double> getTone() async {
    return _instance.getDouble(AppConstants.toneKey) ??
        AppConstants.defaultToneHz;
  }

  Future<void> saveTone(double hz) async {
    await _instance.setDouble(AppConstants.toneKey, hz);
  }

  Future<List<String>> getTextHistory() async {
    final json = _instance.getString(AppConstants.textHistoryKey);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.cast<String>();
  }

  Future<void> saveTextHistory(List<String> history) async {
    await _instance.setString(
      AppConstants.textHistoryKey,
      jsonEncode(history),
    );
  }

  Future<void> clearTextHistory() async {
    await _instance.remove(AppConstants.textHistoryKey);
  }
}
