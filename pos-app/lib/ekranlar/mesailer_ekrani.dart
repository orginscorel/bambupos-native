import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'ortak.dart';

/// MESAİLER — web /panel/mesai (Panel/Shifts/Mesailer.vue) birebiri.
/// Seçilen günün vardiya tablosu: tek uç GET /api/v1/shifts/day-board?gun=.
/// Hesap sunucuda (AttendanceService::dayBoard); burada yalnız çizilir.
/// ≥1024 px: çerçeveli kişi kutuları (7 sütun), altında kart listesi.
class MesailerEkrani extends StatefulWidget {
  const MesailerEkrani({super.key});

  @override
  State<MesailerEkrani> createState() => _MesailerEkraniState();
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// lib.ts fmtMin: "45dk" · "8s" · "7s 30dk".
String _dk(int? m) {
  if (m == null) return '—';
  final s = m ~/ 60;
  final d = m % 60;
  if (s == 0) return '${d}dk';
  if (d == 0) return '${s}s';
  return '${s}s ${d}dk';
}

String _saat(Object? iso) {
  final t = saatMetni(iso?.toString());
  return t.isEmpty ? '—' : t;
}

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

class _MesailerEkraniState extends State<MesailerEkrani> {
  late final Api _api = context.api;
  late DateTime _gun = _bugun;
  bool _yukleniyor = true;
  String _hata = '';
  List<Map<String, dynamic>> _satirlar = const [];
  Map<String, dynamic>? _ozet;
  int _tolerans = 0;

  static DateTime get _bugun {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _buGun => _ymd(_gun) == _ymd(_bugun);

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = '';
    });
    try {
      final r = await _api.get('/api/v1/shifts/day-board', sorgu: {'gun': _ymd(_gun)});
      if (!mounted) return;
      final m = r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
      setState(() {
        _satirlar = (m['satirlar'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _ozet = m['ozet'] is Map ? (m['ozet'] as Map).cast<String, dynamic>() : null;
        _tolerans = tamSayi(m['tolerans_dk']);
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = e.mesaj.isEmpty ? 'Vardiya tablosu alınamadı.' : e.mesaj;
        _satirlar = const [];
        _ozet = null;
      });
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _kaydir(int n) {
    _gun = _gun.add(Duration(days: n));
    _yukle();
  }

  Future<void> _tarihSec() async {
    final s = await showDatePicker(
      context: context,
      initialDate: _gun,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (s == null) return;
    _gun = DateTime(s.year, s.month, s.day);
    _yukle();
  }

  String get _tarihUzun => '${_gun.day.toString().padLeft(2, '0')} ${_aylar[_gun.month - 1]} ${_gun.year} ${_gunler[_gun.weekday - 1]}';

  /* ── Sunum yardımcıları ── */

  static const _durumAd = {'calisiyor': 'Çalışıyor', 'cikti': 'Çıktı', 'bekliyor': 'Bekliyor', 'gelmedi': 'Gelmedi', 'izinli': 'İzinli'};
  static const _durumTon = {'calisiyor': 'iyi', 'cikti': 'notr', 'bekliyor': 'notr', 'gelmedi': 'kotu', 'izinli': 'uyari'};

  Color _ton(String? t) => switch (t) {
        'iyi' => Kabuk.success,
        'uyari' => Kabuk.warning,
        'kotu' => Kabuk.negative,
        _ => Kabuk.soft,
      };

  Map<String, dynamic> _kisi(Map<String, dynamic> s) => s['user'] is Map ? (s['user'] as Map).cast<String, dynamic>() : const {};
  Map<String, dynamic>? _vardiya(Map<String, dynamic> s) => s['vardiya'] is Map ? (s['vardiya'] as Map).cast<String, dynamic>() : null;

  String _durum(Map<String, dynamic> s) {
    final d = '${s['durum'] ?? ''}';
    if (d == 'izinli' && s['izin_adi'] != null) return '${s['izin_adi']}';
    return _durumAd[d] ?? d;
  }

  String? _girisTon(Map<String, dynamic> s) => s['dakiklik'] == 'gec' ? 'kotu' : (s['dakiklik'] == 'zamaninda' ? 'iyi' : null);

  /// lib.ts vardiyaTuru: dilim (sabah/akşam/gece) + net süre (6 sa eşiği).
  ({String dilim, String sure, int netDk}) _tur(Map<String, dynamic> v) {
    final bas = DateTime.tryParse('${v['starts_at']}')?.toLocal();
    final bit = DateTime.tryParse('${v['ends_at']}')?.toLocal();
    if (bas == null || bit == null) return (dilim: 'gece', sure: 'part', netDk: 0);
    final net = (bit.difference(bas).inMinutes - tamSayi(v['break_min']).clamp(0, 9999)).clamp(0, 99999);
    final ertesi = _ymd(bas) != _ymd(bit);
    final gece = bas.hour >= 22 || bas.hour < 5 || (ertesi && bit.hour >= 2);
    return (dilim: gece ? 'gece' : (bas.hour < 14 ? 'sabah' : 'aksam'), sure: net < 360 ? 'part' : 'tam', netDk: net);
  }

  Widget _aralik(Map<String, dynamic> v, {double boy = 16.5}) {
    final t = _tur(v);
    final renk = switch (t.dilim) {
      'sabah' => Kabuk.warning,
      'aksam' => Kabuk.brand,
      _ => Kabuk.soft,
    };
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '${_saat(v['starts_at'])} - ${_saat(v['ends_at'])}',
          style: TextStyle(fontSize: boy, fontWeight: FontWeight.w800, letterSpacing: -.2, color: renk),
        ),
        const TextSpan(text: '  '),
        TextSpan(
          text: _dk(t.netDk),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.sure == 'tam' ? Kabuk.success : Kabuk.info),
        ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _rozet(Map<String, dynamic> s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
        child: Text(_durum(s),
            maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _ton(_durumTon['${s['durum']}']))),
      );

  /* ── Parçalar ── */

  List<({String ad, String deger, IconData ikon, String? ton})> get _cipler {
    final o = _ozet;
    int n(String k) => tamSayi(o?[k]);
    return [
      (ad: 'Vardiyası olan', deger: '${n('vardiyali')}', ikon: Icons.calendar_today_outlined, ton: null),
      (ad: _buGun ? 'Şu an mesaide' : 'Çıkışsız kayıt', deger: '${n('calisan')}', ikon: Icons.schedule_rounded, ton: n('calisan') > 0 ? 'iyi' : null),
      (ad: 'Geç gelen', deger: '${n('gec')}', ikon: Icons.warning_amber_rounded, ton: n('gec') > 0 ? 'kotu' : null),
      (ad: 'Gelmeyen', deger: '${n('gelmedi')}', ikon: Icons.cancel_outlined, ton: n('gelmedi') > 0 ? 'uyari' : null),
      (ad: 'Çalışılan süre', deger: _dk(n('calisilan_dk')), ikon: Icons.history_rounded, ton: null),
    ];
  }

  Widget _ozetSatiri({required bool ust}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: ust ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final c in _cipler)
            Container(
              constraints: BoxConstraints(minHeight: ust ? 30 : 34),
              padding: EdgeInsets.symmetric(horizontal: ust ? 9 : 11, vertical: 3),
              decoration: BoxDecoration(color: Kabuk.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(c.ikon, size: 14, color: Kabuk.soft),
                const SizedBox(width: 6),
                Text(c.deger, style: TextStyle(fontSize: ust ? 13 : 14, fontWeight: FontWeight.w800, color: c.ton == null ? Kabuk.ink : _ton(c.ton))),
                const SizedBox(width: 6),
                Text(c.ad, style: TextStyle(fontSize: ust ? 11.5 : 12, color: Kabuk.soft)),
              ]),
            ),
        ],
      );

  Widget _gunGezinme({required bool genis}) {
    Widget ok(IconData i, String ipucu, VoidCallback bas) => Tooltip(
          message: ipucu,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: bas,
            child: SizedBox(width: 32, height: 30, child: Icon(i, size: 16, color: Kabuk.soft)),
          ),
        );
    final tarih = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: _tarihSec,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (genis) ...[Icon(Icons.calendar_today_outlined, size: 15, color: Kabuk.soft), const SizedBox(width: 6)],
            Text(
              '${_gun.day.toString().padLeft(2, '0')}.${_gun.month.toString().padLeft(2, '0')}.${_gun.year}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Kabuk.ink),
            ),
          ]),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Kabuk.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
      child: Row(
        mainAxisSize: genis ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [ok(Icons.chevron_left_rounded, 'Önceki gün', () => _kaydir(-1)), tarih, ok(Icons.chevron_right_rounded, 'Sonraki gün', () => _kaydir(1))],
      ),
    );
  }

  Widget _bos({required bool genis}) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: genis ? 30 : 22, horizontal: 14),
        decoration: BoxDecoration(color: Kabuk.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
        child: Column(children: [
          if (genis) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.people_outline_rounded, size: 20, color: Kabuk.soft),
            ),
            const SizedBox(height: 8),
          ],
          Text('$_tarihUzun için vardiya ya da mesai kaydı yok',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Kabuk.ink)),
          const SizedBox(height: 4),
          Text(
            '${genis ? 'Burada' : 'Bu tabloda'} yalnız o güne planlanmış vardiyalar ve o gün açılan giriş/çıkış kayıtları görünür. '
            'Vardiya planı “Plan” ekranından kurulur; giriş/çıkış PIN ekranından ya da kiosk cihazından alınır.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.6, color: Kabuk.soft),
          ),
        ]),
      );

  /// Telefon/tablet kartı.
  Widget _kart(Map<String, dynamic> s) {
    final u = _kisi(s);
    final v = _vardiya(s);
    final devam = s['devam'] == true;
    Widget ol(String baslik, String deger, {String? ton, String? alt}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .4, color: Kabuk.soft)),
            Text(deger, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ton == null ? Kabuk.ink : _ton(ton))),
            if (alt != null) Text(alt, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Kabuk.soft)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(color: Kabuk.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${u['name'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.ink)),
          ),
          const SizedBox(width: 8),
          _rozet(s),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          if (v != null)
            Flexible(child: _aralik(v, boy: 15))
          else ...[
            Icon(Icons.calendar_today_outlined, size: 13, color: Kabuk.soft),
            const SizedBox(width: 5),
            Text('Planlı vardiya yok', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Kabuk.soft)),
          ],
          if (u['position'] != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text('${u['position']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ol('Giriş', _saat(s['giris']), ton: _girisTon(s), alt: tamSayi(s['gec_dk']) > 0 ? '${s['gec_dk']} dk geç' : null),
            const SizedBox(width: 6),
            ol('Çıkış', devam ? '—' : _saat(s['cikis']), alt: devam ? 'devam ediyor' : null),
            const SizedBox(width: 6),
            ol('Mola', tamSayi(s['mola_dk']) > 0 ? _dk(tamSayi(s['mola_dk'])) : '—'),
            const SizedBox(width: 6),
            ol('Çalışılan', s['giris'] != null ? _dk(tamSayi(s['calisilan_dk'])) : '—'),
          ]),
        ),
      ]),
    );
  }

  static const _oranlar = [1.7, 1.5, 1.0, 1.0, 0.85, 0.9, 1.0];

  Widget _izgara(List<Widget> h) => Row(children: [
        for (var i = 0; i < h.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(flex: (_oranlar[i] * 100).round(), child: h[i]),
        ],
      ]);

  /// Masaüstü: çerçeveli kişi kutusu (7 sütun, başlıkla aynı ızgara).
  Widget _satir(Map<String, dynamic> s) {
    final u = _kisi(s);
    final v = _vardiya(s);
    final devam = s['devam'] == true;
    final gec = tamSayi(s['gec_dk']);
    Widget alt(String m, {Color? renk, FontWeight w = FontWeight.w600}) =>
        Text(m, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: w, color: renk ?? Kabuk.soft));
    Widget buyuk(String m, {String? ton}) => Text(m,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.2, color: ton == null ? Kabuk.ink : _ton(ton)));

    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Kabuk.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
      child: _izgara([
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${u['name'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Kabuk.ink)),
          if (u['position'] != null)
            Text('${u['position']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Kabuk.soft)),
        ]),
        Column(children: [
          if (v != null) ...[
            Center(child: _aralik(v)),
            if (tamSayi(s['vardiya_sayisi']) > 1) Padding(padding: const EdgeInsets.only(top: 3), child: alt('${s['vardiya_sayisi']} vardiya')),
          ] else ...[
            Text('—', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
            Padding(padding: const EdgeInsets.only(top: 3), child: alt('planlı vardiya yok')),
          ],
        ]),
        Column(children: [
          buyuk(_saat(s['giris']), ton: _girisTon(s)),
          if (gec > 0)
            alt('$gec dk geç', renk: Kabuk.negative, w: FontWeight.w700)
          else if (s['dakiklik'] == 'zamaninda')
            alt('zamanında'),
        ]),
        Column(children: [buyuk(devam ? '—' : _saat(s['cikis'])), if (devam) alt('devam ediyor')]),
        Text(tamSayi(s['mola_dk']) > 0 ? _dk(tamSayi(s['mola_dk'])) : '—',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Kabuk.soft)),
        Text(s['giris'] != null ? _dk(tamSayi(s['calisilan_dk'])) : '—',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Kabuk.ink)),
        Center(child: _rozet(s)),
      ]),
    );
  }

  Widget _yenileDugmesi() => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          side: BorderSide(color: Kabuk.line),
          backgroundColor: Kabuk.surface,
          foregroundColor: Kabuk.ink,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        onPressed: _yukleniyor ? null : _yukle,
        icon: const Icon(Icons.refresh_rounded, size: 15),
        label: const Text('Yenile'),
      );

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final genis = g >= 1024;
    final yanBosluk = g <= 560 ? 12.0 : 18.0;
    final tabloBosluk = g <= 1100 ? 12.0 : 18.0;

    final govde = <Widget>[];
    if (genis) {
      govde.add(Padding(
        padding: EdgeInsets.fromLTRB(yanBosluk, 2, yanBosluk, 10),
        child: Row(children: [
          Text('Mesailer', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.2, color: Kabuk.ink)),
          const SizedBox(width: 10),
          _yenileDugmesi(),
          const SizedBox(width: 10),
          Expanded(child: _ozetSatiri(ust: true)),
          const SizedBox(width: 10),
          _gunGezinme(genis: true),
        ]),
      ));
    } else {
      govde.add(Padding(padding: EdgeInsets.fromLTRB(yanBosluk, 2, yanBosluk, 8), child: _gunGezinme(genis: false)));
      govde.add(Padding(padding: EdgeInsets.fromLTRB(yanBosluk, 0, yanBosluk, 10), child: _ozetSatiri(ust: false)));
    }

    if (_hata.isNotEmpty) {
      govde.add(Container(
        margin: EdgeInsets.fromLTRB(yanBosluk, 8, yanBosluk, 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Kabuk.line)),
        child: Text(_hata, style: TextStyle(fontSize: 12.5, color: Kabuk.negative)),
      ));
    }

    if (genis) {
      govde.add(Padding(
        padding: EdgeInsets.fromLTRB(tabloBosluk + 16, 2, tabloBosluk + 16, 8),
        child: _izgara([
          for (final b in ['Personel', 'Mesai', 'Giriş', 'Çıkış', 'Mola Süresi', 'Çalışılan', 'Durum'])
            Text(b.toUpperCase(),
                textAlign: b == 'Personel' ? TextAlign.left : TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .8, color: Kabuk.soft)),
        ]),
      ));
    }

    final kenar = genis ? tabloBosluk : yanBosluk;
    if (_yukleniyor) {
      govde.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Center(child: Text('Yükleniyor…', style: TextStyle(fontSize: 13, color: Kabuk.soft))),
      ));
    } else if (_satirlar.isEmpty) {
      govde.add(Padding(padding: EdgeInsets.symmetric(horizontal: kenar), child: _bos(genis: genis)));
    } else {
      for (final s in _satirlar) {
        govde.add(Padding(
          padding: EdgeInsets.fromLTRB(kenar, 0, kenar, genis ? 8 : 6),
          child: genis ? _satir(s) : _kart(s),
        ));
      }
      if (genis) {
        govde.add(Padding(
          padding: EdgeInsets.fromLTRB(yanBosluk, 4, yanBosluk, 0),
          child: Text(
            'Geç kalma $_tolerans dakika toleransla ölçülür (Cihazlar & Ayar ekranından değişir).',
            style: TextStyle(fontSize: 11.5, height: 1.6, color: Kabuk.soft),
          ),
        ));
      }
    }

    return ColoredBox(
      color: Kabuk.surface,
      child: RefreshIndicator(
        onRefresh: _yukle,
        child: ListView(
          padding: EdgeInsets.only(top: g >= 1280 ? 16 : (g >= 640 ? 14 : 8), bottom: g >= 640 ? 26 : 14),
          children: govde,
        ),
      ),
    );
  }
}
