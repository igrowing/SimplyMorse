import 'package:flutter/services.dart';

/// Abstract interface for sharing text and copying to clipboard.
abstract interface class ShareService {
  /// Copies [text] to the system clipboard.
  Future<void> copyToClipboard(String text);

  /// Shares [text] via the system share sheet.
  Future<void> share(String text);
}
