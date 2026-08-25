import 'package:simply_morse/core/services/share_service.dart';

class FakeShareService implements ShareService {
  final List<String> copiedTexts = [];
  final List<String> sharedTexts = [];

  @override
  Future<void> copyToClipboard(String text) async {
    copiedTexts.add(text);
  }

  @override
  Future<void> share(String text) async {
    sharedTexts.add(text);
  }

  void reset() {
    copiedTexts.clear();
    sharedTexts.clear();
  }
}
