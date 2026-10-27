import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/canli.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/form.dart';
import '../ortak/grafik.dart';
import '../ortak/ortak.dart';
import '../ortak/ust_serit.dart';

const izinTurleri = {
  'annual': 'Yıllık izin',
  'sick': 'Rapor',
  'unpaid': 'Ücretsiz izin',
  'holiday': 'Resmi tatil',
  'absence': 'Devamsızlık',
  'other': 'Diğer',
};

/// Gün tablosu durumu → (ad, renk).
(String, Color) mesaiDurumu(String d, PaRenk r) => switch (d) {
  'calisiyor' => ('Çalışıyor', r.arti),
  'cikti' => ('Çıktı', r.silik),
  'gelmedi' => ('Gelmedi', r.eksi),
  'izinli' => ('İzinli', r.uyari),
  'bekliyor' => ('Bekleniyor', Marka.mavi),
  _ => (d.isEmpty ? '—' : d, r.silik),
};

DateTime? _t(Object? s) => s == null ? null : DateTime.tryParse(s.toString())?.toLocal();

/// MESAİ / DEVAM: üç bölüm.
///  - Gün tablosu: GET /api/v1/shifts/day-board?gun=Y-m-d
///  - Talepler: GET leave-requests / swap-requests (?status=pending) +
///    POST …/{id}/approve | reject
///  - Haftalık: GET /api/v1/shifts/attendance-summary?from&to
/// Kişiye dokununca kayıtları (time-entries) açılır: düzelt (PUT, gerekçe
/// zorunlu) / onayla (POST approve) / içerideyse çıkış ver (clock_out_at).
class MesaiEkrani extends StatefulWidget {
  const MesaiEkrani({super.key, this.sekme = 0});
  final int sekme;
  @override
  State<MesaiEkrani> createState() => _MesaiEkraniState();
}

class _MesaiEkraniState extends State<MesaiEkrani> {
  late int _sekme = widget.sekme;
  DateTime _gun = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  Map<String, dynamic>? _tablo;
  ApiHata? _tabloHata;
  List<Map<String, dynamic>>? _izinler;
  List<Map<String, dynamic>>? _takaslar;
  ApiHata? _talepHata;
  List<Map<String, dynamic>>? _haftalik;
  ApiHata? _haftaHata;
  final _mesgul = <String>{};

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() => switch (_sekme) {
    0 => _tabloYukle(),
    1 => _talepYukle(),
    _ => _haftaYukle(),
  };

  Future<void> _tabloYukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/shifts/day-board', sorgu: {'gun': gunIso(_gun)});
      if (mounted) {
        setState(() {
          _tablo = r is Map ? Map<String, dynamic>.from(r) : {};
          _tabloHata = null;
        });
      }
    } on ApiHata catch (e) {
      if (mounted) setState(() => _tabloHata = e);
    }
  }

  Future<void> _talepYukle() async {
    try {
      final s = await Future.wait([
        Uyg.api.get('/api/v1/shifts/leave-requests', sorgu: const {'status': 'pending'}),
        Uyg.api.get('/api/v1/shifts/swap-requests', sorgu: const {'status': 'pending'}),
      ]);
      if (!mounted) return;
      setState(() {
        _izinler = s[0] is Map ? (s[0] as Map).l('data') : const [];
        _takaslar = s[1] is Map ? (s[1] as Map).l('data') : const [];
        _talepHata = null;
      });
      Canli.bekleyenIzin.value = _izinler!.length;
      Canli.bekleyenTakas.value = _takaslar!.length;
    } on ApiHata catch (e) {
      if (mounted) setState(() => _talepHata = e);
    }
  }

  Future<void> _haftaYukle() async {
    final bas = haftaBasi(DateTime.now());
    try {
      final r = await Uyg.api.get('/api/v1/shifts/attendance-summary', sorgu: {'from': gunIso(bas), 'to': gunIso(bas.add(const Duration(days: 7)))});
      if (mounted) {
        setState(() {
          _haftalik = r is Map ? r.l('summary') : const [];
          _haftaHata = null;
        });
      }
    } on ApiHata catch (e) {
      if (mounted) setState(() => _haftaHata = e);
    }
  }

  void _sekmeSec(int s) {
    setState(() => _sekme = s);
    _yukle();
  }

  Future<void> _karar(String tur, Map<String, dynamic> x, bool onay) async {
    final id = x.i('id');
    final anahtar = '$tur$id';
    final govde = <String, dynamic>{};
    if (!onay) {
      final not = await metinIste(context, baslik: 'Ret nedeni', ipucu: 'İsteğe bağlı, personele gösterilir', evet: 'Reddet');
      if (not == null) return;
      if (not.isNotEmpty) govde['note'] = not;
    } else if (tur == 'swap' && x.m('target_user').isEmpty) {
      // Devralacak kişi belirtilmemiş: seç.
      final kisi = await _kisiSec('Vardiyayı kim devralsın?', haric: x.m('shift').i('user_id'));
      if (kisi == null) return;
      govde['target_user_id'] = kisi;
    }
    setState(() => _mesgul.add(anahtar));
    try {
      final yol = tur == 'leave' ? 'leave-requests' : 'swap-requests';
      await Uyg.api.post('/api/v1/shifts/$yol/$id/${onay ? 'approve' : 'reject'}', govde);
      HapticFeedback.mediumImpact();
      bildir(onay ? 'Talep onaylandı' : 'Talep reddedildi', mesaj: 'Personele bildirim gider.');
      await _talepYukle();
    } on ApiHata catch (e) {
      hataBildir(e, yetkiMesaji: 'Talepleri onaylamak için "Personel yönet" yetkisi gerekir.');
    } finally {
      if (mounted) setState(() => _mesgul.remove(anahtar));
    }
  }

  Future<int?> _kisiSec(String baslik, {int? haric}) async {
    if (Canli.meta.value == null) await Canli.metaTazele();
    if (!mounted) return null;
    final kisiler = Canli.personel.where((p) => p.i('id') != haric).toList();
    return pencereAc<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(baslik),
        children: [
          for (final p in kisiler)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p.i('id')),
              child: Row(
                children: [
                  Avatar(p.s('name'), boyut: 30),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.s('name'))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bekleyen = (_izinler?.length ?? Canli.bekleyenIzin.value) + (_takaslar?.length ?? Canli.bekleyenTakas.value);
    return PaSayfa(
      baslik: 'Mesai ve devam',
      alt: 'Kim içeride, kim geç kaldı, bekleyen talepler',
      geri: true,
      yenile: _yukle,
      sag: IconButton.filledTonal(
        tooltip: 'İzin / rapor gir',
        style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap)),
        onPressed: () async {
          final ok = await izinFormuAc(context);
          if (ok == true && _sekme == 1) _talepYukle();
        },
        icon: const Icon(Icons.beach_access_rounded),
      ),
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: Marka.yaricap),
            minimumSize: const Size(44, 46),
          ),
          segments: [
            const ButtonSegment(value: 0, label: Text('Gün'), icon: Icon(Icons.view_list_rounded, size: 18)),
            ButtonSegment(value: 1, label: Text(bekleyen > 0 ? 'Talepler ($bekleyen)' : 'Talepler'), icon: const Icon(Icons.inbox_rounded, size: 18)),
            const ButtonSegment(value: 2, label: Text('Hafta'), icon: Icon(Icons.insights_rounded, size: 18)),
          ],
          selected: {_sekme},
          onSelectionChanged: (s) => _sekmeSec(s.first),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
          transitionBuilder: asamaGecisi,
          child: KeyedSubtree(
            key: ValueKey(_sekme),
            child: switch (_sekme) {
              0 => _gunTablosu(),
              1 => _talepler(),
              _ => _hafta(),
            },
          ),
        ),
      ],
    );
  }

  Widget _hataKarti(ApiHata h, VoidCallback yenile) => PaKart(
    child: h.kod == 404
        ? const BosDurum(baslik: 'Vardiya / Mesai eklentisi kapalı', ikon: Icons.extension_off_rounded)
        : h.yetkiYok
        ? const BosDurum(baslik: 'Bu bölümü görme yetkiniz yok', mesaj: '"Personeli görüntüle" yetkisi gerekir.', ikon: Icons.lock_rounded)
        : HataDurum(hata: h, yenile: yenile),
  );

  /* ── Gün tablosu ── */

  Widget _gunTablosu() {
    final r = context.pa;
    final t = _tablo;
    final bugun = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final secici = Row(
      children: [
        IconButton(
          tooltip: 'Önceki gün',
          onPressed: () {
            setState(() {
              _gun = _gun.subtract(const Duration(days: 1));
              _tablo = null;
            });
            _tabloYukle();
          },
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final g = await gunSec(context, _gun, sonGun: bugun.add(const Duration(days: 30)));
              if (g == null) return;
              setState(() {
                _gun = g;
                _tablo = null;
              });
              _tabloYukle();
            },
            child: Text(
              _gun == bugun ? 'Bugün · ${Bicim.gunAy(_gun)}' : '${Bicim.gunAdi(_gun)}, ${Bicim.gunAy(_gun)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sonraki gün',
          onPressed: () {
            setState(() {
              _gun = _gun.add(const Duration(days: 1));
              _tablo = null;
            });
            _tabloYukle();
          },
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
    if (t == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          secici,
          if (_tabloHata != null)
            _hataKarti(_tabloHata!, _tabloYukle)
          else ...[
            const Iskelet(yukseklik: 84),
            const SizedBox(height: 10),
            const Iskelet(yukseklik: 220),
          ],
        ],
      );
    }
    final oz = t.m('ozet');
    final satirlar = t.l('satirlar')
      ..sort((a, b) {
        const sira = ['calisiyor', 'gelmedi', 'bekliyor', 'izinli', 'cikti'];
        return sira.indexOf(a.s('durum')).compareTo(sira.indexOf(b.s('durum')));
      });
    Widget kutu(String ad, int n, Color c, IconData ikon) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: r.koyu ? .18 : .08),
          borderRadius: Marka.yaricap,
          border: Border.all(color: c.withValues(alpha: .3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikon, size: 16, color: c),
            const SizedBox(height: 4),
            SayacMetin(
              deger: n,
              yaz: (v) => Bicim.sayi(v),
              stil: gosterim(20, renk: c),
            ),
            Text(
              ad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.soluk, fontSize: 11),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        secici,
        Row(
          children: [
            kutu('Çalışıyor', oz.i('calisan'), r.arti, Icons.login_rounded),
            const SizedBox(width: 6),
            kutu('Geç kalan', oz.i('gec'), r.uyari, Icons.alarm_rounded),
            const SizedBox(width: 6),
            kutu('Gelmedi', oz.i('gelmedi'), r.eksi, Icons.person_off_rounded),
            const SizedBox(width: 6),
            kutu('İzinli', oz.i('izinli'), Marka.mavi, Icons.beach_access_rounded),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Toplam çalışma ${Bicim.dakika(oz.i('calisilan_dk'))} · ${oz.i('vardiyali')} vardiyalı kişi · tolerans ${t.i('tolerans_dk')} dk',
          style: TextStyle(color: r.silik, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (satirlar.isEmpty)
          const PaKart(
            child: BosDurum(
              baslik: 'Bu gün kayıt yok',
              mesaj: 'Planlı vardiya ya da mesai girişi olmayan günlerde tablo boş kalır.',
              ikon: Icons.event_available_rounded,
            ),
          )
        else
          SatirGrubu([for (final s in satirlar) _kisiSatiri(s)]),
        const SizedBox(height: 10),
        const BilgiNotu(
          'Kişiye dokunun: mesai kaydını düzeltin, onaylayın ya da çıkışı unutanın çıkışını verin. Giriş yapmamış personel için yeni kayıt eklenemez (personel QR ile girer).',
          ikon: Icons.touch_app_rounded,
        ),
      ],
    );
  }

  Widget _kisiSatiri(Map<String, dynamic> s) {
    final r = context.pa;
    final (dAd, dRenk) = mesaiDurumu(s.s('durum'), r);
    final v = s.m('vardiya');
    final vb = _t(v['starts_at']), vs = _t(v['ends_at']);
    final g = _t(s['giris']), c = _t(s['cikis']);
    final plan = vb == null ? 'Plansız' : 'Plan ${Bicim.saat(vb)}–${vs == null ? '?' : Bicim.saat(vs)}';
    final gec = s.i('gec_dk');
    return Basilir(
      onTap: () => _kayitlar(s),
      etiket: '${s.m('user').s('name')}, $dAd',
      olcek: .99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Avatar(s.m('user').s('name'), boyut: 38, nokta: s.s('durum') == 'calisiyor' ? r.arti : null),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.m('user').s('name', '—'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      if (gec > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: r.uyari.withValues(alpha: .15), borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            '$gec dk geç',
                            style: TextStyle(color: r.uyari, fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    [
                      plan,
                      if (g != null) 'Giriş ${Bicim.saat(g)}',
                      if (c != null) 'Çıkış ${Bicim.saat(c)}',
                      if (s.i('mola_dk') > 0) 'Mola ${s.i('mola_dk')} dk',
                      if (s.s('izin_adi').isNotEmpty) s.s('izin_adi'),
                    ].join(' · '),
                    maxLines: 2,
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: dRenk.withValues(alpha: r.koyu ? .22 : .12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    dAd,
                    style: TextStyle(color: dRenk, fontWeight: FontWeight.w700, fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s.i('calisilan_dk') > 0 ? Bicim.dakika(s.i('calisilan_dk')) : '',
                  style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _kayitlar(Map<String, dynamic> s) async {
    final degisti = await altSayfaAc<bool>(context, (_) => _KayitSayfasi(kisi: s.m('user'), gun: _gun));
    if (degisti == true) _tabloYukle();
  }

  /* ── Talepler ── */

  Widget _talepler() {
    final r = context.pa;
    if (_izinler == null || _takaslar == null) {
      if (_talepHata != null) return _hataKarti(_talepHata!, _talepYukle);
      return const Column(children: [Iskelet(yukseklik: 96), SizedBox(height: 10), Iskelet(yukseklik: 96)]);
    }
    if (_izinler!.isEmpty && _takaslar!.isEmpty) {
      return PaKart(
        child: Column(
          children: [
            const BosDurum(
              baslik: 'Bekleyen talep yok',
              mesaj: 'Personelin izin ve vardiya değişim talepleri burada onayınıza düşer.',
              ikon: Icons.mark_email_read_rounded,
            ),
            YumusakDugme(
              onTap: () async {
                final ok = await izinFormuAc(context);
                if (ok == true) _talepYukle();
              },
              ikon: Icons.beach_access_rounded,
              yazi: 'Personel adına izin gir',
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_izinler!.isNotEmpty) ...[
          BolumBasligi('İzin talepleri', ikon: Icons.beach_access_rounded, alt: '${_izinler!.length} bekliyor'),
          for (final l in _izinler!) _talepKarti('leave', l, r),
          const SizedBox(height: 8),
        ],
        if (_takaslar!.isNotEmpty) ...[
          BolumBasligi('Vardiya değişim talepleri', ikon: Icons.swap_horiz_rounded, alt: '${_takaslar!.length} bekliyor'),
          for (final w in _takaslar!) _talepKarti('swap', w, r),
        ],
      ],
    );
  }

  Widget _talepKarti(String tur, Map<String, dynamic> x, PaRenk r) {
    final mesgul = _mesgul.contains('$tur${x.i('id')}');
    late final String kisi;
    late final String baslik;
    late final String alt;
    if (tur == 'leave') {
      kisi = x.m('user').s('name', '—');
      final a = Bicim.gunCoz(x.s('starts_on')), b = Bicim.gunCoz(x.s('ends_on'));
      final gun = a == null || b == null ? 0 : b.difference(a).inDays + 1;
      baslik = izinTurleri[x.s('type')] ?? 'İzin';
      alt = a == null || b == null ? '' : '${Bicim.aralik(a, b)} · $gun gün';
    } else {
      final sh = x.m('shift');
      kisi = sh.m('user').s('name', x.m('requested_by').s('name', '—'));
      final a = _t(sh['starts_at']), b = _t(sh['ends_at']);
      baslik = x.m('target_user').isEmpty ? 'Vardiyasını devretmek istiyor' : '${x.m('target_user').s('name')} devralsın';
      alt = a == null ? '' : '${Bicim.gunAdi(a)} ${Bicim.gunAyKisa(a)} · ${Bicim.saat(a)}–${b == null ? '?' : Bicim.saat(b)}';
    }
    final olusma = _t(x['created_at']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PaKart(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Avatar(kisi, boyut: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kisi,
                        style: TextStyle(color: r.metin, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        baslik,
                        style: TextStyle(color: r.birincil, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (alt.isNotEmpty) Text(alt, style: TextStyle(color: r.silik, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (olusma != null) Text(Bicim.tarihSaat(olusma), style: TextStyle(color: r.silik, fontSize: 11)),
              ],
            ),
            if (x.s('reason').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap),
                child: Text(
                  '“${x.s('reason')}”',
                  style: TextStyle(color: r.soluk, fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: YumusakDugme(
                    onTap: mesgul ? null : () => _karar(tur, x, false),
                    renk: r.eksi,
                    zemin: r.eksi.withValues(alpha: r.koyu ? .16 : .08),
                    ikon: Icons.close_rounded,
                    yazi: 'Reddet',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: YumusakDugme(
                    onTap: mesgul ? null : () => _karar(tur, x, true),
                    renk: Colors.white,
                    zemin: Marka.zumrut,
                    yukleniyor: mesgul,
                    ikon: Icons.check_rounded,
                    yazi: 'Onayla',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /* ── Haftalık ── */

  Widget _hafta() {
    final r = context.pa;
    final h = _haftalik;
    if (h == null) {
      if (_haftaHata != null) return _hataKarti(_haftaHata!, _haftaYukle);
      return const Iskelet(yukseklik: 260);
    }
    final dolu = h.where((x) => x.i('worked_min') > 0 || x.i('planned_shifts') > 0).toList()
      ..sort((a, b) => b.i('worked_min').compareTo(a.i('worked_min')));
    if (dolu.isEmpty) {
      return const PaKart(
        child: BosDurum(baslik: 'Bu hafta mesai kaydı yok', ikon: Icons.insights_rounded),
      );
    }
    final top = dolu.fold<int>(0, (a, x) => a + x.i('worked_min'));
    final fazla = dolu.fold<int>(0, (a, x) => a + x.i('overtime_min'));
    final gec = dolu.fold<int>(0, (a, x) => a + x.i('late_count'));
    final enCok = math.max(1, dolu.first.i('worked_min'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Mini('Toplam çalışma', Bicim.dakika(top), r.birincil)),
            const SizedBox(width: 8),
            Expanded(child: _Mini('Fazla mesai', Bicim.dakika(fazla), r.uyari)),
            const SizedBox(width: 8),
            Expanded(child: _Mini('Geç kalma', '$gec kez', r.eksi)),
          ],
        ),
        const SizedBox(height: 12),
        PaKart(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BolumBasligi('Kişi başı çalışma', ikon: Icons.bar_chart_rounded, alt: 'Bu hafta · saat'),
              SutunGrafik(
                yukseklik: 150,
                noktalar: [for (final x in dolu.take(10)) Nokta(basHarf(x.m('user').s('name')), x.i('worked_min') / 60, uzun: x.m('user').s('name'))],
                yaz: (d) => '${Bicim.ondalik(d)} sa',
                renk: Marka.mavi,
                ozet: 'Bu hafta kişi başı çalışma saatleri',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PaKart(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BolumBasligi('Devam özeti', ikon: Icons.fact_check_rounded),
              for (var i = 0; i < dolu.length; i++)
                CubukSatir(
                  sira: i + 1,
                  ad: dolu[i].m('user').s('name'),
                  deger: Bicim.dakika(dolu[i].i('worked_min')),
                  alt: [
                    '${dolu[i].i('days_worked')}/${dolu[i].i('planned_shifts')} gün',
                    if (dolu[i].i('late_count') > 0) '${dolu[i].i('late_count')} geç',
                    if (dolu[i].i('auto_absent_days') > 0) '${dolu[i].i('auto_absent_days')} gelmedi',
                  ].join(' · '),
                  oran: dolu[i].i('worked_min') / enCok,
                  renk: dolu[i].i('late_count') > 0 ? Marka.kehribar : Marka.mor,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.ad, this.deger, this.renk);
  final String ad;
  final String deger;
  final Color renk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: r.kart,
        borderRadius: Marka.yaricap,
        border: Border.all(color: r.kenar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 3,
            decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(1.5)),
          ),
          const SizedBox(height: 6),
          Text(
            ad,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: r.silik, fontSize: 11.5),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(deger, style: gosterim(16, renk: r.metin)),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────── Kayıtlar (düzelt / onayla) ───────────────────────── */

class _KayitSayfasi extends StatefulWidget {
  const _KayitSayfasi({required this.kisi, required this.gun});
  final Map<String, dynamic> kisi;
  final DateTime gun;
  @override
  State<_KayitSayfasi> createState() => _KayitSayfasiState();
}

class _KayitSayfasiState extends State<_KayitSayfasi> {
  List<Map<String, dynamic>>? _kayit;
  ApiHata? _hata;
  bool _degisti = false;
  int? _mesgul;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await Uyg.api.get(
        '/api/v1/shifts/time-entries',
        sorgu: {'user_id': widget.kisi.i('id'), 'from': gunIso(widget.gun.subtract(const Duration(days: 1))), 'to': gunIso(widget.gun)},
      );
      final g = widget.gun;
      final l = (r is Map ? r.l('data') : <Map<String, dynamic>>[]).where((e) {
        final d = _t(e['clock_in_at']);
        return d != null && d.year == g.year && d.month == g.month && d.day == g.day;
      }).toList();
      if (mounted) setState(() => _kayit = l);
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e);
    }
  }

  Future<void> _duzelt(Map<String, dynamic> e, {bool cikisVer = false}) async {
    final giris = _t(e['clock_in_at'])!;
    var cikis = _t(e['clock_out_at']) ?? (cikisVer ? DateTime.now() : null);
    var mola = e.i('break_total_min');
    final sonuc = await altSayfaAc<Map<String, dynamic>>(context, (_) => _DuzeltFormu(giris: giris, cikis: cikis, mola: mola, cikisVer: cikisVer));
    if (sonuc == null) return;
    setState(() => _mesgul = e.i('id'));
    try {
      await Uyg.api.put('/api/v1/shifts/time-entries/${e.i('id')}', sonuc);
      _degisti = true;
      bildir(cikisVer ? 'Çıkış verildi' : 'Mesai kaydı düzeltildi', mesaj: 'Değişiklik gerekçesiyle kayda geçti.');
      await _yukle();
    } on ApiHata catch (x) {
      hataBildir(x, yetkiMesaji: 'Mesai düzeltmek için "Personel yönet" yetkisi gerekir.');
    } finally {
      if (mounted) setState(() => _mesgul = null);
    }
  }

  Future<void> _onayla(Map<String, dynamic> e) async {
    setState(() => _mesgul = e.i('id'));
    try {
      await Uyg.api.post('/api/v1/shifts/time-entries/${e.i('id')}/approve');
      _degisti = true;
      bildir('Mesai onaylandı');
      await _yukle();
    } on ApiHata catch (x) {
      hataBildir(x, yetkiMesaji: 'Mesai onaylamak için "Personel yönet" yetkisi gerekir.');
    } finally {
      if (mounted) setState(() => _mesgul = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (ok, _) {
        if (!ok) Navigator.of(context).pop(_degisti);
      },
      child: AltSayfa(
        baslik: widget.kisi.s('name', 'Personel'),
        alt: '${Bicim.gunAdi(widget.gun)}, ${Bicim.gunAy(widget.gun)} · mesai kayıtları',
        ikon: Icons.badge_rounded,
        children: [
          if (_kayit == null && _hata != null)
            HataDurum(hata: _hata!, yenile: _yukle)
          else if (_kayit == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Yukleyici()),
            )
          else if (_kayit!.isEmpty)
            const BosDurum(
              baslik: 'Bu gün giriş kaydı yok',
              mesaj: 'Personel giriş yapmadığı için düzeltilecek kayıt yok.',
              ikon: Icons.login_rounded,
            )
          else
            for (final e in _kayit!)
              Builder(
                builder: (_) {
                  final g = _t(e['clock_in_at'])!;
                  final c = _t(e['clock_out_at']);
                  final acik = c == null;
                  final onayli = e.s('approved_at').isNotEmpty;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('${Bicim.saat(g)} → ${c == null ? 'içeride' : Bicim.saat(c)}', style: gosterim(18, renk: r.metin)),
                            const Spacer(),
                            if (onayli) Icon(Icons.verified_rounded, color: r.arti, size: 20),
                            if (acik)
                              Text(
                                'Açık',
                                style: TextStyle(color: r.arti, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            'Çalışılan ${Bicim.dakika(e.i('worked_min'))}',
                            if (e.i('break_total_min') > 0) 'mola ${e.i('break_total_min')} dk',
                            if (e.i('late_min') > 0) '${e.i('late_min')} dk geç',
                            if (e.i('overtime_min') > 0) '${Bicim.dakika(e.i('overtime_min'))} fazla',
                            if (e.s('method_in').isNotEmpty) 'giriş: ${e.s('method_in')}',
                          ].join(' · '),
                          style: TextStyle(color: r.silik, fontSize: 12.5),
                        ),
                        if (e.s('edit_reason').isNotEmpty) Text('Düzeltildi: ${e.s('edit_reason')}', style: TextStyle(color: r.uyari, fontSize: 12)),
                        const SizedBox(height: 8),
                        if (_mesgul == e.i('id'))
                          const Center(child: Yukleyici(boyut: 22))
                        else
                          Row(
                            children: [
                              Expanded(
                                child: YumusakDugme(
                                  onTap: () => _duzelt(e),
                                  yukseklik: 46,
                                  ikon: Icons.edit_rounded,
                                  yazi: 'Düzelt',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: acik
                                    ? YumusakDugme(
                                        onTap: () => _duzelt(e, cikisVer: true),
                                        yukseklik: 46,
                                        renk: Colors.white,
                                        zemin: Marka.mor,
                                        ikon: Icons.logout_rounded,
                                        yazi: 'Çıkış ver',
                                      )
                                    : YumusakDugme(
                                        onTap: onayli ? null : () => _onayla(e),
                                        yukseklik: 46,
                                        renk: Colors.white,
                                        zemin: Marka.zumrut,
                                        ikon: Icons.verified_rounded,
                                        yazi: onayli ? 'Onaylı' : 'Onayla',
                                      ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DuzeltFormu extends StatefulWidget {
  const _DuzeltFormu({required this.giris, required this.cikis, required this.mola, required this.cikisVer});
  final DateTime giris;
  final DateTime? cikis;
  final int mola;
  final bool cikisVer;
  @override
  State<_DuzeltFormu> createState() => _DuzeltFormuState();
}

class _DuzeltFormuState extends State<_DuzeltFormu> {
  late TimeOfDay _g = TimeOfDay.fromDateTime(widget.giris);
  late TimeOfDay? _c = widget.cikis == null ? null : TimeOfDay.fromDateTime(widget.cikis!);
  late int _mola = widget.mola;
  late final _neden = TextEditingController(text: widget.cikisVer ? 'Çıkış yapmayı unuttu' : '');

  @override
  void dispose() {
    _neden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.giris;
    final g = DateTime(d.year, d.month, d.day, _g.hour, _g.minute);
    DateTime? c;
    if (_c != null) {
      c = DateTime(d.year, d.month, d.day, _c!.hour, _c!.minute);
      if (!c.isAfter(g)) c = c.add(const Duration(days: 1));
    }
    final gecerli = _neden.text.trim().length >= 3;
    return AltSayfa(
      baslik: widget.cikisVer ? 'Çıkış ver' : 'Mesai kaydını düzelt',
      alt: 'Değişiklik gerekçesiyle denetim kaydına geçer',
      ikon: Icons.edit_calendar_rounded,
      dugmeler: KaydetDugmesi(
        yazi: 'Kaydet',
        onPressed: !gecerli
            ? null
            : () => Navigator.of(context).pop(<String, dynamic>{
                'clock_in_at': utcIso(g),
                if (c != null) 'clock_out_at': utcIso(c),
                'break_total_min': _mola,
                'reason': _neden.text.trim(),
              }),
      ),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SaatKutusu(
                ad: 'Giriş',
                saat: _g,
                onTap: () async {
                  final t = await saatSec(context, _g, baslik: 'Giriş saati');
                  if (t != null) setState(() => _g = t);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SaatKutusu(
                ad: 'Çıkış',
                saat: _c ?? TimeOfDay.now(),
                not: _c == null ? 'Yok' : (c != null && c.day != g.day ? '+1 gün' : null),
                onTap: () async {
                  final t = await saatSec(context, _c ?? TimeOfDay.now(), baslik: 'Çıkış saati');
                  if (t != null) setState(() => _c = t);
                },
              ),
            ),
          ],
        ),
        const AlanBasligi('MOLA'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in {0, 15, 30, 45, 60, _mola}.toList()..sort())
              SecimCipi(yazi: m == 0 ? 'Yok' : '$m dk', secili: _mola == m, onTap: () => setState(() => _mola = m)),
          ],
        ),
        const AlanBasligi('GEREKÇE (ZORUNLU)'),
        TextField(
          controller: _neden,
          maxLength: 255,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Örn. Kart okutmayı unuttu'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/* ───────────────────────── İzin formu ───────────────────────── */

/// Personel adına izin / rapor girişi. POST /api/v1/shifts/leave-requests
/// (user_id, type, starts_on, ends_on, reason). Yönetici başkası için
/// girince sunucu doğrudan onaylı kaydeder.
Future<bool?> izinFormuAc(BuildContext context, {int? kisi}) async {
  if (Canli.meta.value == null) await Canli.metaTazele();
  if (!context.mounted) return null;
  return altSayfaAc<bool>(context, (_) => _IzinFormu(kisi: kisi));
}

class _IzinFormu extends StatefulWidget {
  const _IzinFormu({this.kisi});
  final int? kisi;
  @override
  State<_IzinFormu> createState() => _IzinFormuState();
}

class _IzinFormuState extends State<_IzinFormu> {
  late int? _kisi = widget.kisi;
  String _tur = 'annual';
  late DateTime _bas = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late DateTime _son = _bas;
  final _neden = TextEditingController();
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _neden.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kisi == null) {
      setState(() => _hata = 'Kişi seçin.');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/shifts/leave-requests', {
        'user_id': _kisi,
        'type': _tur,
        'starts_on': gunIso(_bas),
        'ends_on': gunIso(_son),
        if (_neden.text.trim().isNotEmpty) 'reason': _neden.text.trim(),
      });
      HapticFeedback.mediumImpact();
      bildir('İzin kaydedildi', mesaj: '${izinTurleri[_tur]} · ${Bicim.aralik(_bas, _son)}');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiHata catch (e) {
      setState(() {
        _mesgul = false;
        _hata = e.yetkiYok ? 'Personel adına izin girmek için "Personel yönet" yetkisi gerekir.' : e.mesaj;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final gun = _son.difference(_bas).inDays + 1;
    return AltSayfa(
      baslik: 'İzin / rapor gir',
      alt: 'Personel adına; onaylı olarak kaydedilir',
      ikon: Icons.beach_access_rounded,
      dugmeler: KaydetDugmesi(yazi: 'Kaydet ($gun gün)', mesgul: _mesgul, onPressed: _kaydet),
      children: [
        const AlanBasligi('KİŞİ'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in Canli.personel) SecimCipi(yazi: p.s('name'), secili: _kisi == p.i('id'), onTap: () => setState(() => _kisi = p.i('id'))),
            if (Canli.personel.isEmpty) Text('Personel listesi alınamadı.', style: TextStyle(color: r.silik)),
          ],
        ),
        const AlanBasligi('TÜR'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final e in izinTurleri.entries) SecimCipi(yazi: e.value, secili: _tur == e.key, onTap: () => setState(() => _tur = e.key))],
        ),
        const AlanBasligi('TARİH'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final g = await gunSec(context, _bas);
                  if (g != null) {
                    setState(() {
                      _bas = g;
                      if (_son.isBefore(g)) _son = g;
                    });
                  }
                },
                icon: const Icon(Icons.event_rounded),
                label: Text('Başlangıç ${Bicim.gunAyKisa(_bas)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final g = await gunSec(context, _son, ilkGun: _bas);
                  if (g != null) setState(() => _son = g);
                },
                icon: const Icon(Icons.event_available_rounded),
                label: Text('Bitiş ${Bicim.gunAyKisa(_son)}'),
              ),
            ),
          ],
        ),
        const AlanBasligi('AÇIKLAMA'),
        TextField(
          controller: _neden,
          maxLength: 255,
          decoration: const InputDecoration(hintText: 'İsteğe bağlı'),
        ),
        const BilgiNotu('Onaylı izin günlerine vardiya atanamaz; personele bildirim gider.'),
        if (_hata != null) ...[const SizedBox(height: 10), BilgiNotu(_hata!, ikon: Icons.error_outline_rounded, renk: r.eksi)],
        const SizedBox(height: 8),
      ],
    );
  }
}
