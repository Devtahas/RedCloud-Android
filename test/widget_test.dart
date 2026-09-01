import 'package:flutter_test/flutter_test.dart';
import 'package:redcloud_android/main.dart';

void main() {
  testWidgets('App initialization test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(
      initialLang: 'fa',
      initialDarkMode: true,
      isFirstRun: false,
    ));
  });
}