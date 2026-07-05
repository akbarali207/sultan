import 'package:flutter_test/flutter_test.dart';

import 'package:sultan/main.dart';

void main() {
  testWidgets('Ilova ochiladi (login ekrani)', (WidgetTester tester) async {
    await tester.pumpWidget(const SultanApp());
    expect(find.byType(SultanApp), findsOneWidget);
  });
}
