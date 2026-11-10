import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/store/takvim_store.dart';

void main() {
  late Directory klasor;
  late File dosya;

  setUp(() {
    klasor = Directory.systemTemp.createTempSync('takvim_inceleme_');
    dosya = File('${klasor.path}/takvim.json');
  });
  tearDown(() => klasor.deleteSync(recursive: true));

  test('aynı anda başlayan iki degistir: ikisinin değişikliği de bellekte ve diskte kalır', () async {
    final a = await TakvimStore.ac(dosya);
    await Future.wait([
      a.degistir((v) => v.addTask('Bir')),
      a.degistir((v) => v.addTask('İki')),
    ]);
    expect(a.veri.tasks.length, 2);
    expect((await TakvimStore.ac(dosya)).veri.tasks.length, 2);
  });

  test('başarısız bir degistir sonraki çağrıları zehirlemez, hata kendi çağırana gider', () async {
    final a = await TakvimStore.ac(dosya);
    final hatali = a.degistir<void>((v) => throw StateError('x'));
    final iyi = a.degistir((v) => v.addTask('Kalan'));
    await expectLater(hatali, throwsStateError);
    await iyi;
    expect(a.veri.tasks.length, 1);
  });
}
