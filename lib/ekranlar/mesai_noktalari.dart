import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/konum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// MESAİ NOKTALARI (Ekibim › Noktalar) — mesai QR'ının okutulabileceği
/// konum + yarıçap. Personel QR okuturken konumu bu noktaya göre doğrulanır.
///   GET  /api/v1/portal/yonetici/mesai-noktalari
///   POST /api/v1/portal/yonetici/mesai-noktalari/{id} {lat,lng,yaricap_m,zorunlu}
/// Düzenleme `staff.manage` ister; diğer yöneticiler salt okur.
class MesaiNoktalari extends StatefulWidget {
  const MesaiNoktalari({super.key});
  @override
  State<MesaiNoktalari> createState() => _MesaiNoktalariState();
}

const _yaricaplar = [50, 100, 150, 250, 500, 1000];

class _MesaiNoktalariState extends State<MesaiNoktalari> {
  Map<String, dynamic>? _veri;
  ApiHata? _hata;
  final _mesgul = <int>{};

  bool get _duzenler => Uyg.izin('staff.manage');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final r = await Uyg.api.get('/api/v1/portal/yonetici/mesai-noktalari');
      if (mounted) setState(() => _veri = Map<String, dynamic>.from(r as Map));
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e);
    }
  }

  List<Map<String, dynamic>> get _noktalar =>
      ((_veri?['noktalar'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  Future<void> _kaydet(Map<String, dynamic> n, Map<String, dynamic> degisen, {String? basari}) async {
    final id = (n['id'] as num).toInt();
    final govde = {
      'lat': _d(n['lat']),
      'lng': _d(n['lng']),
      'yaricap_m': (n['yaricap_m'] as num?)?.toInt() ?? 100,
      'zorunlu': n['zorunlu'] == true,
      ...degisen,
    };
    setState(() => _mesgul.add(id));
    try {
      final r = await Uyg.api.post('/api/v1/portal/yonetici/mesai-noktalari/$id', govde);
      final yeni = r is Map && r['nokta'] is Map ? Map<String, dynamic>.from(r['nokta'] as Map) : {...n, ...govde};
      if (!mounted) return;
      setState(() {
        final l = (_veri!['noktalar'] as List).map((e) => (e as Map)['id'] == n['id'] ? yeni : e).toList();
        _veri = {..._veri!, 'noktalar': l};
      });
      if (basari != null) bildir(basari);
    } on ApiHata catch (e) {
      bildir('Kaydedilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul.remove(id));
    }
  }

  Future<void> _buradaAyarla(Map<String, dynamic> n) async {
    final id = (n['id'] as num).toInt();
    setState(() => _mesgul.add(id));
    var k = await Konum.al();
    if (mounted) setState(() => _mesgul.remove(id));
    if (!mounted) return;
    if (k.konum == null) {
      final tekrar = await konumPanosu(context, k.durum);
      if (!tekrar || !mounted) return;
      k = await Konum.al();
      if (k.konum == null || !mounted) {
        bildir('Konum alınamadı', mesaj: 'Açık alanda yeniden dene.', tur: BildirimTur.uyari);
        return;
      }
    }
    final p = k.konum!;
    final dogruluk = p.accuracy.round();
    final onay = await panoAc<bool>(
      context,
      baslik: 'Bu konum kaydedilsin mi?',
      alt: n['ad']?.toString(),
      icerik: (ctx) {
        final r = ctx.pa;
        final zayif = dogruluk > 50;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              PaIkon(Icons.my_location_rounded, boyut: 44, grad: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}', style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('Doğruluk ±$dogruluk m', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: zayif ? const Color(0xFFB45309) : (r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)))),
                ]),
              ),
            ]),
          ),
          if (zayif) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Marka.kehribar.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
              child: const Text('Doğruluk düşük. Daha kesin konum için kapı/pencere yakınında birkaç saniye bekleyip yeniden dene ya da yarıçapı büyük seç.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFFB45309), fontWeight: FontWeight.w500)),
            ),
          ],
          const SizedBox(height: 16),
          GradDugme(yazi: 'Mesai noktası yap', ikon: Icons.check_rounded, onTap: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 6),
          PaMetinDugme(yazi: 'Vazgeç', onTap: () => Navigator.pop(ctx, false)),
        ]);
      },
    );
    if (onay == true) {
      await _kaydet(n, {'lat': double.parse(p.latitude.toStringAsFixed(7)), 'lng': double.parse(p.longitude.toStringAsFixed(7))}, basari: 'Mesai noktası kaydedildi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    if (_veri == null && _hata != null) return HataDurum(hata: _hata!, onTekrar: _yukle);
    if (_veri == null) {
      return const Column(children: [Iskelet(yukseklik: 84, radius: 24), SizedBox(height: 12), Iskelet(yukseklik: 230, radius: 24)]);
    }
    if (_veri!['destekli'] == false) {
      return const BosDurum(
        ikon: Icons.system_update_rounded,
        baslik: 'Sistem güncellemesi bekleniyor',
        aciklama: 'Konumla mesai doğrulaması, işletmenin sistemi güncellendiğinde burada açılacak.',
      );
    }
    final l = _noktalar;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaKart(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PaIkon(Icons.share_location_rounded, boyut: 44, grad: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mesai noktaları', style: gosterim(17, renk: r.metin)),
              const SizedBox(height: 3),
              Text('Personel mesai QR\'ını okuturken konumu bu noktaya göre doğrulanır. "Zorunlu" açıksa nokta dışında mesai/mola kaydı alınmaz.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: r.soluk)),
            ]),
          ),
        ]),
      ),
      if (!_duzenler)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: r.silik),
            const SizedBox(width: 6),
            Expanded(child: Text('Düzenlemek için personel yönetme yetkisi gerekir.', style: TextStyle(fontSize: 12, color: r.silik))),
          ]),
        ),
      const SizedBox(height: 14),
      if (l.isEmpty)
        const BosDurum(ikon: Icons.qr_code_2_rounded, baslik: 'Mesai noktası yok', aciklama: 'Mesai QR\'ı tanımlı cihaz/şube bulunamadı.')
      else
        for (var i = 0; i < l.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: Belir(gecikme: i * 50, child: _kart(l[i]))),
    ]);
  }

  Widget _cip(String yazi, Color renk, IconData ikon) {
    final r = context.pa;
    final on = r.koyu ? Color.lerp(renk, Colors.white, .3)! : renk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(8), border: Border.all(color: renk.withValues(alpha: .22))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon, size: 13, color: on),
        const SizedBox(width: 4),
        Text(yazi, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on)),
      ]),
    );
  }

  Widget _kart(Map<String, dynamic> n) {
    final r = context.pa;
    final id = (n['id'] as num).toInt();
    final lat = _d(n['lat']);
    final lng = _d(n['lng']);
    final ayarli = lat != null && lng != null;
    final yaricap = (n['yaricap_m'] as num?)?.toInt() ?? 100;
    final zorunlu = n['zorunlu'] == true;
    final mesgul = _mesgul.contains(id);
    final duzen = _duzenler && !mesgul;
    final sube = n['sube']?.toString();

    return PaKart(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          PaIkon(ayarli ? Icons.location_on_rounded : Icons.location_off_rounded, boyut: 44,
              zemin: ayarli ? null : Marka.kehribar.withValues(alpha: .14), renk: ayarli ? null : const Color(0xFFB45309)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n['ad']?.toString() ?? 'Mesai noktası', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: r.metin)),
              if (sube != null && sube.isNotEmpty) Text(sube, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk)),
            ]),
          ),
          if (mesgul) const SizedBox(width: 20, height: 20, child: Yukleyici(boyut: 20, renk: Marka.mor)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ayarli ? _cip('Konum ayarlı', Marka.zumrut, Icons.check_circle_rounded) : _cip('Konum ayarlanmamış', Marka.kehribar, Icons.error_outline_rounded),
          _cip(zorunlu ? 'Zorunlu açık' : 'Zorunlu kapalı', zorunlu ? Marka.mor : const Color(0xFF64748B), zorunlu ? Icons.lock_rounded : Icons.lock_open_rounded),
          _cip('${_m(yaricap)} yarıçap', Marka.mavi, Icons.radar_rounded),
        ]),
        if (ayarli) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.place_outlined, size: 16, color: r.silik),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: r.soluk, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              PaMetinDugme(
                yazi: 'Haritada aç',
                kucuk: true,
                sonIkon: Icons.open_in_new_rounded,
                onTap: () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lng'), mode: LaunchMode.externalApplication),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Text('Yarıçap', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: r.soluk)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (_, k) {
          final sutun = k.maxWidth > 420 ? 6 : 3;
          final w = (k.maxWidth - 6 * (sutun - 1)) / sutun;
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final y in _yaricaplar)
              SizedBox(
                width: w,
                child: Builder(builder: (_) {
                  final kutu = AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: y == yaricap ? Marka.grad : null,
                      color: y == yaricap ? null : r.ic,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: y == yaricap ? Colors.white.withValues(alpha: .2) : r.kenar),
                    ),
                    child: Text(_m(y), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: y == yaricap ? Colors.white : r.soluk)),
                  );
                  // Salt okurken basılamaz ama soluklaşmaz (seçili değer okunur kalsın)
                  if (!duzen) return kutu;
                  return Basilir(
                    olcek: .94,
                    onTap: () {
                      if (y != yaricap) _kaydet(n, {'yaricap_m': y});
                    },
                    child: kutu,
                  );
                }),
              ),
          ]);
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Konum zorunlu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: r.metin)),
                Text(ayarli ? 'Açıksa nokta dışında QR kabul edilmez' : 'Önce konumu ayarla', style: TextStyle(fontSize: 11.5, color: r.soluk)),
              ]),
            ),
            Switch.adaptive(
              value: zorunlu,
              activeTrackColor: Marka.mor,
              onChanged: duzen
                  ? (v) {
                      if (v && !ayarli) {
                        bildir('Önce konumu ayarla', mesaj: 'Zorunlu konum için mesai noktasının konumu gerekli.', tur: BildirimTur.uyari);
                        return;
                      }
                      _kaydet(n, {'zorunlu': v});
                    }
                  : null,
            ),
          ]),
        ),
        if (_duzenler) ...[
          const SizedBox(height: 12),
          ayarli
              ? YumusakDugme(yazi: 'Konumumu mesai noktası yap', ikon: Icons.my_location_rounded, onTap: mesgul ? null : () => _buradaAyarla(n))
              : GradDugme(yazi: 'Konumumu mesai noktası yap', ikon: Icons.my_location_rounded, yukseklik: 50, onTap: mesgul ? null : () => _buradaAyarla(n)),
        ],
      ]),
    );
  }

  static String _m(int m) => m >= 1000 ? '${m ~/ 1000} km' : '$m m';
}
