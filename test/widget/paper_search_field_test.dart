import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/shared/widgets/paper_widgets.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';

void main() {
  testWidgets('clear affordance follows the field text', (
    WidgetTester tester,
  ) async {
    String value = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: PaperTheme.build(style: PaperStyle.white),
        home: Scaffold(
          body: PaperSearchField(onChanged: (String text) => value = text),
        ),
      ),
    );

    expect(find.byTooltip('Clear'), findsNothing);

    await tester.enterText(find.byType(TextField), 'paper');
    await tester.pump();

    expect(find.byTooltip('Clear'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();

    expect(find.byTooltip('Clear'), findsNothing);
    expect(value, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('clear affordance appears when a parent sets controller text', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: PaperTheme.build(style: PaperStyle.white),
        home: Scaffold(
          body: PaperSearchField(controller: controller, onChanged: (_) {}),
        ),
      ),
    );

    expect(find.byTooltip('Clear'), findsNothing);

    controller.text = 'imported';
    await tester.pump();

    expect(find.byTooltip('Clear'), findsOneWidget);
  });
}
