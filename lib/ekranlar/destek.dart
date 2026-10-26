import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// DESTEK — web Portal/Support.vue karşılığı: işletme yetkilileri (ara /
/// WhatsApp), BamBumPOS destek e-postası, sık sorulanlar.
class DestekEkrani extends StatefulWidget {
  const DestekEkrani({super.key});
  @override
  State<DestekEkrani> createState() => _DestekEkraniState();
}

class _DestekEkraniState extends State<DestekEkrani> {
  List<Map<String, dynamic>>? _yetkililer;
  String _eposta = 'destek@bambumpos.com';
  int? _acik = 0;

  static const _sss = [
    ('Mesaiye nasıl başlarım?',
        'Alt menünün ortasındaki QR düğmesine dokun, işletmedeki ekranda (kasa / giriş tableti) görünen mesai QR’ını okut. Açılan panodan “Mesaiye başla”yı seç.'),
    ('Neden QR okutmadan mesai başlatamıyorum?',
        'Mesai ve mola kayıtları yalnızca işletmede bulunduğunu doğrulayan QR ile yapılır. QR her birkaç saniyede değişir; fotoğrafı ya da gönderilen bağlantı çalışmaz.'),
    ('“QR geçerli değil” diyor',
        'Kod çok kısa süre geçerlidir. Ekrandaki yeni kodu tekrar okut. Sorun sürerse telefonunun saatinin otomatik olduğundan emin ol.'),
    ('Molam hakkımı aşarsa ne olur?',
        'İşlem engellenmez; aşım süren kayda geçer ve yöneticin görür. Kalan mola hakkını QR panosunda ve ana ekranda görebilirsin.'),
    ('Bildirimler gelmiyor',
        'Profil › Bildirimler bölümünden anlık bildirimlere izin ver. Telefon ayarlarında BamBumPOS Personel için bildirimlerin açık olduğundan emin ol.'),
    ('POS PIN’imi unuttum',
        'Profil › POS PIN bölümünden yenisini belirleyebilirsin. Mevcut PIN’i hatırlamıyorsan yöneticin sıfırlayabilir.'),
  ];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/destek') as Map;
      if (!mounted) return;
      setState(() {
        _yetkililer = ((r['yoneticiler'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _eposta = r['eposta']?.toString() ?? _eposta;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() => _yetkililer = const []);
      bildir('Yetkililer yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    }
  }

  static String _tel(String t) {
    final r = t.replaceAll(RegExp(r'\D'), '');
    if (r.startsWith('90')) return '+$r';
    if (r.startsWith('0')) return '+9$r';
    return '+90$r';
  }

  static String _bas(String ad) {
    final s = ad.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2).map((e) => e.characters.first.toUpperCase()).join();
    return s.isEmpty ? '•' : s;
  }

  Future<void> _ac(Uri u) async {
    try {
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok) bildir('Açılamadı', mesaj: u.toString(), tur: BildirimTur.hata);
    } catch (_) {
      bildir('Açılamadı', mesaj: u.toString(), tur: BildirimTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaSayfa(
      baslik: 'Destek',
      yenile: _yukle,
      govde: Kaydir(altBosluk: 40, children: [
        PaKart(
          gradient: Marka.kart,
          padding: const EdgeInsets.all(20),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              right: -18,
              top: -18,
              child: Icon(Icons.headset_mic_rounded, size: 120, color: Colors.white.withValues(alpha: .12)),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Nasıl yardımcı olabiliriz?', style: gosterim(22, renk: Colors.white)),
              const SizedBox(height: 6),
              Text(
                'İşletmenle ilgili konular için yetkiline, uygulama sorunları için BamBumPOS ekibine ulaş.',
                style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 13.5, height: 1.4),
              ),
            ]),
          ]),
        ),
        const BolumBasligi('İşletme yetkilileri'),
        if (_yetkililer == null)
          const Iskelet(yukseklik: 72, radius: 24)
        else if (_yetkililer!.isEmpty)
          PaKart(child: Text('Bu işletmede tanımlı yetkili bulunamadı.', style: TextStyle(color: r.soluk)))
        else
          SatirGrubu([
            for (final y in _yetkililer!) _yetkiliSatiri(context, y),
          ]),
        const BolumBasligi('BamBumPOS destek'),
        SatirGrubu([
          Satir(
            ikon: Icons.mail_rounded,
            grad: true,
            baslik: 'E-posta gönder',
            alt: _eposta,
            onTap: () => _ac(Uri(scheme: 'mailto', path: _eposta, query: 'subject=${Uri.encodeComponent('Personel uygulaması')}')),
          ),
        ]),
        const BolumBasligi('Sık sorulanlar'),
        PaKart(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(children: [
              for (var i = 0; i < _sss.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: r.kenar),
                _SssSatiri(
                  soru: _sss[i].$1,
                  cevap: _sss[i].$2,
                  acik: _acik == i,
                  onTap: () {
                    titret();
                    setState(() => _acik = _acik == i ? null : i);
                  },
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _yetkiliSatiri(BuildContext context, Map<String, dynamic> y) {
    final r = context.pa;
    final ad = y['ad']?.toString() ?? '';
    final tel = y['telefon']?.toString();
    final ayni = y['ayni_sube'] != false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: Marka.grad,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Color(0x885443D2), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -6)],
          ),
          child: Text(_bas(ad), style: gosterim(15, renk: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: r.metin)),
            Text('${y['rol'] ?? 'Yetkili'}${ayni ? '' : ' · başka şube'}', style: TextStyle(fontSize: 12, color: r.soluk)),
          ]),
        ),
        if (tel != null && tel.isNotEmpty) ...[
          Basilir(
            onTap: () => _ac(Uri(scheme: 'tel', path: _tel(tel))),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(15)),
              child: Icon(Icons.call_rounded, color: r.birincil, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Basilir(
            onTap: () => _ac(Uri.parse('https://wa.me/${_tel(tel).replaceAll('+', '')}')),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
            ),
          ),
        ] else
          Text('Telefon yok', style: TextStyle(fontSize: 12, color: r.silik)),
      ]),
    );
  }
}

class _SssSatiri extends StatelessWidget {
  const _SssSatiri({required this.soru, required this.cevap, required this.acik, required this.onTap});
  final String soru;
  final String cevap;
  final bool acik;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(soru, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: r.metin))),
            AnimatedRotation(
              turns: acik ? .5 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: r.ic, shape: BoxShape.circle),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: r.soluk, size: 20),
              ),
            ),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: acik
                ? Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Text(cevap, style: TextStyle(fontSize: 13.5, height: 1.5, color: r.soluk)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}
