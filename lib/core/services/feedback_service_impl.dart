import 'package:flutter/services.dart';
import 'package:simply_morse/core/services/feedback_service.dart';

class FeedbackServiceImpl implements FeedbackService {
  @override
  Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }

  @override
  Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }

  @override
  Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  @override
  Future<void> selectionClick() async {
    await HapticFeedback.selectionClick();
  }

  @override
  Future<void> success() async {
    await HapticFeedback.vibrate();
  }
}
