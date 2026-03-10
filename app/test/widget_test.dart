import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/main.dart';

void main() {
  testWidgets('App boots to login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Trip Expense Tracker'), findsOneWidget);
  });
}
