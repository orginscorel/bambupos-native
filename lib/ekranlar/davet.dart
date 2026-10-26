import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// DAVET ET, KAZAN — BamBumPOS'a işletme öner (web: Portal/Invite.vue).
/// Mevcut satış ortaklığı (Affiliate) modülü: kişiye özel bağlantı, gelen
/// işletmeler, hakedişler ve ödeme talebi. Kampanya → Davetlerim → Hakediş.
class DavetEkrani extends StatefulWidget {
  const DavetEkrani({super.key});
  @override
  State<DavetEkrani> createState() => _DavetEkraniState();
}

class _DavetEkraniState extends State<DavetEkrani> {
  static const _sekmeler = ['Kampanya', 'Davetlerim', 'Hakediş'];
  Map<String, dynamic>? _d;
  int _sekme = 0;
  bool _odemeBekle = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/davet');
      if (!mounted) return;
      setState(() => _d = Map<String, dynamic>.from(r as Map));
    } on ApiHata catch (e) {
      bildir('Davet bilgisi alınamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    }
  }

  String get _durum => _d?['durum']?.toString() ?? 'yok';
  bool get _aktif => _durum == 'active';
  Map get _kurallar => (_d?['kurallar'] as Map?) ?? const {};
  Map get _ist => (_d?['istatistik'] as Map?) ?? const {};
  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  String? get _baglanti => _d?['kisa_link']?.toString() ?? _d?['link']?.toString();

  String _tarih(dynamic s) {
    final t = DateTime.tryParse(s?.toString() ?? '')?.toLocal();
    if (t == null) return '';
    const aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return '${t.day} ${aylar[t.month - 1]} ${t.year}';
  }

  Future<void> _paylas() async {
    final url = _baglanti;
    if (url == null) return;
    titret(1);
    await SharePlus.instance.share(ShareParams(
      text: "İşletmen için BamBumPOS'u dene: QR menü, POS, mutfak ekranı ve personel uygulaması tek sistemde. $url",
      subject: 'BamBumPOS',
    ));
  }

  Future<void> _whatsapp() async {
    final url = _baglanti;
    if (url == null) return;
    final u = Uri.parse('https://wa.me/?text=${Uri.encodeComponent("İşletmen için BamBumPOS'u dene: $url")}');
    if (!await launchUrl(u, mode: LaunchMode.externalApplication)) {
      bildir('WhatsApp açılamadı', tur: BildirimTur.hata);
    }
  }

  Future<void> _kopyala(String t) async {
    await Clipboard.setData(ClipboardData(text: t));
    titret();
    bildir('Kopyalandı', mesaj: t);
  }

  Future<void> _odemeIste() async {
    setState(() => _odemeBekle = true);
    try {
      final r = await Uyg.api.post('/api/v1/portal/davet/odeme') as Map;
      bildir('Ödeme talebin alındı', mesaj: '${paraYaz(_i(r['tutar_minor']))} · ödemeler haftalık yapılır');
      await _yukle();
    } on ApiHata catch (e) {
      bildir('Talep oluşturulamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _odemeBekle = false);
    }
  }

  void _formuAc() {
    final o = (_d?['onerilen'] as Map?) ?? const {};
    panoAc<void>(
      context,
      baslik: 'Davet hesabı',
      alt: "Kazançların bu IBAN'a gönderilir.",
      icerik: (_) => _BasvuruFormu(
        ad: o['name']?.toString() ?? Uyg.ad,
        eposta: o['email']?.toString() ?? '',
        telefon: o['phone']?.toString() ?? '',
        yeni: _durum == 'yok',
        bitti: () async {
          Navigator.of(context).pop();
          await _yukle();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PaSayfa(
      baslik: 'Davet et, kazan',
      yenile: _yukle,
      govde: Kaydir(children: [
        _adimCizgisi(),
        const SizedBox(height: 16),
        if (_d == null)
          const PaKart(child: Iskelet(yukseklik: 260))
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(a), child: c),
            ),
            child: KeyedSubtree(key: ValueKey(_sekme), child: [_kampanya, _davetler, _hakedis][_sekme]()),
          ),
      ]),
    );
  }

  Widget _adimCizgisi() {
    final r = context.pa;
    return Row(children: [
      for (var i = 0; i < _sekmeler.length; i++) ...[
        GestureDetector(
          onTap: () {
            titret();
            setState(() => _sekme = i);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: _sekme == i ? r.birincil : r.soluk),
              child: Text(_sekmeler[i]),
            ),
          ),
        ),
        if (i < _sekmeler.length - 1)
          Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: r.kenar, borderRadius: BorderRadius.circular(9)),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _sekme > i ? 1 : 0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: Container(decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(9))),
                ),
              ),
            ),
          ),
      ],
    ]);
  }

  /* ─────────── Kampanya ─────────── */

  Widget _kampanya() {
    final r = context.pa;
    final oran = _kurallar['oran_yuzde'];
    final oranYazi = oran is num ? (oran == oran.roundToDouble() ? oran.toInt().toString() : oran.toString()) : '15';
    return Column(children: [
      Belir(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: AspectRatio(
            aspectRatio: 360 / 200,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => CustomPaint(painter: _AfisCizer(v)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Belir(
        gecikme: 80,
        child: PaKart(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Kafe ve restoran davet et, kazan!', textAlign: TextAlign.center, style: gosterim(20, renk: r.metin, satir: 1.2)),
            const SizedBox(height: 16),
            _madde(Icons.percent_rounded, [
              const TextSpan(text: 'Davet ettiğin işletmenin abonelik ödemelerinden '),
              TextSpan(text: '%$oranYazi pay', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700)),
              const TextSpan(text: ' kazan.'),
            ]),
            _madde(Icons.calendar_month_rounded, [
              const TextSpan(text: 'Kazancın '),
              TextSpan(text: '${_i(_kurallar['ay'])} ay boyunca', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700)),
              const TextSpan(text: ' her ödemede devam eder.'),
            ]),
            _madde(Icons.account_balance_wallet_rounded, [
              const TextSpan(text: 'Bakiye '),
              TextSpan(text: paraYaz(_i(_kurallar['min_odeme_minor'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: " olunca IBAN'ına ödeme iste."),
            ]),
            const SizedBox(height: 8),
            ..._kampanyaEylem(),
          ]),
        ),
      ),
    ]);
  }

  Widget _madde(IconData ikon, List<InlineSpan> parca) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PaIkon(ikon, boyut: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(TextSpan(children: parca), style: TextStyle(color: context.pa.metin, fontSize: 14, height: 1.4)),
            ),
          ),
        ]),
      );

  List<Widget> _kampanyaEylem() {
    final r = context.pa;
    if (_aktif) {
      return [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Text(_d?['kisa_link']?.toString() ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: r.metin, fontSize: 13.5)),
            ),
            Basilir(
              onTap: () => _kopyala(_d?['kisa_link']?.toString() ?? ''),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.copy_rounded, color: r.birincil, size: 18),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GradDugme(yazi: 'Davet gönder', ikon: Icons.ios_share_rounded, onTap: _paylas)),
          const SizedBox(width: 8),
          Basilir(
            onTap: _whatsapp,
            child: Container(
              width: 56,
              height: 54,
              decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.chat_rounded, color: Colors.white),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        YumusakDugme(yazi: 'Ödeme bilgilerini güncelle', onTap: _formuAc),
      ];
    }
    if (_durum == 'pending') {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Marka.kehribar.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const _Nabiz(renk: Marka.kehribar),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Başvurun inceleniyor. Onaylanınca davet bağlantın burada açılır.',
                  style: TextStyle(color: r.koyu ? const Color(0xFFFDE68A) : const Color(0xFF78350F), fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        YumusakDugme(yazi: 'Bilgilerimi düzenle', onTap: _formuAc),
      ];
    }
    if (_durum == 'suspended' || _durum == 'rejected') {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
          child: const Text('Davet hesabın şu an kapalı. Ayrıntı için destek@bambumpos.com',
              style: TextStyle(color: Marka.gul, fontWeight: FontWeight.w600, fontSize: 13.5)),
        ),
      ];
    }
    return [GradDugme(yazi: 'Davet hesabımı aç', ikon: Icons.auto_awesome_rounded, onTap: _formuAc)];
  }

  /* ─────────── Davetlerim ─────────── */

  Widget _davetler() {
    final r = context.pa;
    final liste = ((_d?['davetler'] as List?) ?? const []).whereType<Map>().toList();
    return Column(children: [
      if (_aktif)
        Row(children: [
          for (final (i, k) in [('Tıklama', _i(_ist['clicks']), r.metin), ('Davet', _i(_ist['referrals']), r.birincil), ('Aktif', _i(_ist['active']), Marka.zumrut)].indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Belir(
                gecikme: 50 * i,
                child: PaKart(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(children: [
                    Sayac(deger: k.$2, yaz: (v) => v.round().toString(), stil: gosterim(22, renk: k.$3)),
                    Text(k.$1, style: TextStyle(color: r.soluk, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      const SizedBox(height: 14),
      if (liste.isEmpty)
        BosDurum(
          ikon: Icons.groups_rounded,
          baslik: 'Henüz davet yok',
          aciklama: 'Bağlantınla gelen işletmeler burada listelenir.',
          eylem: YumusakDugme(yazi: 'Davet gönder', onTap: () => setState(() => _sekme = 0)),
        )
      else
        for (var i = 0; i < liste.length; i++)
          Belir(
            gecikme: math.min(i, 8) * 40,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PaKart(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const PaIkon(Icons.storefront_rounded, boyut: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(liste[i]['ad']?.toString() ?? 'İşletme', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: r.metin)),
                      Text(_tarih(liste[i]['tarih']), style: TextStyle(color: r.soluk, fontSize: 12)),
                    ]),
                  ),
                  _DurumEtiketi(liste[i]['durum']?.toString() ?? ''),
                ]),
              ),
            ),
          ),
    ]);
  }

  /* ─────────── Hakediş ─────────── */

  Widget _hakedis() {
    final r = context.pa;
    final bakiye = _i(_ist['balance_minor']);
    final minOdeme = _i(_kurallar['min_odeme_minor']);
    final bekleyen = _d?['bekleyen_odeme'] as Map?;
    final yapilabilir = bakiye >= minOdeme && bekleyen == null && bakiye > 0;
    final odemeler = ((_d?['odemeler'] as List?) ?? const []).whereType<Map>().toList();
    final hakedisler = ((_d?['hakedisler'] as List?) ?? const []).whereType<Map>().toList();
    final String dugmeYazi = bekleyen != null
        ? 'Talep işleniyor · ${paraYaz(_i(bekleyen['tutar_minor']))}'
        : yapilabilir
            ? 'Ödeme iste'
            : 'En az ${paraYaz(minOdeme)} gerekir';
    return Column(children: [
      Belir(
        child: PaKart(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF064E3B), Color(0xFF0D9488), Marka.mavi]),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ÇEKİLEBİLİR BAKİYE', style: TextStyle(color: const Color(0xFFD1FAE5).withValues(alpha: .8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Sayac(deger: bakiye, yaz: paraYaz, stil: gosterim(34, renk: Colors.white, satir: 1)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _kucukKutu('Toplam kazanç', paraYaz(_i(_ist['earned_minor'])))),
              const SizedBox(width: 8),
              Expanded(child: _kucukKutu('Ödenen', paraYaz(_i(_ist['paid_minor'])))),
            ]),
            if (_aktif) ...[
              const SizedBox(height: 14),
              Basilir(
                onTap: yapilabilir && !_odemeBekle ? _odemeIste : null,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Center(
                    child: _odemeBekle
                        ? const Yukleyici(boyut: 22, renk: Color(0xFF065F46))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF065F46), size: 18),
                            const SizedBox(width: 8),
                            Text(dugmeYazi, style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
              ),
            ],
            if (_d?['iban_maskeli'] != null) ...[
              const SizedBox(height: 8),
              Center(child: Text('IBAN ${_d!['iban_maskeli']}', style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 12))),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Belir(
        gecikme: 80,
        child: PaKart(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Text('HAREKETLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: r.silik)),
            ),
            if (odemeler.isEmpty && hakedisler.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                child: Text('Henüz hakediş yok. Davet ettiğin işletme ödeme yaptıkça burada görünür.', style: TextStyle(color: r.soluk, fontSize: 13.5)),
              ),
            for (final o in odemeler) _hareket(Icons.south_rounded, Marka.zumrut, 'Ödeme', _tarih(o['tarih']), paraYaz(_i(o['tutar_minor'])), r.metin, o['durum']?.toString() ?? ''),
            for (final h in hakedisler)
              _hareket(Icons.add_rounded, r.birincil, 'Hakediş ${h['donem'] ?? ''}'.trim(), _tarih(h['tarih']), '+${paraYaz(_i(h['tutar_minor']))}', Marka.zumrut,
                  h['durum']?.toString() ?? ''),
          ]),
        ),
      ),
    ]);
  }

  Widget _kucukKutu(String b, String d) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b, style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(d, style: gosterim(15, renk: Colors.white))),
        ]),
      );

  Widget _hareket(IconData ikon, Color ikonRenk, String baslik, String tarih, String tutar, Color tutarRenk, String durum) {
    final r = context.pa;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: ikonRenk.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
          child: Icon(ikon, color: ikonRenk, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: r.metin)),
            Text(tarih, style: TextStyle(color: r.soluk, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(tutar, style: gosterim(14, renk: tutarRenk)),
          const SizedBox(height: 3),
          _DurumEtiketi(durum, kucuk: true),
        ]),
      ]),
    );
  }
}

/* ───────────────────────── Yardımcılar ───────────────────────── */

class _DurumEtiketi extends StatelessWidget {
  const _DurumEtiketi(this.durum, {this.kucuk = false});
  final String durum;
  final bool kucuk;
  @override
  Widget build(BuildContext context) {
    final (yazi, renk) = switch (durum) {
      'pending' => ('Bekliyor', Marka.kehribar),
      'active' => ('Aktif', Marka.zumrut),
      'approved' => ('Onaylandı', Marka.gok),
      'paid' => ('Ödendi', Marka.zumrut),
      'requested' => ('Talep edildi', Marka.kehribar),
      'cancelled' => ('İptal', context.pa.silik),
      'rejected' => ('Reddedildi', Marka.gul),
      _ => (durum, context.pa.silik),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: kucuk ? 7 : 10, vertical: kucuk ? 2 : 4),
      decoration: BoxDecoration(color: renk.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
      child: Text(yazi, style: TextStyle(color: renk, fontSize: kucuk ? 10 : 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _Nabiz extends StatefulWidget {
  const _Nabiz({required this.renk});
  final Color renk;
  @override
  State<_Nabiz> createState() => _NabizState();
}

class _NabizState extends State<_Nabiz> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(alignment: Alignment.center, children: [
            Container(
              width: 10 + 12 * _c.value,
              height: 10 + 12 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.renk.withValues(alpha: (1 - _c.value) * .5)),
            ),
            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.renk)),
          ]),
        ),
      );
}

/// Başvuru / bilgi güncelleme formu (alttan pano içinde).
class _BasvuruFormu extends StatefulWidget {
  const _BasvuruFormu({required this.ad, required this.eposta, required this.telefon, required this.yeni, required this.bitti});
  final String ad;
  final String eposta;
  final String telefon;
  final bool yeni;
  final Future<void> Function() bitti;
  @override
  State<_BasvuruFormu> createState() => _BasvuruFormuState();
}

class _BasvuruFormuState extends State<_BasvuruFormu> {
  late final _ad = TextEditingController(text: widget.ad);
  late final _tel = TextEditingController(text: widget.telefon);
  late final _eposta = TextEditingController(text: widget.eposta);
  final _iban = TextEditingController(text: 'TR');
  final _tc = TextEditingController();
  final Map<String, String> _hatalar = {};
  bool _bekle = false;

  @override
  void dispose() {
    for (final c in [_ad, _tel, _eposta, _iban, _tc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gonder() async {
    setState(() {
      _bekle = true;
      _hatalar.clear();
    });
    try {
      final r = await Uyg.api.post('/api/v1/portal/davet/basvuru', {
        'name': _ad.text.trim(),
        'phone': _tel.text.trim(),
        'email': _eposta.text.trim(),
        'iban': _iban.text.replaceAll(' ', '').toUpperCase(),
        'tax_no': _tc.text.trim().isEmpty ? null : _tc.text.trim(),
      }) as Map;
      titret(1);
      bildir(r['mesaj']?.toString() ?? 'Kaydedildi');
      await widget.bitti();
    } on ApiHata catch (e) {
      final h = e.govde?['errors'];
      if (h is Map && h.isNotEmpty) {
        setState(() {
          h.forEach((k, v) => _hatalar[k.toString()] = v is List && v.isNotEmpty ? v.first.toString() : v.toString());
        });
      } else {
        bildir('Kaydedilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      }
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  Widget _alan(String etiket, TextEditingController c, String anahtar, {TextInputType? klavye, String? ipucu, List<String>? doldur}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: klavye,
          autofillHints: doldur,
          textCapitalization: anahtar == 'iban' ? TextCapitalization.characters : TextCapitalization.none,
          decoration: InputDecoration(labelText: etiket, helperText: ipucu, errorText: _hatalar[anahtar]),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _alan('Ad soyad', _ad, 'name', doldur: const [AutofillHints.name]),
        _alan('Telefon', _tel, 'phone', klavye: TextInputType.phone, doldur: const [AutofillHints.telephoneNumber]),
        _alan('E-posta', _eposta, 'email', klavye: TextInputType.emailAddress, doldur: const [AutofillHints.email]),
        _alan('IBAN', _iban, 'iban', ipucu: 'TR ile başlayan 26 hane'),
        _alan('TC kimlik no', _tc, 'tax_no', klavye: TextInputType.number, ipucu: 'Ödeme belgesi için (isteğe bağlı)'),
        const SizedBox(height: 4),
        GradDugme(yazi: widget.yeni ? 'Başvur' : 'Kaydet', yukleniyor: _bekle, onTap: _gonder),
      ]);
}

/* ───────────────────────── Afiş çizimi ───────────────────────── */

/// "DAVET ET / KAZAN" afişi: lacivert zemin, mor ışık, telefon çizimi.
class _AfisCizer extends CustomPainter {
  _AfisCizer(this.t);
  final double t;

  void _yazi(Canvas c, String s, Offset o, double boyut, Color renk, {FontWeight w = FontWeight.w800, String aile = 'Jakarta'}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: aile, fontSize: boyut, fontWeight: w, color: renk, fontVariations: [FontVariation('wght', w.value.toDouble())]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 360;
    c.scale(k);
    const alan = Rect.fromLTWH(0, 0, 360, 200);
    c.drawRect(
      alan,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Marka.lacivert0, Marka.lacivert1, Marka.lacivert2],
          stops: [0, .45, 1],
        ).createShader(alan),
    );
    c.drawCircle(
      const Offset(270, 60),
      150,
      Paint()..shader = RadialGradient(colors: [Marka.mor.withValues(alpha: .8), Marka.mor.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: const Offset(270, 60), radius: 150)),
    );

    // Telefon (aşağıdan yükselir)
    c.save();
    c.translate(0, 30 * (1 - t));
    final telefon = RRect.fromRectAndRadius(const Rect.fromLTWH(214, 26, 92, 160), const Radius.circular(18));
    c.drawRRect(telefon, Paint()..color = Marka.murekkep);
    c.drawRRect(telefon, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .2));
    const ekran = Rect.fromLTWH(224, 44, 72, 50);
    c.drawRRect(RRect.fromRectAndRadius(ekran, const Radius.circular(10)), Paint()..shader = Marka.grad.createShader(ekran));
    c.drawCircle(const Offset(260, 69), 13, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: .9));
    c.drawPath(
      Path()
        ..moveTo(254, 69)
        ..lineTo(258, 73)
        ..lineTo(266, 65),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(224, 104, 50, 7), const Radius.circular(3.5)), Paint()..color = Colors.white.withValues(alpha: .35));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(224, 118, 70, 7), const Radius.circular(3.5)), Paint()..color = Colors.white.withValues(alpha: .18));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(224, 140, 72, 24), const Radius.circular(8)), Paint()..color = Marka.gok);
    c.restore();

    // Kıvılcımlar
    c.drawCircle(const Offset(196, 40), 4 * t, Paint()..color = Marka.lavanta);
    c.drawCircle(const Offset(322, 30), 3 * t, Paint()..color = const Color(0xFF7DD3FC));
    c.drawCircle(const Offset(330, 150), 5 * t, Paint()..color = const Color(0xFF34D399));

    // Yazılar (soldan süzülür)
    c.save();
    c.translate(-16 * (1 - t), 0);
    final a = t.clamp(0.0, 1.0);
    _yazi(c, 'DAVET ET', const Offset(22, 42), 30, Colors.white.withValues(alpha: a));
    _yazi(c, 'KAZAN', const Offset(22, 78), 30, const Color(0xFFA5B4FC).withValues(alpha: a));
    _yazi(c, 'İşletme öner,', const Offset(22, 124), 12.5, Colors.white.withValues(alpha: .65 * a), w: FontWeight.w400, aile: 'Poppins');
    _yazi(c, 'her ödemesinden pay al', const Offset(22, 142), 12.5, Colors.white.withValues(alpha: .65 * a), w: FontWeight.w400, aile: 'Poppins');
    c.restore();
  }

  @override
  bool shouldRepaint(_AfisCizer o) => o.t != t;
}
