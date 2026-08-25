import 'package:flutter_test/flutter_test.dart';

import 'package:simply_morse/app.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const SimplyMorseApp());
    expect(find.text('SimplyMorse'), findsOneWidget);
  });
}
