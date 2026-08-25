import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/services/share_service.dart';
import '../../helpers/fake_share_service.dart';

void main() {
  group('ShareService', () {
    late FakeShareService shareService;

    setUp(() {
      shareService = FakeShareService();
    });

    test('copyToClipboard records the text', () async {
      await shareService.copyToClipboard('Hello World');
      expect(shareService.copiedTexts, ['Hello World']);
    });

    test('share records the text', () async {
      await shareService.share('SOS');
      expect(shareService.sharedTexts, ['SOS']);
    });

    test('multiple copies are recorded in order', () async {
      await shareService.copyToClipboard('A');
      await shareService.copyToClipboard('B');
      expect(shareService.copiedTexts, ['A', 'B']);
    });

    test('reset clears all recorded calls', () async {
      await shareService.copyToClipboard('test');
      await shareService.share('test');
      shareService.reset();
      expect(shareService.copiedTexts, isEmpty);
      expect(shareService.sharedTexts, isEmpty);
    });
  });
}
