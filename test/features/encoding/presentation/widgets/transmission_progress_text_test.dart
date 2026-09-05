import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/transmission_state.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/transmission_progress_text.dart';

void main() {
  group('TransmissionProgressText', () {
    Future<void> pumpLabel(
      WidgetTester tester, {
      required String text,
      TransmissionState state = const TransmissionState(),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransmissionProgressText(
              text: text,
              state: state,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'renders SizedBox.shrink when text is empty',
      (tester) async {
        await pumpLabel(tester, text: '');

        // Empty text → SizedBox.shrink inside the label
        expect(find.byType(TransmissionProgressText), findsOneWidget);
      },
    );

    testWidgets('displays text via RichText', (tester) async {
      await pumpLabel(tester, text: 'SOS');

      expect(find.byType(RichText), findsOneWidget);
      final richText = tester.widget<RichText>(
        find.byType(RichText),
      );
      final span = richText.text as TextSpan;
      expect(span.children!.length, 3);
      expect((span.children![0] as TextSpan).text, 'S');
      expect((span.children![1] as TextSpan).text, 'O');
      expect((span.children![2] as TextSpan).text, 'S');
    });

    testWidgets(
      'shows RichText during transmission',
      (tester) async {
        await pumpLabel(
          tester,
          text: 'HI',
          state: const TransmissionState(
            status: TransmissionStatus.transmitting,
            currentCharIndex: 0,
          ),
        );

        expect(find.byType(RichText), findsOneWidget);
      },
    );

    testWidgets(
      'highlights current character during transmission',
      (tester) async {
        await pumpLabel(
          tester,
          text: 'AB',
          state: const TransmissionState(
            status: TransmissionStatus.transmitting,
            currentCharIndex: 1,
          ),
        );

        final richText = tester.widget<RichText>(
          find.byType(RichText),
        );
        final span = richText.text as TextSpan;

        expect(span.children!.length, 2);

        // First char (A) = transmitted (normal weight)
        // Second char (B) = current (bold)
        final firstStyle = span.children![0].style!;
        final secondStyle = span.children![1].style!;

        expect(firstStyle.fontWeight, FontWeight.normal);
        expect(secondStyle.fontWeight, FontWeight.bold);
      },
    );

    testWidgets(
      'styles all characters as completed',
      (tester) async {
        await pumpLabel(
          tester,
          text: 'TEST',
          state: const TransmissionState(
            status: TransmissionStatus.completed,
          ),
        );

        final richText = tester.widget<RichText>(
          find.byType(RichText),
        );
        final span = richText.text as TextSpan;

        expect(span.children!.length, 4);
        for (final child in span.children!) {
          expect(
            child.style!.fontWeight,
            FontWeight.normal,
          );
        }
      },
    );

    testWidgets(
      'styles idle characters as normal weight',
      (tester) async {
        await pumpLabel(
          tester,
          text: 'HI',
          state: const TransmissionState(
            status: TransmissionStatus.idle,
          ),
        );

        final richText = tester.widget<RichText>(
          find.byType(RichText),
        );
        final span = richText.text as TextSpan;

        for (final child in span.children!) {
          expect(
            child.style!.fontWeight,
            FontWeight.normal,
          );
        }
      },
    );

    testWidgets(
      'renders bare text with no border of its own',
      (tester) async {
        // The widget is embedded in the input box's decorator;
        // it must not draw its own container or border.
        await pumpLabel(tester, text: 'SOS');

        expect(find.byType(Container), findsNothing);
        expect(find.byType(RichText), findsOneWidget);
      },
    );

    test('buildSpans marks the current character bold in primary', () {
      final colors = ColorScheme.fromSeed(
        seedColor: Colors.blue,
      );

      final spans = TransmissionProgressText.buildSpans(
        'AB',
        const TransmissionState(
          status: TransmissionStatus.transmitting,
          currentCharIndex: 1,
        ),
        colors,
      );

      expect(spans.length, 2);
      // Transmitted char: dimmed primary, normal weight.
      expect(spans[0].style!.fontWeight, FontWeight.normal);
      expect(spans[0].style!.color, colors.primary.withValues(alpha: 0.6));
      // Current char: full primary, bold.
      expect(spans[1].style!.fontWeight, FontWeight.bold);
      expect(spans[1].style!.color, colors.primary);
    });
  });
}
