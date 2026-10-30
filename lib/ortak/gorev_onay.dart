import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import 'gorev_foto.dart';
import 'ortak.dart';

/// FOTOĞRAFLI GÖREV ONAYI (sunucu 2026-10-30).
///
/// Sunucuda onay göçü çalıştıysa görev DTO'sunda `onay_destekli: true` gelir:
/// personel "Tamamladım" ile görevi bitiremez; en az 1 (en çok 3) fotoğraf +
/// isteğe bağlı notla ONAYA GÖNDERİR (durum `review`). Yönetici onaylar
/// (`done`) ya da gerekçe yazıp reddeder (`in_progress`, `onay.durum = rejected`).
/// `onay_destekli` gelmezse eski akış (fotoğraf isteğe bağlı, doğrudan bitir).

bool onayDestekli(Map g) => g['onay_destekli'] == true;

Map<String, dynamic>? gorevOnay(Map g) => g['onay'] is Map ? Map<String, dynamic>.from(g['onay'] as Map) : null;

bool gorevReddedildi(Map g) => g['status'] == 'in_progress' && gorevOnay(g)?['durum'] == 'rejected';

final _zaman = DateFormat('d MMM HH:mm', 'tr_TR');
String _z(Object? iso) {
  final t = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  return t == null ? '' : _zaman.format(t);
}

String? _ad(Object? kisi) => kisi is Map ? kisi['name']?.toString() : null;

/// Kartın altındaki onay bilgisi: geri gönderildi (gerekçe) · onay bekliyor ·
/// onaylandı (kim, ne zaman).
class GorevOnayBilgisi extends StatelessWidget {
  const GorevOnayBilgisi({super.key, required this.g, this.yonetici = false});
  final Map<String, dynamic> g;
  final bool yonetici;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final o = gorevOnay(g);
    if (o == null) return const SizedBox.shrink();
    final durum = g['status']?.toString();

    if (gorevReddedildi(g)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Marka.gul.withValues(alpha: .5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Geri gönderildi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Marka.gul)),
          const SizedBox(height: 2),
          Text(o['gerekce']?.toString() ?? '', style: TextStyle(fontSize: 13.5, color: r.metin, height: 1.35)),
          const SizedBox(height: 2),
          Text([_ad(o['inceleyen']), _z(o['inceleme'])].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 11.5, color: r.silik)),
        ]),
      );
    }
    if (durum == 'review') {
      final not = o['not']?.toString();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.schedule_rounded, size: 15, color: r.soluk),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Onay bekliyor · ${_z(o['gonderim'])}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.metin)),
            ),
          ]),
          if (not != null && not.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('“$not”', style: TextStyle(fontSize: 13, color: r.soluk, height: 1.35)),
            ),
          if (yonetici && (o['gerekce']?.toString().isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Önceki ret: ${o['gerekce']}', style: TextStyle(fontSize: 12, color: r.silik)),
            ),
        ]),
      );
    }
    if (durum == 'done' && o['durum'] == 'approved') {
      return Row(children: [
        Icon(Icons.verified_rounded, size: 15, color: r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ['Onaylandı', _ad(o['inceleyen']), _z(o['inceleme'])].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 12, color: r.soluk),
          ),
        ),
      ]);
    }
    return const SizedBox.shrink();
  }
}

/* ───────────── Personel: onaya gönder ekranı ───────────── */

/// Onaya gönder ekranını açar; gönderilirse sunucunun güncel görevini döner.
Future<Map<String, dynamic>?> onayaGonderAc(BuildContext context, Map<String, dynamic> g) =>
    Navigator.of(context).push<Map<String, dynamic>>(HizliRota(builder: (_) => OnayaGonderEkrani(gorev: g)));

class OnayaGonderEkrani extends StatefulWidget {
  const OnayaGonderEkrani({super.key, required this.gorev});
  final Map<String, dynamic> gorev;
  @override
  State<OnayaGonderEkrani> createState() => _OnayaGonderEkraniState();
}

class _OnayaGonderEkraniState extends State<OnayaGonderEkrani> {
  late List<Map<String, dynamic>> _fotolar = gorevFotolari(widget.gorev);
  final _not = TextEditingController();
  bool _yukleniyor = false;
  bool _gonderiliyor = false;
  String? _silinen;

  int get _id => (widget.gorev['id'] as num).toInt();

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    if (_yukleniyor || _fotolar.length >= gorevFotoSiniri) return;
    final yol = await gorevFotoSec(context, mevcut: _fotolar.length);
    if (yol == null || yol == 'yok' || !mounted) return;
    setState(() => _yukleniyor = true);
    final l = await gorevFotoYukle(_id, yol);
    if (!mounted) return;
    setState(() {
      _yukleniyor = false;
      if (l != null) _fotolar = l;
    });
  }

  Future<void> _sil(Map<String, dynamic> f) async {
    if (_silinen != null) return;
    final ad = f['ad']?.toString() ?? '';
    setState(() => _silinen = ad);
    try {
      final r = await Uyg.api.delete('/api/v1/portal/tasks/$_id/foto/$ad');
      final l = (r is Map ? r['fotolar'] as List? : null) ?? const [];
      if (mounted) setState(() => _fotolar = l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } on ApiHata catch (e) {
      bildir('Fotoğraf kaldırılamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _silinen = null);
    }
  }

  Future<void> _gonder() async {
    if (_gonderiliyor || _fotolar.isEmpty) return;
    setState(() => _gonderiliyor = true);
    try {
      final not = _not.text.trim();
      final r = await Uyg.api.post('/api/v1/portal/tasks/$_id/onaya-gonder', {'not': not.isEmpty ? null : not}) as Map;
      titret(1);
      bildir('Onaya gönderildi', mesaj: widget.gorev['title']?.toString());
      if (mounted) Navigator.of(context).pop(r['task'] is Map ? Map<String, dynamic>.from(r['task'] as Map) : null);
    } on ApiHata catch (e) {
      bildir('Gönderilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      if (mounted) setState(() => _gonderiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final g = widget.gorev;
    final o = gorevOnay(g);
    return PaSayfa(
      baslik: 'Onaya gönder',
      altBaslik: g['title']?.toString(),
      govde: ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          if (gorevReddedildi(g)) ...[
            GorevOnayBilgisi(g: g),
            const SizedBox(height: 16),
          ],
          Text('Fotoğraflar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: r.metin)),
          const SizedBox(height: 2),
          Text('İşin bittiğini gösteren en az 1, en çok $gorevFotoSiniri fotoğraf.', style: TextStyle(fontSize: 12.5, color: r.soluk)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < _fotolar.length; i++)
                Stack(fit: StackFit.expand, children: [
                  Basilir(
                    onTap: () => fotoBuyut(context, _fotolar, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: KorumaliFoto(url: _fotolar[i]['url'].toString(), boyut: 110),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Basilir(
                      onTap: () => _sil(_fotolar[i]),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
                        child: _silinen == _fotolar[i]['ad']
                            ? const Center(child: Yukleyici(boyut: 16, renk: Colors.white))
                            : const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ]),
              if (_fotolar.length < gorevFotoSiniri)
                Basilir(
                  onTap: _ekle,
                  child: Container(
                    decoration: BoxDecoration(
                      color: r.ic,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: r.kenar, width: 1.5),
                    ),
                    child: Center(
                      child: _yukleniyor
                          ? Yukleyici(boyut: 22, renk: r.birincil)
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.add_a_photo_rounded, color: r.birincil, size: 26),
                              const SizedBox(height: 4),
                              Text('Ekle', style: TextStyle(fontSize: 12.5, color: r.soluk)),
                            ]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _not,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', hintText: 'ör. Depo rafları düzenlendi'),
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: _fotolar.isEmpty ? .5 : 1,
            child: GradDugme(
              yazi: o?['durum'] == 'rejected' ? 'Tekrar onaya gönder' : 'Onaya gönder',
              ikon: Icons.send_rounded,
              yukleniyor: _gonderiliyor,
              onTap: _fotolar.isEmpty || _yukleniyor ? null : _gonder,
            ),
          ),
          if (_fotolar.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Göndermek için en az bir fotoğraf ekle.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: r.soluk)),
            ),
        ],
      ),
    );
  }
}

/* ───────────── Yönetici modu: onayla / reddet ───────────── */

/// Yönetici modunda (yetki tasks.assign) onay bekleyen görev için karar.
/// Dönüş: sunucunun güncel görevi (ya da null).
Future<Map<String, dynamic>?> gorevOnayla(int id) async {
  try {
    final r = await Uyg.api.post('/api/v1/portal/yonetici/gorev/$id/onayla') as Map;
    titret(1);
    bildir('Görev onaylandı');
    return r['gorev'] is Map ? Map<String, dynamic>.from(r['gorev'] as Map) : null;
  } on ApiHata catch (e) {
    bildir('Onaylanamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    return null;
  }
}

Future<Map<String, dynamic>?> gorevReddet(BuildContext context, Map<String, dynamic> g) async {
  final gerekce = await panoAc<String>(
    context,
    baslik: 'Görevi geri gönder',
    alt: 'Personel bu gerekçeyi görür ve düzeltip yeniden gönderir.',
    icerik: (ctx) => _GerekceFormu(baslik: g['title']?.toString() ?? ''),
  );
  if (gerekce == null) return null;
  try {
    final r = await Uyg.api.post('/api/v1/portal/yonetici/gorev/${(g['id'] as num).toInt()}/reddet', {'gerekce': gerekce}) as Map;
    bildir('Görev geri gönderildi', tur: BildirimTur.bilgi);
    return r['gorev'] is Map ? Map<String, dynamic>.from(r['gorev'] as Map) : null;
  } on ApiHata catch (e) {
    bildir('Gönderilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    return null;
  }
}

class _GerekceFormu extends StatefulWidget {
  const _GerekceFormu({required this.baslik});
  final String baslik;
  @override
  State<_GerekceFormu> createState() => _GerekceFormuState();
}

class _GerekceFormuState extends State<_GerekceFormu> {
  final _c = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _c,
          autofocus: true,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Gerekçe', hintText: 'ör. Alt raf da düzenlensin', errorText: _hata),
        ),
        const SizedBox(height: 8),
        GradDugme(
          yazi: 'Geri gönder',
          ikon: Icons.undo_rounded,
          onTap: () {
            final t = _c.text.trim();
            if (t.length < 3) {
              setState(() => _hata = 'Neyin düzeltileceğini kısaca yaz.');
              return;
            }
            Navigator.of(context).pop(t);
          },
        ),
      ]);
}

/// Yönetici kartı altındaki iki düğme (büyük dokunma alanı).
class OnayKararDugmeleri extends StatelessWidget {
  const OnayKararDugmeleri({super.key, required this.onOnayla, required this.onReddet, this.mesgul = false});
  final VoidCallback onOnayla;
  final VoidCallback onReddet;
  final bool mesgul;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: YumusakDugme(yazi: 'Reddet', ikon: Icons.undo_rounded, yukseklik: 48, onTap: mesgul ? null : onReddet)),
        const SizedBox(width: 8),
        Expanded(
          child: GradDugme(yazi: 'Onayla', ikon: Icons.check_rounded, yukseklik: 48, yukleniyor: mesgul, parilti: false, onTap: onOnayla),
        ),
      ]);
}
