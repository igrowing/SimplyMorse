import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_feedback_service.dart';

void main() {
  group('FeedbackService', () {
    late FakeFeedbackService feedback;

    setUp(() {
      feedback = FakeFeedbackService();
    });

    test('lightImpact records call', () async {
      await feedback.lightImpact();
      expect(feedback.calls, ['light']);
    });

    test('mediumImpact records call', () async {
      await feedback.mediumImpact();
      expect(feedback.calls, ['medium']);
    });

    test('heavyImpact records call', () async {
      await feedback.heavyImpact();
      expect(feedback.calls, ['heavy']);
    });

    test('selectionClick records call', () async {
      await feedback.selectionClick();
      expect(feedback.calls, ['selection']);
    });

    test('success records call', () async {
      await feedback.success();
      expect(feedback.calls, ['success']);
    });

    test('multiple calls are recorded in order', () async {
      await feedback.lightImpact();
      await feedback.mediumImpact();
      await feedback.success();
      expect(feedback.calls, ['light', 'medium', 'success']);
    });

    test('reset clears all calls', () async {
      await feedback.lightImpact();
      feedback.reset();
      expect(feedback.calls, isEmpty);
    });
  });
}
