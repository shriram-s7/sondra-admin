import 'package:flutter_test/flutter_test.dart';

import 'package:sondra/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const SondraApp());
    expect(find.byType(SondraApp), findsOneWidget);
  });
}
