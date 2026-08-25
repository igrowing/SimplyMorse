import 'package:simply_morse/core/services/feedback_service.dart';

class FakeFeedbackService implements FeedbackService {
  final List<String> calls = [];

  @override
  Future<void> lightImpact() async => calls.add('light');

  @override
  Future<void> mediumImpact() async => calls.add('medium');

  @override
  Future<void> heavyImpact() async => calls.add('heavy');

  @override
  Future<void> selectionClick() async => calls.add('selection');

  @override
  Future<void> success() async => calls.add('success');

  void reset() => calls.clear();
}
