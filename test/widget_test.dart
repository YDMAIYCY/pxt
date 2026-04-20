import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/ui/app_shell.dart';

void main() {
  testWidgets('Guide page is shown on app launch', (WidgetTester tester) async {
    await tester.pumpWidget(const PaixuetongApp());

    expect(find.text('进入登录'), findsOneWidget);
  });
}
