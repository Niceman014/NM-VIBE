import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/app.dart';

void main() {
  testWidgets('NM VIBE opens on the empty library', (WidgetTester tester) async {
    await tester.pumpWidget(const NmVibeApp());

    expect(find.text('NM VIBE'), findsOneWidget);
    expect(find.text('Your library starts here'), findsOneWidget);
    expect(
      find.text('Add music from your device to see it in NM VIBE.'),
      findsOneWidget,
    );
  });
}
