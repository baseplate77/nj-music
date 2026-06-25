@Tags(['live'])
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_music/services/music_service.dart';
void main() {
  test('first resolve is fast (androidVr) and second is cached', () async {
    final svc = MusicService();
    final sw1 = Stopwatch()..start();
    final u1 = await svc.streamUrl('4D7u5KF7SP8');
    final t1 = sw1.elapsedMilliseconds;
    final sw2 = Stopwatch()..start();
    final u2 = await svc.streamUrl('4D7u5KF7SP8');
    final t2 = sw2.elapsedMilliseconds;
    // ignore: avoid_print
    print('first=${t1}ms  cached=${t2}ms  mime=${Uri.parse(u1).queryParameters['mime']}');
    expect(u1, equals(u2));
    expect(t2, lessThan(50));            // cache hit
    expect(Uri.parse(u1).queryParameters['mime'], contains('mp4'));
    svc.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
