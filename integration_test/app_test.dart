import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crispchess/main.dart' as app;
import 'package:crispchess/screens/chess_game_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows the chess game screen', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ChessGameScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
