import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/gorev_foto.dart';
import '../ortak/ortak.dart';

/// GÖREVLERİM (sekme) — web Portal/Tasks.vue'nun native karşılığı.
/// İlerleme halkası + sayaçlar, Aktif/Tamamlanan kayan sekme, öncelik renkli
/// şeritli kartlar, tek dokunuşla Başla → Tamamladım.
class GorevlerEkrani extends StatefulWidget {
  const GorevlerEkrani({super.key});
  @override
  State<GorevlerEkrani> createState() => _GorevlerEkraniState();
}

class _GorevlerEkraniState extends State<GorevlerEkrani> {
  bool _yukleniyor = true;
  List<Map<String, dynamic>> _gorevler = [];
  Map<String, int> _sayac = {'open': 0, 'in_progress': 0, 'done': 0};
  int _sekme = 0; // 0 aktif, 1 tamamlanan
  int _mesgul = 0;
  int _yeniBiten = 0;
  int _fotoYukleniyor = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/tasks') as Map;
      final l = ((r['tasks'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final c = (r['counts'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        _gorevler = l;
        _sayac = {
          'open': (c['open'] as num?)?.toInt() ?? 0,
          'in_progress': (c['in_progress'] as num?)?.toInt() ?? 0,
          'done': (c['done'] as num?)?.toInt() ?? 0,
        };
      });
    } on ApiHata catch (e) {
      bildir('Görevler yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ilerlet(Map<String, dynamic> g) async {
    if (_mesgul != 0) return;
    final id = (g['id'] as num).toInt();
    final hedef = g['status'] == 'open' ? 'in_progress' : 'done';
    setState(() => _mesgul = id);
    try {
      final r = await Uyg.api.post('/api/v1/portal/tasks/$id/status', {'status': hedef}) as Map;
      final yeni = r['task'] is Map ? Map<String, dynamic>.from(r['task'] as Map) : {...g, 'status': hedef};
      final i = _gorevler.indexWhere((t) => t['id'] == g['id']);
      setState(() {
        if (i >= 0) _gorevler[i] = yeni;
        final s = <String, int>{'open': 0, 'in_progress': 0, 'done': 0};
        for (final t in _gorevler) {
          s[t['status'].toString()] = (s[t['status'].toString()] ?? 0) + 1;
        }
        _sayac = s;
      });
      if (hedef == 'done') {
        titret(1);
        setState(() => _yeniBiten = id);
        bildir('Görev tamamlandı', mesaj: g['title']?.toString());
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) setState(() => _yeniBiten = 0);
      } else {
        bildir('Görev başlatıldı', mesaj: g['title']?.toString(), tur: BildirimTur.bilgi);
      }
    } on ApiHata catch (e) {
      bildir('İşlem tamamlanamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = 0);
    }
  }

  /// Sürüyor → Tamamladım: önce isteğe bağlı fotoğraf (kanıt), sonra durum.
  Future<void> _tamamla(Map<String, dynamic> g) async {
    if (_mesgul != 0 || _fotoYukleniyor != 0) return;
    final sec = await gorevFotoSec(context, tamamla: true, mevcut: gorevFotolari(g).length);
    if (sec == null || !mounted) return;
    if (sec != 'yok') {
      final tamam = await _fotoGonder(g, sec);
      if (!tamam || !mounted) return;
    }
    final guncel = _gorevler.firstWhere((t) => t['id'] == g['id'], orElse: () => g);
    await _ilerlet(guncel);
  }

  Future<void> _fotoEkle(Map<String, dynamic> g) async {
    if (_fotoYukleniyor != 0) return;
    if (gorevFotolari(g).length >= gorevFotoSiniri) {
      bildir('Fotoğraf sınırı doldu', mesaj: 'Bir göreve en fazla $gorevFotoSiniri fotoğraf eklenebilir.', tur: BildirimTur.uyari);
      return;
    }
    final sec = await gorevFotoSec(context, mevcut: gorevFotolari(g).length);
    if (sec == null || sec == 'yok' || !mounted) return;
    if (await _fotoGonder(g, sec)) bildir('Fotoğraf eklendi', mesaj: g['title']?.toString());
  }

  Future<bool> _fotoGonder(Map<String, dynamic> g, String yol) async {
    final id = (g['id'] as num).toInt();
    setState(() => _fotoYukleniyor = id);
    final l = await gorevFotoYukle(id, yol);
    if (!mounted) return l != null;
    setState(() {
      _fotoYukleniyor = 0;
      if (l != null) {
        final i = _gorevler.indexWhere((t) => t['id'] == g['id']);
        if (i >= 0) _gorevler[i] = {..._gorevler[i], 'fotolar': l};
      }
    });
    return l != null;
  }

  List<Map<String, dynamic>> get _gosterilen {
    const pr = {'urgent': 0, 'high': 1, 'normal': 2, 'low': 3};
    final l = _gorevler.where((t) => _sekme == 0 ? t['status'] != 'done' : t['status'] == 'done').toList();
    l.sort((a, b) {
      final p = (pr[a['priority']] ?? 2).compareTo(pr[b['priority']] ?? 2);
      if (p != 0) return p;
      return (a['due_at']?.toString() ?? '9').compareTo(b['due_at']?.toString() ?? '9');
    });
    return l;
  }

  String get _altBaslik {
    if (_yukleniyor) return 'Görevlerin yükleniyor…';
    if (_gorevler.isEmpty) return 'Atanmış görev yok';
    final acik = (_sayac['open'] ?? 0) + (_sayac['in_progress'] ?? 0);
    return acik > 0 ? '$acik açık görev' : 'Tüm görevler tamam 🎉';
  }

  @override
  Widget build(BuildContext context) {
    final liste = _gosterilen;
    return PaSayfa(
      baslik: 'Görevlerim',
      altBaslik: _altBaslik,
      geri: false,
      yenile: _yukle,
      govde: Kaydir(children: [
        _Ozet(sayac: _sayac),
        const SizedBox(height: 14),
        _Sekmeler(
          secili: _sekme,
          aktif: (_sayac['open'] ?? 0) + (_sayac['in_progress'] ?? 0),
          biten: _sayac['done'] ?? 0,
          onSec: (i) => setState(() => _sekme = i),
        ),
        const SizedBox(height: 14),
        if (_yukleniyor)
          Column(children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PaKart(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Iskelet(yukseklik: 16, genislik: 200),
                    SizedBox(height: 10),
                    Iskelet(yukseklik: 12, genislik: 120),
                  ]),
                ),
              ),
          ])
        else if (liste.isEmpty)
          BosDurum(
            ikon: Icons.assignment_turned_in_rounded,
            baslik: _sekme == 0 ? 'Şu an görevin yok' : 'Henüz tamamlanan yok',
            aciklama: _sekme == 0 ? 'Yöneticin görev atadığında burada belirir ve bildirim alırsın.' : 'Bitirdiğin görevler burada listelenir.',
          )
        else
          Column(children: [
            for (var i = 0; i < liste.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Belir(
                  key: ValueKey('g${liste[i]['id']}${liste[i]['status']}'),
                  gecikme: math.min(i, 6) * 50,
                  child: GorevKarti(
                    g: liste[i],
                    mesgul: _mesgul == (liste[i]['id'] as num).toInt(),
                    yeniBitti: _yeniBiten == (liste[i]['id'] as num).toInt(),
                    fotoYukleniyor: _fotoYukleniyor == (liste[i]['id'] as num).toInt(),
                    onIlerlet: () => liste[i]['status'] == 'open' ? _ilerlet(liste[i]) : _tamamla(liste[i]),
                    onFotoEkle: () => _fotoEkle(liste[i]),
                  ),
                ),
              ),
          ]),
      ]),
    );
  }
}

/* ───────────── Özet: halka + sayaçlar ───────────── */

class _Ozet extends StatelessWidget {
  const _Ozet({required this.sayac});
  final Map<String, int> sayac;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final toplam = (sayac['open'] ?? 0) + (sayac['in_progress'] ?? 0) + (sayac['done'] ?? 0);
    final oran = toplam == 0 ? 0.0 : (sayac['done'] ?? 0) / toplam;
    Widget kutu(int deger, String etiket, Color zemin, Color renk) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Sayac(deger: deger, yaz: (v) => v.round().toString(), stil: gosterim(20, renk: renk)),
              Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
            ]),
          ),
        );
    return PaKart(
      child: Row(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: oran),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _HalkaCizer(v, r.ic),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('%${(v * 100).round()}', style: gosterim(18, renk: r.metin)),
                  Text('TAMAM', style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w700, color: r.silik)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        kutu(sayac['open'] ?? 0, 'Bekleyen', r.ic, r.soluk),
        const SizedBox(width: 8),
        kutu(sayac['in_progress'] ?? 0, 'Sürüyor', r.birincilYumusak, r.birincil),
        const SizedBox(width: 8),
        kutu(sayac['done'] ?? 0, 'Bitti', Marka.zumrut.withValues(alpha: .14), r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
      ]),
    );
  }
}

class _HalkaCizer extends CustomPainter {
  _HalkaCizer(this.oran, this.zemin);
  final double oran;
  final Color zemin;
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromLTWH(5, 5, s.width - 10, s.height - 10);
    c.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = zemin);
    if (oran <= 0) return;
    c.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * oran,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [Marka.morAcik, Marka.gok],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HalkaCizer o) => o.oran != oran || o.zemin != zemin;
}

/* ───────────── Kayan sekme ───────────── */

class _Sekmeler extends StatelessWidget {
  const _Sekmeler({required this.secili, required this.aktif, required this.biten, required this.onSec});
  final int secili;
  final int aktif;
  final int biten;
  final ValueChanged<int> onSec;

  @override
  Widget build(BuildContext context) =>
      PaSegment(secili: secili, ogeler: const ['Aktif', 'Tamamlanan'], sayilar: [aktif, biten], onSec: onSec);
}

/* ───────────── Görev kartı ───────────── */

/// Görev kartı. `onIlerlet` null → salt okunur (yönetici listesi): durum
/// düğmeleri gizlenir, `atananGoster` ile atanan kişi yazılır.
class GorevKarti extends StatelessWidget {
  const GorevKarti({
    super.key,
    required this.g,
    this.mesgul = false,
    this.yeniBitti = false,
    this.fotoYukleniyor = false,
    this.onIlerlet,
    this.onFotoEkle,
    this.atananGoster = false,
  });
  final Map<String, dynamic> g;
  final bool mesgul;
  final bool yeniBitti;
  final bool fotoYukleniyor;
  final VoidCallback? onIlerlet;
  final VoidCallback? onFotoEkle;
  final bool atananGoster;

  static final _tarih = DateFormat('d MMM HH:mm', 'tr_TR');

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final durum = g['status']?.toString() ?? 'open';
    final oncelik = g['priority']?.toString() ?? 'normal';
    final bitti = durum == 'done';
    final acik = g['herkese_acik'] == true;
    final son = DateTime.tryParse(g['due_at']?.toString() ?? '')?.toLocal();
    final gecikti = !bitti && son != null && son.isBefore(DateTime.now());
    final aciklama = g['description']?.toString();
    final olusturan = g['created_by'] is Map ? (g['created_by'] as Map)['name']?.toString() : null;
    final atanan = g['assigned_to'] is Map ? (g['assigned_to'] as Map)['name']?.toString() : null;
    final fotolar = gorevFotolari(g);
    final salt = onIlerlet == null;

    final (pEt, pZemin, pRenk) = switch (oncelik) {
      'urgent' => ('Acil', Marka.gul.withValues(alpha: .14), Marka.gul),
      'high' => ('Yüksek', Marka.gul.withValues(alpha: .14), Marka.gul),
      'low' => ('Düşük', r.ic, r.soluk),
      _ => ('Normal', r.birincilYumusak, r.birincil),
    };
    final serit = switch (oncelik) {
      'urgent' || 'high' => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFB7185), Color(0xFFE11D48)]),
      'low' => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFCBD5E1), Color(0xFF94A3B8)]),
      _ => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Marka.morAcik, Marka.mavi]),
    };

    Widget cip(IconData? ikon, String yazi, Color zemin, Color renk) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (ikon != null) ...[Icon(ikon, size: 12, color: renk), const SizedBox(width: 4)],
            Text(yazi, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: renk)),
          ]),
        );

    return PaKart(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, decoration: BoxDecoration(gradient: serit)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Durum düğmesi (daire)
                  GestureDetector(
                    onTap: bitti || mesgul || salt ? null : onIlerlet,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bitti ? Marka.zumrut : Colors.transparent,
                        border: Border.all(
                          width: 2,
                          color: bitti ? Colors.transparent : (durum == 'in_progress' ? r.birincil : r.kenar),
                        ),
                      ),
                      child: Center(
                        child: mesgul
                            ? Yukleyici(boyut: 18, renk: r.birincil)
                            : bitti
                                ? TweenAnimationBuilder<double>(
                                    key: ValueKey(yeniBitti),
                                    tween: Tween(begin: yeniBitti ? 0 : 1, end: 1),
                                    duration: const Duration(milliseconds: 600),
                                    curve: Curves.elasticOut,
                                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                                  )
                                : durum == 'in_progress'
                                    ? Container(width: 12, height: 12, decoration: BoxDecoration(color: r.birincil, shape: BoxShape.circle))
                                    : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text(
                            g['title']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              height: 1.3,
                              color: bitti ? r.soluk : r.metin,
                              decoration: bitti ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        cip(null, pEt, pZemin, pRenk),
                      ]),
                      if (aciklama != null && aciklama.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(aciklama, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: r.soluk, height: 1.35)),
                        ),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (son != null)
                          cip(Icons.schedule_rounded, '${_tarih.format(son)}${gecikti ? ' · gecikti' : ''}',
                              gecikti ? Marka.gul.withValues(alpha: .14) : r.ic, gecikti ? Marka.gul : r.soluk),
                        if (acik) cip(Icons.groups_rounded, 'Herkese açık', Marka.gok.withValues(alpha: .16), r.koyu ? Marka.gok : const Color(0xFF0284C7)),
                        if (atananGoster && !acik && atanan != null)
                          cip(Icons.person_rounded, atanan, r.ic, r.soluk)
                        else if (!atananGoster && olusturan != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.person_rounded, size: 13, color: r.silik),
                            const SizedBox(width: 3),
                            Text(olusturan, style: TextStyle(fontSize: 11.5, color: r.silik)),
                          ]),
                        if (salt && durum == 'in_progress') cip(Icons.timelapse_rounded, 'Sürüyor', r.birincilYumusak, r.birincil),
                      ]),
                      if (fotolar.isNotEmpty || fotoYukleniyor) ...[
                        const SizedBox(height: 10),
                        FotoSeridi(fotolar: fotolar, yukleniyor: fotoYukleniyor),
                      ],
                      if (!bitti && !salt) ...[
                        const SizedBox(height: 12),
                        durum == 'open'
                            ? SizedBox(
                                width: double.infinity,
                                child: YumusakDugme(
                                  yazi: acik ? 'Üstlen ve başla' : 'Başla',
                                  ikon: Icons.play_arrow_rounded,
                                  onTap: mesgul ? null : onIlerlet,
                                ),
                              )
                            : Row(children: [
                                if (onFotoEkle != null && fotolar.length < gorevFotoSiniri) ...[
                                  YumusakDugme(
                                    yazi: 'Fotoğraf',
                                    ikon: Icons.add_a_photo_rounded,
                                    onTap: mesgul || fotoYukleniyor ? null : onFotoEkle,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: GradDugme(
                                    yazi: 'Tamamladım',
                                    ikon: Icons.check_rounded,
                                    yukseklik: 48,
                                    yukleniyor: mesgul || fotoYukleniyor,
                                    onTap: onIlerlet,
                                  ),
                                ),
                              ]),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
