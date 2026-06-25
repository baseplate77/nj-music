import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yt_music/main.dart';

void main() {
  testWidgets('App boots to home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: YtMusicApp()));
    expect(find.text('YT Music'), findsOneWidget);
  });
}
