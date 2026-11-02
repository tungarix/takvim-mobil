import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim/core/zaman.dart';
import 'package:takvim/store/takvim_store.dart';

import 'yardimci.dart';

void main() {
  late Directory klasor;
  late File dosya;

  setUp(() {
    klasor = Directory.systemTemp.createTempSync('takvim_store_');
    dosya = File('${klasor.path}/alt/takvim.json');
  });
  tearDown(() => klasor.deleteSync(recursive: true));

  Future<TakvimStore> ac() => TakvimStore.ac(dosya, saat: Saat().call);

  test('yeni depo boş açılır; değişiklik kaydedilir ve yeniden açınca aynen gelir, cihaz kimliği kalıcı', () async {
    final a = await ac();
    expect(a.veri.events, isEmpty);
    final cal = await a.degistir((v) => v.addCalendar('Kişisel', '#3b82f6'));
    await a.degistir((v) => v.addTask('Rapor'));
    final b = await ac();
    expect(ozet(b.veri), ozet(a.veri));
    expect(b.veri.calendars.keys, [cal.uid]);
    expect(b.cihaz.id, a.cihaz.id);
  });

  test('yazma sonrası artık .tmp kalmaz; ikinci kayıtta .bak sağlam önceki hâli taşır', () async {
    final a = await ac();
    await a.degistir((v) => v.addCalendar('Bir', '#111'));
    final birinci = ozet(a.veri);
    await a.degistir((v) => v.addCalendar('İki', '#222'));
    expect(File('${dosya.path}.tmp').existsSync(), isFalse);
    final bak = await TakvimStore.ac(File('${dosya.path}.bak'), saat: Saat().call);
    expect(ozet(bak.veri), birinci);
  });

  test('değişiklik fonksiyonu hata verirse bellek ve dosya olduğu gibi kalır', () async {
    final a = await ac();
    await a.degistir((v) => v.addCalendar('Bir', '#111'));
    final once = ozet(a.veri);
    final dosyaOnce = dosya.readAsStringSync();
    await expectLater(a.degistir((v) {
      v.addCalendar('Yarım', '#999');
      throw StateError('yarıda patladı');
    }), throwsStateError);
    expect(ozet(a.veri), once);
    expect(dosya.readAsStringSync(), dosyaOnce);
  });

  test('asıl dosya bozuksa son sağlam yedeğe dönülür; bozuk dosya silinmez, yanında saklanır', () async {
    final a = await ac();
    await a.degistir((v) => v.addCalendar('Bir', '#111'));
    await a.degistir((v) => v.addCalendar('İki', '#222'));
    final bakOzet = ozet((await TakvimStore.ac(File('${dosya.path}.bak'), saat: Saat().call)).veri);
    dosya.writeAsStringSync('{yarım yazılmış'); // elektrik kesildi
    final b = await ac();
    expect(ozet(b.veri), bakOzet);
    final saklanan = klasor.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('.bozuk-'));
    expect(saklanan.single.readAsStringSync(), '{yarım yazılmış');
    // sağlam hâl asıl dosyaya geri yazıldı
    expect(ozet((await ac()).veri), bakOzet);
  });

  test('asıl dosya yok ama tam yazılmış .tmp var (rename öncesi kesinti): .tmp kullanılır', () async {
    final a = await ac();
    await a.degistir((v) => v.addCalendar('Bir', '#111'));
    final icerik = dosya.readAsStringSync();
    File('${dosya.path}.tmp').writeAsStringSync(icerik);
    dosya.deleteSync();
    expect(ozet((await ac()).veri), ozet(a.veri));
  });

  test('hiçbir dosya okunamıyorsa boş başlamaz: hata fırlar, dosyalara dokunulmaz', () async {
    final a = await ac();
    await a.degistir((v) => v.addCalendar('Bir', '#111'));
    await a.degistir((v) => v.addCalendar('İki', '#222'));
    dosya.writeAsStringSync('bozuk1');
    File('${dosya.path}.bak').writeAsStringSync('bozuk2');
    await expectLater(ac(), throwsA(isA<BozukDepoHatasi>()));
    expect(dosya.readAsStringSync(), 'bozuk1');
    expect(File('${dosya.path}.bak').readAsStringSync(), 'bozuk2');
  });

  test('daha yeni sürümün deposu bozuk sayılıp ezilmez', () async {
    dosya.parent.createSync(recursive: true);
    dosya.writeAsStringSync('{"format":"takvim-store","version":9}');
    await expectLater(ac(), throwsA(isA<SurumHatasi>()));
    expect(dosya.readAsStringSync(), contains('"version":9'));
  });

  test('bozuk asıl dosya yedeği ezmez: bir sonraki kayıtta .bak sağlam kalır', () async {
    final a = await ac();
    await a.degistir((v) => v.addCalendar('Bir', '#111'));
    await a.degistir((v) => v.addCalendar('İki', '#222'));
    final bak = File('${dosya.path}.bak').readAsStringSync();
    dosya.writeAsStringSync('çöp'); // uygulama açıkken dosya bozuldu
    await a.degistir((v) => v.addCalendar('Üç', '#333'));
    expect(File('${dosya.path}.bak').readAsStringSync(), bak);
  });
}
