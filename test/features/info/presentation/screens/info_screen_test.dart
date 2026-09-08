import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';
import 'package:simply_morse/features/info/presentation/screens/info_screen.dart';

import '../../../../helpers/wakelock_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockWakelockToggleChannel();

  Future<void> pumpInfo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: InfoScreen()));
  }

  group('InfoScreen', () {
    testWidgets('renders all chapter titles', (tester) async {
      await pumpInfo(tester);

      expect(find.text('Morse basics'), findsOneWidget);
      expect(find.text('Pauses and timing'), findsOneWidget);
      expect(find.text('Farnsworth timing'), findsOneWidget);
      expect(find.text('Symbols the app can decode'), findsOneWidget);
      expect(find.text('Common abbreviations'), findsOneWidget);
    });

    testWidgets('presents every decodable letter', (tester) async {
      await pumpInfo(tester);

      for (final entry in MorseCodeTable.letters.entries) {
        expect(find.text(entry.key), findsWidgets);
      }
    });

    testWidgets('presents digits and the SOS prosign', (tester) async {
      await pumpInfo(tester);

      expect(find.text('...---...'), findsOneWidget);
      for (final entry in MorseCodeTable.digits.entries) {
        expect(find.text(entry.key), findsWidgets);
      }
    });

    testWidgets('mentions the three pause levels', (tester) async {
      await pumpInfo(tester);

      expect(
        find.textContaining('Pause between tones in a symbol'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Pause between symbols (letters)'),
        findsOneWidget,
      );
      expect(find.textContaining('Pause between words'), findsOneWidget);
    });

    testWidgets('explains Farnsworth timing', (tester) async {
      await pumpInfo(tester);

      expect(
        find.textContaining('stretches the pauses between characters'),
        findsOneWidget,
      );
      expect(find.textContaining('effective speed of 10 WPM'), findsOneWidget);
    });

    testWidgets('lists the requested abbreviations', (tester) async {
      await pumpInfo(tester);

      // findsWidgets: single-letter abbreviations such as C and N
      // also appear in the letter table above.
      for (final abbrev in ['73', 'GN', 'SK', 'C', 'N', 'CQ']) {
        expect(find.text(abbrev), findsWidgets);
      }
      expect(find.textContaining('Best regards'), findsOneWidget);
      expect(find.textContaining('Good night'), findsOneWidget);
    });

    testWidgets('notes the Latin Extended opt-in behavior', (tester) async {
      await pumpInfo(tester);

      // findsWidgets: also the subsection title.
      expect(find.textContaining('Latin Extended'), findsWidgets);
      expect(find.textContaining('decoded only when Latin'), findsOneWidget);
    });

    testWidgets('scrolls to the abbreviations chapter', (tester) async {
      await pumpInfo(tester);

      await tester.scrollUntilVisible(
        find.text('CQ'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CQ'), findsOneWidget);
    });
  });
}
