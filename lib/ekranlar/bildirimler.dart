import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/bildirim.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'kabuk.dart';

/// BİLDİRİMLER — web Portal/Notifications.vue karşılığı: güne göre gruplu
/// liste, okunmamış vurgusu, tümünü okundu say, anlık bildirim izni.
class BildirimlerEkrani extends StatefulWidget {
  const BildirimlerEkrani({super.key});
  @override
  State<BildirimlerEkrani> createState() => _BildirimlerEkraniState();
}

class _BildirimlerEkraniState extends State<BildirimlerEkrani> with WidgetsBindingObserver {
  bool _yukleniyor = true;

  static final _gun = DateFormat('d MMMM EEEE', 'tr_TR');
  static final _saat = DateFormat('HH:mm', 'tr_TR');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BildirimMerkezi.izinDurumu();
    _yenile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Telefon ayarlarından dönünce izni yeniden oku
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) BildirimMerkezi.izinDurumu();
  }

  Future<void> _yenile() async {
    await BildirimMerkezi.yokla(ilk: true);
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _izinIste() async {
    if (BildirimMerkezi.izin.value == true) {
      bildir('Bildirimler zaten açık', mesaj: 'Kapatmak istersen telefon ayarlarından değiştirebilirsin.');
      return;
    }
    final ok = await BildirimMerkezi.izinIste();
    if (!mounted) return;
    if (ok) {
      bildir('Anlık bildirimler açık', mesaj: 'Görev, vardiya ve mesai bildirimleri bu telefona gelecek.');
      return;
    }
    // Daha önce reddedildiyse telefon yeniden sormaz → iPhone'da ayarlar sayfasını aç
    if (Platform.isIOS && await launchUrl(Uri.parse('app-settings:'))) return;
    bildir('İzin verilmedi',
        mesaj: Platform.isAndroid
            ? 'Ayarlar › Uygulamalar › BamBumPOS Personel › Bildirimler bölümünden aç.'
            : 'Ayarlar › BamBumPOS Personel › Bildirimler bölümünden aç.',
        tur: BildirimTur.uyari);
  }

  Future<void> _ac(Map<String, dynamic> n) async {
    final id = (n['id'] as num).toInt();
    if (n['read'] != true) BildirimMerkezi.okundu(id);
    final url = n['url']?.toString() ?? '';
    if (url.isNotEmpty) adreseGit(url);
  }

  List<(String, List<Map<String, dynamic>>)> _grupla(List<Map<String, dynamic>> l) {
    final out = <(String, List<Map<String, dynamic>>)>[];
    final simdi = DateTime.now();
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    for (final n in l) {
      final t = DateTime.tryParse(n['created_at']?.toString() ?? '')?.toLocal() ?? simdi;
      final g = DateTime(t.year, t.month, t.day);
      final fark = bugun.difference(g).inDays;
      final ad = fark == 0 ? 'Bugün' : fark == 1 ? 'Dün' : _gun.format(t);
      if (out.isNotEmpty && out.last.$1 == ad) {
        out.last.$2.add(n);
      } else {
        out.add((ad, [n]));
      }
    }
    return out;
  }

  ({Color zemin, Color renk}) _ton(BuildContext context, String tur) {
    final r = context.pa;
    return switch (tur) {
      'task_assigned' => (zemin: const Color(0xFF7C3AED).withValues(alpha: .14), renk: r.koyu ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED)),
      'shift_reminder' => (zemin: Marka.gok.withValues(alpha: .16), renk: r.koyu ? Marka.gok : const Color(0xFF0284C7)),
      'leave_decided' => (zemin: Marka.zumrut.withValues(alpha: .14), renk: r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
      'leave_requested' => (zemin: Marka.kehribar.withValues(alpha: .16), renk: const Color(0xFFB45309)),
      _ => (zemin: r.birincilYumusak, renk: r.birincil),
    };
  }

  IconData _ikon(String tur) => switch (tur) {
        'task_assigned' => Icons.assignment_rounded,
        'shift_reminder' => Icons.calendar_month_rounded,
        'leave_decided' || 'leave_requested' => Icons.beach_access_rounded,
        'staff_break' => Icons.coffee_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: BildirimMerkezi.liste,
      builder: (_, liste, _) => ValueListenableBuilder<int>(
        valueListenable: BildirimMerkezi.okunmamis,
        builder: (_, okunmamis, _) => PaSayfa(
          baslik: 'Bildirimler',
          altBaslik: okunmamis > 0 ? '$okunmamis okunmamış' : 'Hepsi okundu',
          yenile: _yenile,
          govde: Kaydir(altBosluk: 40, children: [
            ValueListenableBuilder<bool?>(
              valueListenable: BildirimMerkezi.izin,
              builder: (_, izin, _) => SatirGrubu([
                Satir(
                  ikon: izin == false ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                  grad: izin != false,
                  ikonZemin: izin == false ? const Color(0xFFFEE2E2) : null,
                  ikonRenk: izin == false ? const Color(0xFFDC2626) : null,
                  baslik: 'Anlık bildirimler',
                  alt: izin == true
                      ? 'Bu telefonda açık'
                      : izin == false
                          ? 'Kapalı · açmak için dokun'
                          : 'Denetleniyor…',
                  onTap: _izinIste,
                  sag: izin == true
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Marka.zumrut.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_rounded, color: Marka.zumrut, size: 16),
                            SizedBox(width: 4),
                            Text('Açık', style: TextStyle(color: Marka.zumrut, fontWeight: FontWeight.w700, fontSize: 12.5)),
                          ]),
                        )
                      : izin == false
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(8)),
                              child: const Text('Aç', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                            )
                          : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 4),
              child: Row(children: [
                Expanded(child: Text('Gelen kutusu', style: gosterim(18, renk: r.metin))),
                if (okunmamis > 0)
                  TextButton(
                    onPressed: () {
                      titret();
                      BildirimMerkezi.hepsiOkundu();
                    },
                    child: Text('Tümünü okundu say', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            if (_yukleniyor && liste.isEmpty)
              Column(children: [
                for (var i = 0; i < 4; i++)
                  const Padding(padding: EdgeInsets.only(top: 10), child: Iskelet(yukseklik: 64, radius: 20)),
              ])
            else if (liste.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: BosDurum(
                  ikon: Icons.notifications_none_rounded,
                  baslik: 'Bildirim yok',
                  aciklama: 'Görev, vardiya ve izin bildirimlerin burada toplanır.',
                ),
              )
            else
              for (final (gun, grup) in _grupla(liste)) ...[
                BolumBasligi(gun),
                SatirGrubu([
                  for (final n in grup) _satir(context, n),
                ]),
              ],
          ]),
        ),
      ),
    );
  }

  Widget _satir(BuildContext context, Map<String, dynamic> n) {
    final r = context.pa;
    final okundu = n['read'] == true;
    final tur = n['type']?.toString() ?? '';
    final ton = _ton(context, tur);
    final t = DateTime.tryParse(n['created_at']?.toString() ?? '')?.toLocal();
    final govde = n['body']?.toString();
    return Material(
      color: okundu ? Colors.transparent : r.birincilYumusak.withValues(alpha: r.koyu ? .5 : .55),
      child: InkWell(
        onTap: () {
          titret();
          _ac(n);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PaIkon(_ikon(tur), boyut: 40, zemin: ton.zemin, renk: ton.renk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(n['title']?.toString() ?? 'Bildirim',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: r.metin)),
                  ),
                  if (t != null) Text(_saat.format(t), style: TextStyle(fontSize: 11, color: r.silik)),
                ]),
                if (govde != null && govde.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(govde, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: r.soluk, height: 1.35)),
                  ),
              ]),
            ),
            if (!okundu)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 8, top: 6),
                decoration: BoxDecoration(
                  color: r.birincil,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Color(0xB35443D2), blurRadius: 8)],
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
