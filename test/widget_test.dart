import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simply_morse/app.dart';
import 'package:simply_morse/core/di/injection.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    await configureDependencies();
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const SimplyMorseApp());
    await tester.pumpAndSettle();
    expect(find.text('SimplyMorse'), findsOneWidget);
  });
}
