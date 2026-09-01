import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simply_morse/core/services/share_service.dart';

class ShareServiceImpl implements ShareService {
  @override
  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
