import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/bildirim.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'bildirimler.dart';
import 'davet.dart';
import 'hedefler.dart';
import 'kabuk.dart';
import 'mesaim.dart';
import 'primler.dart';
import 'qr_okut.dart';

/// ANA SAYFA — web /panelim ile aynı: selamlama, halkalar (çalışma · mola ·
/// mola sayısı), kaydırılabilir Bugün / Bu ay kartları, vardiya ilerlemesi,
/// QR eylem kartı, son 7 gün grafiği, yaklaşan görevler, kısayol kartları.
class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  Map<String, dynamic>? _durum;
  Map<String, dynamic>? _gorev;
  Map<String, dynamic>? _bugun;
  Map<String, dynamic>? _ay;
  Map<String, dynamic>? _prim;
  List<Map<String, dynamic>> _gecmis = const [];
  bool _yukleniyor = true;
  DateTime _simdi = DateTime.now();
  DateTime _sunucuAni = DateTime.now();
  Timer? _tik;
  Timer? _yokla;
  final _sayfa = PageController();
  int _kart = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
    _tik = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _simdi = DateTime.now()));
    _yokla = Timer.periodic(const Duration(seconds: 60), (_) => _durumYukle());
  }

  @override
  void dispose() {
    _tik?.cancel();
    _yokla?.cancel();
    _sayfa.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _al(String yol) async {
    try {
      final r = await Uyg.api.get(yol);
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } on ApiHata {
      return null;
    }
  }

  Future<void> _durumYukle() async {
    final d = await _al('/api/v1/portal/state');
    if (d != null && mounted) {
      setState(() {
        _durum = d;
        _sunucuAni = DateTime.now();
      });
    }
  }

  Future<void> _yukle() async {
    final sonuc = await Future.wait([
      _al('/api/v1/portal/state'),
      _al('/api/v1/portal/tasks'),
      _al('/api/v1/portal/reports?period=day'),
      _al('/api/v1/portal/reports?period=month'),
      _al('/api/v1/portal/history'),
      Uyg.eklenti('commission') ? _al('/api/v1/portal/earnings?period=month') : Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _durum = sonuc[0];
      _sunucuAni = DateTime.now();
      _gorev = sonuc[1];
      _bugun = sonuc[2];
      _ay = sonuc[3];
      _gecmis = ((sonuc[4]?['entries'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _prim = (sonuc[5]?['scheme_name'] != null) ? sonuc[5] : null;
      _yukleniyor = false;
    });
  }

  /* ---------- hesaplar ---------- */
  bool get _calisiyor => _durum?['status'] == 'working';
  bool get _molada => _durum?['on_break'] == true;
  String get _kip => !_calisiyor ? 'off' : _molada ? 'break' : 'work';
  double get _gecenDk => math.max(0, _simdi.difference(_sunucuAni).inSeconds / 60);

  int get _calisilan {
    final e = _durum?['entry'] as Map?;
    if (e == null) return 0;
    return ((e['worked_min'] as num?) ?? 0).toInt() + (_molada ? 0 : _gecenDk.round());
  }

  int get _molaKullanilan => ((_durum?['break_used_min'] as num?) ?? 0).toInt() + (_molada ? _gecenDk.round() : 0);
  int get _molaHak => ((_durum?['break_allowance_min'] as num?) ?? 0).toInt();
  int get _molaSayi => ((_durum?['break_count'] as num?) ?? 0).toInt();

  DateTime? _t(Object? s) => s == null ? null : DateTime.tryParse(s.toString())?.toLocal();
  Map? get _vardiya => _durum?['today_shift'] as Map?;
  int get _planDk {
    final v = _vardiya;
    if (v == null) return 480;
    return math.max(1, _t(v['ends_at'])!.difference(_t(v['starts_at'])!).inMinutes);
  }

  String _saat(DateTime? d) => d == null ? '--:--' : DateFormat('HH:mm').format(d);

  String get _selam {
    final h = _simdi.hour;
    if (h < 6) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final ust = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion(
      value: durumCubugu,
      child: Scaffold(
        backgroundColor: r.zemin,
        body: RefreshIndicator(
          onRefresh: _yukle,
          color: Marka.mor,
          edgeOffset: ust,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // Üst alan + içerik yaprağı AYNI parçada: yaprak üst alanın
              // üstüne binsin (yuvarlak köşeler görünsün).
              SliverToBoxAdapter(
                child: Column(children: [
                  _hero(ust),
                  Transform.translate(
                    offset: const Offset(0, -26),
                    child: Container(
                      decoration: BoxDecoration(color: r.zemin, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                      padding: EdgeInsets.fromLTRB(16, 22, 16, 96 + MediaQuery.paddingOf(context).bottom),
                      child: _govde(),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ───────────── Üst alan ───────────── */

  Widget _hero(double ust) {
    final kipRenk = switch (_kip) { 'work' => const Color(0xFF6EE7B7), 'break' => const Color(0xFFC4B5FD), _ => const Color(0xB3BAE6FD) };
    final kipYazi = switch (_kip) {
      'work' => 'Mesaidesin',
      'break' => _durum?['break_kind'] == 'toilet' ? 'Kısa moladasın' : 'Moladasın',
      _ => 'Mesai dışı',
    };
    final rol = _bugun?['role_label']?.toString() ?? Uyg.hesap.value?['pozisyon']?.toString();
    return Aurora(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, ust + 10, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Belir(
            child: Cam(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(children: [
                _Avatar(kip: _kip),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$_selam${Uyg.ilkAd.isEmpty ? '' : ', ${Uyg.ilkAd}'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(17, agirlik: FontWeight.w700, renk: Colors.white)),
                    const SizedBox(height: 2),
                    Row(children: [
                      _CanliNokta(renk: kipRenk, canli: _kip != 'off'),
                      const SizedBox(width: 6),
                      Text(kipYazi, style: TextStyle(color: kipRenk, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      if (rol != null)
                        Flexible(
                          child: Text(' · $rol', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .45), fontSize: 12.5)),
                        ),
                    ]),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_saat(_simdi), style: gosterim(18, agirlik: FontWeight.w700, renk: Colors.white)),
                  Text(DateFormat('EEE', 'tr_TR').format(_simdi).toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: .45), fontSize: 10, letterSpacing: 1)),
                ]),
                const SizedBox(width: 10),
                _Zil(onTap: () => git(context, const BildirimlerEkrani())),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('d MMMM EEEE', 'tr_TR').format(_simdi).toUpperCase(),
                    style: TextStyle(color: Marka.gok.withValues(alpha: .6), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .3), end: Offset.zero).animate(a), child: c)),
                  child: Text(['Mesai bilgileri', 'Bugün', 'Bu ay'][_kart], key: ValueKey(_kart), style: gosterim(23, renk: Colors.white)),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withValues(alpha: .12))),
              child: Row(children: [
                Text(_saat(_t((_durum?['entry'] as Map?)?['clock_in_at']) ?? _t(_vardiya?['starts_at'])), style: gosterim(15, agirlik: FontWeight.w600, renk: Colors.white)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white.withValues(alpha: .5))),
                Text(_saat(_t(_vardiya?['ends_at'])), style: gosterim(15, agirlik: FontWeight.w600, renk: Colors.white)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: PageView(
              controller: _sayfa,
              onPageChanged: (i) {
                titret();
                setState(() => _kart = i);
              },
              children: [_halkaKarti(), _bugunKarti(), _ayKarti()],
            ),
          ),
          if (_vardiya != null) _vardiyaCubugu(),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++)
              GestureDetector(
                onTap: () => _sayfa.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  width: _kart == i ? 28 : 7,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: _kart == i ? null : Colors.white.withValues(alpha: .3),
                    gradient: _kart == i ? const LinearGradient(colors: [Marka.gok, Color(0xFF8B7FF0)]) : null,
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _halkaKarti() {
    final degerler = [
      _calisilan / _planDk,
      _molaHak > 0 ? _molaKullanilan / _molaHak : (_molaKullanilan > 0 ? 1.0 : 0.0),
      _molaSayi / 3,
    ];
    TextStyle b(Color c) => gosterim(27, renk: c);
    Widget satir(String etiket, Widget deger, List<Color> g) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          deger,
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: g))),
            const SizedBox(width: 6),
            Text(etiket, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12.5)),
          ]),
        ]);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          satir('Çalışma süresi', Sayac(deger: _calisilan, yaz: (v) => dakikaYaz(v), stil: b(const Color(0xFF7DD3FC))), const [Color(0xFF7DD3FC), Marka.mavi]),
          satir(
            'Mola',
            Sayac(
              deger: _molaKullanilan,
              yaz: (v) => '${v.round()} dk${_molaHak > 0 ? ' / ${dakikaYaz(_molaHak)}' : ''}',
              stil: b(const Color(0xFFC4B5FD)),
            ),
            const [Color(0xFFC4B5FD), Color(0xFF7C3AED)],
          ),
          satir('Mola sayısı', Sayac(deger: _molaSayi, yaz: (v) => '${v.round()} adet', stil: b(const Color(0xFF6EE7B7))), const [Color(0xFF6EE7B7), Color(0xFF0D9488)]),
        ]),
      ),
      Halkalar(degerler: degerler, kip: _kip, boyut: 168),
    ]);
  }

  Widget _cam(String etiket, String deger, IconData ikon, List<Color> g) => Cam(
        padding: const EdgeInsets.all(12),
        radius: 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(gradient: LinearGradient(colors: g), borderRadius: BorderRadius.circular(11)),
            child: Icon(ikon, color: Colors.white, size: 17),
          ),
          const Spacer(),
          FittedBox(child: Text(deger, style: gosterim(22, renk: Colors.white))),
          Text(etiket, style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11.5)),
        ]),
      );

  Widget _bugunKarti() {
    final ops = _bugun?['ops'] as Map?;
    String n(Object? v) => v == null ? '—' : NumberFormat.decimalPattern('tr_TR').format(v);
    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(child: _cam('Sipariş', n(ops?['taken_count']), Icons.receipt_long_rounded, const [Color(0xFF7DD3FC), Marka.mavi])),
          const SizedBox(width: 10),
          Expanded(child: _cam('Servis', n(ops?['served_count']), Icons.restaurant_rounded, const [Color(0xFF6EE7B7), Color(0xFF0D9488)])),
          const SizedBox(width: 10),
          Expanded(
            child: _cam('Ort. teslim', ops?['avg_delivery_min'] == null ? '—' : dakikaYaz(ops!['avg_delivery_min'] as num), Icons.timer_rounded,
                const [Color(0xFFC4B5FD), Color(0xFF7C3AED)]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Cam(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 20,
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFA5B4FC), Marka.mor]), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.soup_kitchen_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Hazırladığın ürün', style: TextStyle(color: Colors.white.withValues(alpha: .7)))),
          Text(n(ops?['prepared_count']), style: gosterim(20, renk: Colors.white)),
        ]),
      ),
    ]);
  }

  Widget _ayKarti() {
    final w = _ay?['worked'] as Map?;
    final ops = _ay?['ops'] as Map?;
    String n(Object? v) => v == null ? '—' : NumberFormat.decimalPattern('tr_TR').format(v);
    Widget k(String e, String d, Color c) => Cam(
          padding: const EdgeInsets.all(13),
          radius: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(e, style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(child: Text(d, style: gosterim(23, renk: c))),
          ]),
        );
    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(child: k('Toplam çalışma', w == null ? '—' : dakikaYaz(w['total_min'] as num), const Color(0xFF7DD3FC))),
          const SizedBox(width: 10),
          Expanded(child: k('Çalışılan gün', w == null ? '—' : '${w['active_days']}', const Color(0xFF6EE7B7))),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: Row(children: [
          Expanded(child: k('Servis', n(ops?['served_count']), const Color(0xFFC4B5FD))),
          const SizedBox(width: 10),
          Expanded(child: k(_prim != null ? 'Prim' : 'Sipariş', _prim != null ? paraYaz(_prim!['commission_minor'] as num) : n(ops?['taken_count']), const Color(0xFFC7D2FE))),
        ]),
      ),
    ]);
  }

  Widget _vardiyaCubugu() {
    final a = _t(_vardiya!['starts_at'])!;
    final b = _t(_vardiya!['ends_at'])!;
    final p = (_simdi.difference(a).inSeconds / math.max(1, b.difference(a).inSeconds)).clamp(0.0, 1.0);
    final kalan = b.difference(_simdi).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 7,
            color: Colors.white.withValues(alpha: .1),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Marka.gok, Marka.mavi, Marka.morAcik]))),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(children: [
          Text(_saat(a), style: gosterim(11, agirlik: FontWeight.w600, renk: Colors.white54)),
          Expanded(
            child: Text(
              kalan > 0 ? (p > 0 ? 'Vardiya bitişine ${dakikaYaz(kalan)}' : 'Vardiya başlamadı') : 'Vardiya tamamlandı',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          Text(_saat(b), style: gosterim(11, agirlik: FontWeight.w600, renk: Colors.white54)),
        ]),
      ]),
    );
  }

  /* ───────────── Gövde ───────────── */

  Widget _govde() {
    final r = context.pa;
    final gorevler = ((_gorev?['tasks'] as List?) ?? const []).whereType<Map>().where((t) => t['status'] != 'done').take(3).toList();
    final sayac = _gorev?['counts'] as Map?;
    final acik = ((sayac?['open'] as num?) ?? 0) + ((sayac?['in_progress'] as num?) ?? 0);

    final parcalar = <Widget>[
      // Hızlı kutular
      Row(children: [
        Expanded(
          child: _HizliKutu(
            ikon: _kip == 'break' ? Icons.coffee_rounded : Icons.schedule_rounded,
            yazi: _kip == 'off' ? 'Mesai yok' : _kip == 'break' ? 'Moladasın' : 'Mesaim',
            grad: _kip != 'off',
            onTap: () => git(context, const MesaimEkrani()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _HizliKutu(ikon: Icons.calendar_month_rounded, yazi: 'Vardiyam', zemin: const Color(0xFFE0F2FE), renk: const Color(0xFF0284C7), onTap: () => Kabuk.sekme.value = 2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _HizliKutu(ikon: Icons.trending_up_rounded, yazi: 'Hedeflerim', zemin: const Color(0xFFF1EAFE), renk: const Color(0xFF7C3AED), onTap: () => git(context, const HedeflerEkrani())),
        ),
      ]),
      const SizedBox(height: 14),
      _QrKarti(kip: _kip, onTap: () => git(context, const QrOkutEkrani()).then((_) => _yukle())),
      const SizedBox(height: 14),
      _HaftaKarti(gecmis: _gecmis, bugunCanli: _calisiyor ? _calisilan : null),
      const SizedBox(height: 14),
      // Yaklaşan görevler
      PaKart(
        padding: EdgeInsets.zero,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 6),
            child: Row(children: [
              const PaIkon(Icons.assignment_turned_in_rounded, boyut: 40, grad: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Yaklaşan görevlerim', style: gosterim(16.5, renk: r.metin)),
                  Text(acik > 0 ? '$acik açık görev' : 'Hepsi tamam', style: TextStyle(color: r.soluk, fontSize: 12)),
                ]),
              ),
              YumusakDugme(yazi: 'Tümü ›', onTap: () => Kabuk.sekme.value = 1),
            ]),
          ),
          if (_yukleniyor)
            const Padding(padding: EdgeInsets.all(14), child: Column(children: [Iskelet(yukseklik: 46), SizedBox(height: 8), Iskelet(yukseklik: 46)]))
          else if (gorevler.isEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Container(width: 38, height: 38, decoration: const BoxDecoration(color: Marka.zumrut, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(child: Text('Şu an görevin yok. Yeni görev gelince bildirim alırsın.', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13))),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Column(children: [
                for (final t in gorevler)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Kabuk.sekme.value = 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 5,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            color: (t['priority'] == 'high' || t['priority'] == 'urgent') ? Marka.gul : null,
                            gradient: (t['priority'] == 'high' || t['priority'] == 'urgent') ? null : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Marka.morAcik, Marka.mavi]),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: r.metin)),
                            Text(
                              [
                                switch (t['priority']) { 'urgent' => 'Acil', 'high' => 'Yüksek', 'low' => 'Düşük', _ => 'Normal' },
                                if (t['due_at'] != null) DateFormat('d MMM HH:mm', 'tr_TR').format(_t(t['due_at'])!),
                              ].join(' · '),
                              style: TextStyle(color: r.soluk, fontSize: 12),
                            ),
                          ]),
                        ),
                        if (t['status'] == 'in_progress')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(20)),
                            child: const Text('Sürüyor', style: TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.w700)),
                          )
                        else
                          Icon(Icons.chevron_right_rounded, color: r.silik),
                      ]),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: [
          _AltKart(ikon: Icons.account_balance_wallet_rounded, baslik: 'Primlerim', alt: _prim != null ? paraYaz(_prim!['commission_minor'] as num) : 'Kazanç ve hakedişler', zemin: const Color(0xFFFEF3C7), renk: const Color(0xFFB45309), onTap: () => git(context, const PrimlerEkrani())),
          _AltKart(ikon: Icons.trending_up_rounded, baslik: 'Hedeflerim', alt: 'Bu ayki ilerlemen', zemin: const Color(0xFFF1EAFE), renk: const Color(0xFF7C3AED), onTap: () => git(context, const HedeflerEkrani())),
          _AltKart(ikon: Icons.auto_awesome_rounded, baslik: 'Davet et, kazan', alt: 'İşletme öner, ödül al', grad: true, onTap: () => git(context, const DavetEkrani())),
          _AltKart(ikon: Icons.history_rounded, baslik: 'Mesai geçmişi', alt: 'Giriş, çıkış, molalar', zemin: const Color(0xFFD1FAE5), renk: const Color(0xFF047857), onTap: () => git(context, const MesaimEkrani())),
        ],
      ),
    ];
    return Column(children: [for (var i = 0; i < parcalar.length; i++) Belir(gecikme: math.min(i, 8) * 40, child: parcalar[i])]);
  }
}

/* ───────────────────────── Halkalar ───────────────────────── */

class Halkalar extends StatelessWidget {
  const Halkalar({super.key, required this.degerler, required this.kip, this.boyut = 170});
  final List<double> degerler;
  final String kip;
  final double boyut;

  static const _gradlar = [
    [Color(0xFF7DD3FC), Marka.mavi],
    [Color(0xFFC4B5FD), Color(0xFF7C3AED)],
    [Color(0xFF6EE7B7), Color(0xFF0D9488)],
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: boyut,
      height: boyut,
      child: Stack(alignment: Alignment.center, children: [
        for (var i = 0; i < degerler.length; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: degerler[i].clamp(0.0, 1.0)),
            duration: Duration(milliseconds: 1500 + i * 140),
            curve: const Cubic(.22, 1, .36, 1),
            builder: (_, v, _) => CustomPaint(size: Size.square(boyut), painter: _HalkaCizer(i, v, _gradlar[i])),
          ),
        _HalkaMerkez(kip: kip),
      ]),
    );
  }
}

class _HalkaCizer extends CustomPainter {
  _HalkaCizer(this.sira, this.oran, this.renkler);
  final int sira;
  final double oran;
  final List<Color> renkler;

  @override
  void paint(Canvas c, Size s) {
    const kalinlik = 14.0;
    final r = s.width / 2 - kalinlik / 2 - sira * (kalinlik + 5);
    final m = s.center(Offset.zero);
    final rect = Rect.fromCircle(center: m, radius: r);
    c.drawCircle(m, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik
      ..color = Colors.white.withValues(alpha: .08));
    if (oran <= 0.002) return;
    final yay = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(startAngle: 0, endAngle: math.pi * 2, colors: renkler, transform: const GradientRotation(-math.pi / 2)).createShader(rect);
    c.drawArc(rect, -math.pi / 2, math.pi * 2 * oran, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik + 6
      ..strokeCap = StrokeCap.round
      ..color = renkler.last.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawArc(rect, -math.pi / 2, math.pi * 2 * oran, false, yay);
    final a = -math.pi / 2 + math.pi * 2 * oran;
    c.drawCircle(m + Offset(math.cos(a) * r, math.sin(a) * r), kalinlik / 2 - 3.5, Paint()..color = Colors.white.withValues(alpha: .9));
  }

  @override
  bool shouldRepaint(_HalkaCizer o) => o.oran != oran;
}

class _HalkaMerkez extends StatefulWidget {
  const _HalkaMerkez({required this.kip});
  final String kip;
  @override
  State<_HalkaMerkez> createState() => _HalkaMerkezState();
}

class _HalkaMerkezState extends State<_HalkaMerkez> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ikon = widget.kip == 'break' ? Icons.coffee_rounded : Icons.hourglass_bottom_rounded;
    final renk = widget.kip == 'work' ? const Color(0xFF7DD3FC) : widget.kip == 'break' ? const Color(0xFFC4B5FD) : Colors.white60;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.scale(scale: widget.kip == 'off' ? 1 : 1 + .06 * _c.value, child: child),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: .15))),
        child: Icon(ikon, color: renk, size: 22),
      ),
    );
  }
}

/* ───────────────────────── Parçalar ───────────────────────── */

class _Avatar extends StatelessWidget {
  const _Avatar({required this.kip});
  final String kip;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 50,
        height: 50,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(17), boxShadow: const [BoxShadow(color: Color(0xAA5443D2), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)]),
            child: Text(Uyg.basHarfler, style: gosterim(18, renk: Colors.white)),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kip == 'work' ? const Color(0xFF34D399) : kip == 'break' ? Marka.lavanta : const Color(0xFF94A3B8),
                border: Border.all(color: Marka.lacivert1, width: 3),
              ),
            ),
          ),
        ]),
      );
}

class _CanliNokta extends StatefulWidget {
  const _CanliNokta({required this.renk, required this.canli});
  final Color renk;
  final bool canli;
  @override
  State<_CanliNokta> createState() => _CanliNoktaState();
}

class _CanliNoktaState extends State<_CanliNokta> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 9,
        height: 9,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          if (widget.canli)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Transform.scale(
                scale: 1 + 1.4 * _c.value,
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: widget.renk.withValues(alpha: .6 * (1 - _c.value)))),
              ),
            ),
          Container(decoration: BoxDecoration(shape: BoxShape.circle, color: widget.renk)),
        ]),
      );
}

class _Zil extends StatelessWidget {
  const _Zil({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Basilir(
        onTap: onTap,
        child: ValueListenableBuilder<int>(
          valueListenable: BildirimMerkezi.okunmamis,
          builder: (_, n, _) => Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withValues(alpha: .1))),
              child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 22),
            ),
            if (n > 0)
              Positioned(
                right: -4,
                top: -4,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(n),
                  tween: Tween(begin: .3, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFF43F5E), borderRadius: BorderRadius.circular(10), border: Border.all(color: Marka.lacivert1, width: 2)),
                    child: Text(n > 9 ? '9+' : '$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
          ]),
        ),
      );
}

class _HizliKutu extends StatelessWidget {
  const _HizliKutu({required this.ikon, required this.yazi, required this.onTap, this.zemin, this.renk, this.grad = false});
  final IconData ikon;
  final String yazi;
  final VoidCallback onTap;
  final Color? zemin;
  final Color? renk;
  final bool grad;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaKart(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      child: Column(children: [
        PaIkon(ikon, boyut: 46, grad: grad, zemin: r.koyu ? null : zemin, renk: r.koyu ? null : renk),
        const SizedBox(height: 8),
        Text(yazi, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: r.metin)),
      ]),
    );
  }
}

class _QrKarti extends StatelessWidget {
  const _QrKarti({required this.kip, required this.onTap});
  final String kip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (baslik, alt) = switch (kip) {
      'off' => ('Mesaiye başla', 'Girişteki mesai QR\'ını okut, mesain başlasın.'),
      'break' => ('Moladasın', 'Moladan dönünce QR okut.'),
      _ => ('İyi çalışmalar!', 'Molaya çıkarken ve çıkışta QR okut.'),
    };
    return Basilir(
      onTap: onTap,
      olcek: .97,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: Marka.kart,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x991C1863), blurRadius: 36, offset: Offset(0, 18), spreadRadius: -20)],
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(right: -18, top: -22, child: Icon(Icons.qr_code_2_rounded, size: 120, color: Colors.white.withValues(alpha: .1))),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(baslik, style: gosterim(18, renk: Colors.white)),
                const SizedBox(height: 3),
                Text(alt, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Row(children: [
                Icon(Icons.qr_code_scanner_rounded, color: Marka.lacivert1, size: 20),
                SizedBox(width: 6),
                Text('QR okut', style: TextStyle(color: Marka.lacivert1, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _HaftaKarti extends StatelessWidget {
  const _HaftaKarti({required this.gecmis, this.bugunCanli});
  final List<Map<String, dynamic>> gecmis;
  final int? bugunCanli;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final top = <String, int>{};
    for (final h in gecmis) {
      final k = h['date'].toString();
      top[k] = (top[k] ?? 0) + ((h['worked_min'] as num?) ?? 0).toInt();
    }
    final gunler = <({String etiket, int dk, bool bugun})>[];
    final simdi = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final d = simdi.subtract(Duration(days: i));
      final k = DateFormat('yyyy-MM-dd').format(d);
      var dk = top[k] ?? 0;
      if (i == 0 && bugunCanli != null) dk = math.max(dk, bugunCanli!);
      gunler.add((etiket: DateFormat('EEE', 'tr_TR').format(d), dk: dk, bugun: i == 0));
    }
    final enCok = math.max(60, gunler.map((g) => g.dk).reduce(math.max));
    final toplam = gunler.fold<int>(0, (a, g) => a + g.dk);

    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SON 7 GÜN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: r.silik)),
              Sayac(deger: toplam, yaz: (v) => dakikaYaz(v), stil: gosterim(25, renk: r.metin)),
            ]),
          ),
          TextButton(onPressed: () => git(context, const MesaimEkrani()), child: Text('Geçmiş', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < gunler.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (gunler[i].dk > 0)
                      Text('${(gunler[i].dk / 60).toStringAsFixed(1)}s', style: TextStyle(fontSize: 9.5, color: r.soluk, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: math.max(.06, gunler[i].dk / enCok)),
                      duration: Duration(milliseconds: 800 + i * 60),
                      curve: const Cubic(.22, 1, .36, 1),
                      builder: (_, v, _) => Container(
                        height: 80 * v,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          color: gunler[i].bugun ? null : (gunler[i].dk > 0 ? r.birincilYumusak : r.ic),
                          gradient: gunler[i].bugun ? const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Marka.mor, Marka.gok]) : null,
                          boxShadow: gunler[i].bugun ? const [BoxShadow(color: Color(0x995443D2), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -4)] : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(gunler[i].etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: gunler[i].bugun ? r.birincil : r.silik)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _AltKart extends StatelessWidget {
  const _AltKart({required this.ikon, required this.baslik, required this.alt, required this.onTap, this.zemin, this.renk, this.grad = false});
  final IconData ikon;
  final String baslik;
  final String alt;
  final VoidCallback onTap;
  final Color? zemin;
  final Color? renk;
  final bool grad;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaKart(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PaIkon(ikon, boyut: 40, grad: grad, zemin: r.koyu ? null : zemin, renk: r.koyu ? null : renk),
        const Spacer(),
        Text(baslik, style: gosterim(15.5, renk: r.metin)),
        Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk)),
      ]),
    );
  }
}
