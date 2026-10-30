import 'dart:io';

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/ajan.dart';
import '../core/api.dart';
import '../core/modeller.dart';
import 'cerceve.dart';
import 'borclar_ekrani.dart';
import 'gecmis_ekrani.dart';
import 'gorevler_ekrani.dart';
import 'giderler_ekrani.dart';
import 'guncelleme.dart';
import 'gun_sonu_ekrani.dart';
import 'kasa_ekrani.dart';
import 'kasa_kapanisi.dart';
import 'kds_ekrani.dart';
import 'masa_panosu.dart';
import 'masalar_ekrani.dart';
import 'mesailer_ekrani.dart';
import 'mesai_qr_ekrani.dart';
import 'raporlar_ekrani.dart';
import 'self_ekrani.dart';
import 'teslimat_ekrani.dart';
import 'usb_cihazlar.dart';
import 'ortak.dart';

/// Panelin OPERASYON ekranları — web resources/js/config/navigation.ts ile
/// AYNI sıra, anahtar, yol, izin, istasyon ve özellik bayrağı. Yönetim
/// ekranları (Menü, Stok, Personel, Ayarlar, Rezervasyon …) bilerek
/// yok — onlar İşletme Yönetimi'nde (kullanıcı kararı 2026-10-26).
/// Raporlar 2026-10-27'de sahip isteğiyle POS'a eklendi.
enum PosEkrani {
  siparis('orders', 'Siparişler', 'Sipariş girişi ekranı', Icons.content_paste_rounded, '/panel/siparisler', izin: 'orders.view'),
  gecmis('orders-gecmis', 'Önceki adisyonlar', 'Önceki adisyonlar', Icons.history_rounded, '/panel/siparisler/gecmis', izin: 'orders.view'),
  masalar('tables', 'Masalar', 'Masalar', Icons.qr_code_2_rounded, '/panel/masalar', izin: 'tables.view'),
  kasa('cashier', 'Kasa', 'Kasa ekranı', Icons.shopping_cart_outlined, '/panel/kasa', izin: 'payments.take', para: true),
  kasaKapanis('cash-desk', 'Kasa Kapanışı', 'Kasa kapanışı', Icons.account_balance_wallet_outlined, '/panel/kasa/yonetim', izin: 'cash.view', para: true),
  mutfak('kds', 'Mutfak', 'Mutfak ekranı', Icons.soup_kitchen_outlined, '/panel/mutfak',
      izin: 'kds.view', istasyonlar: ['kitchen'], ozellik: 'hazirlik_takibi', serit: 'kitchen'),
  barista('barista', 'Barista', 'Barista ekranı', Icons.coffee_outlined, '/panel/barista',
      izin: 'kds.view', istasyonlar: ['barista'], ozellik: 'hazirlik_takibi', serit: 'barista'),
  nargile('nargile', 'Nargile', 'Nargile ekranı', Icons.local_fire_department_outlined, '/panel/nargile',
      izin: 'kds.view', istasyonlar: ['hookah'], ozellik: 'nargile', serit: 'nargile'),
  komi('runner', 'Komi', 'Servis ekranı', Icons.notifications_none_rounded, '/panel/komi', izin: 'kds.deliver', ozellik: 'hazirlik_takibi'),
  teslimat('delivery', 'Teslimat', 'Teslimat', Icons.local_shipping_outlined, '/panel/teslimat', izin: 'delivery.view', ozellik: 'delivery'),
  /// SELF SATIŞ (2026-10-30): gel-al / telefon siparişleri — yalnız eklentisi açık işletmede.
  self('self', 'Self Satış', 'Self satış', Icons.shopping_bag_outlined, '/panel/self', izin: 'orders.view', ozellik: 'self_satis'),
  gorevler('tasks', 'Görevler', 'Görevler', Icons.assignment_outlined, '/panel/gorevler', izin: 'tasks.view'),
  mesailer('mesailer', 'Mesailer', 'Mesailer', Icons.schedule_rounded, '/panel/mesai', izin: 'staff.view', ozellik: 'shifts'),
  /// Tüm personel: mesai başlatmak yetki değil zorunluluk (web ile aynı karar).
  mesaiQr('mesai-qr', 'Mesai / mola QR', 'Mesai QR', Icons.schedule_rounded, '/panel/mesai-qr', izin: null, ozellik: 'shifts'),
  borclar('receivables', 'Borçlar / Şahıslar', 'Borçlar / Şahıslar', Icons.inbox_outlined, '/panel/borclar', izin: 'receivables.view', ozellik: 'receivables', para: true),
  giderler('expenses', 'Giderler', 'Giderler', Icons.receipt_outlined, '/panel/gelir-gider', izin: 'cash.close', para: true),
  gunSonu('eod', 'Gün Sonu', 'Gün sonu', Icons.assignment_outlined, '/panel/gun-sonu', izin: 'reports.view', para: true),
  raporlar('reports', 'Raporlar', 'Raporlar', Icons.bar_chart_rounded, '/panel/raporlar', izin: 'reports.view', para: true);

  const PosEkrani(this.anahtar, this.etiket, this.rozet, this.ikon, this.yol,
      {required this.izin, this.istasyonlar = const [], this.ozellik, this.serit, this.para = false});
  final String anahtar;
  final String etiket;
  final String rozet;
  final IconData ikon;
  final String yol;
  final String? izin;
  final List<String> istasyonlar;
  final String? ozellik;

  /// KDS ekranının kulvarı (kitchen / barista / nargile).
  final String? serit;

  /// Tutar gösteren ekran: para görmeyen istasyonda (mutfak/komi) sunucu
  /// da açmaz (TerminalStation::showsMoney).
  final bool para;

  static PosEkrani? yoldan(String yol) {
    final y = yol.split('?').first.replaceAll(RegExp(r'/+$'), '');
    for (final e in values) {
      if (e.yol == y) return e;
    }
    return null;
  }
}

/// usePanelNav CEKMECE_GIZLI_ANAHTAR: "Tümü" kutusunda görünmeyenler
/// (şeritte kısayolu olan ya da yönetimde duran bölümler).
const _cekmeceGizli = {'inventory', 'wifi', 'discounts', 'catalog', 'runner', 'barista', 'kds', 'tables', 'staff', 'shifts', 'tasks', 'mesailer', 'settings'};

/// Cihazın istasyonu → açılışta gelen ana ekran.
PosEkrani anaEkran(Oturum o) => switch (o.istasyon) {
      'kasa' => PosEkrani.kasa,
      'kitchen' => PosEkrani.mutfak,
      'barista' => PosEkrani.barista,
      'nargile' => PosEkrani.nargile,
      'komi' => PosEkrani.komi,
      _ => PosEkrani.siparis,
    };

/// usePanelNav süzgeci birebir: izin → istasyon kapsamı → özellik bayrağı.
bool ekranGorunur(Oturum o, PosEkrani e) {
  if (e.izin != null && !o.yetki(e.izin!)) return false;
  final ist = o.istasyonlar;
  if (e.istasyonlar.isNotEmpty && ist.isNotEmpty && !e.istasyonlar.any(ist.contains)) return false;
  if (e.ozellik != null && !o.eklenti(e.ozellik!)) return false;
  if (e.para && !o.paraGorur) return false;
  return true;
}

/// Açılabilir ekranlar: cihazın ana ekranı + kişinin görebildikleri.
List<PosEkrani> ekranlariHesapla(Oturum o) {
  final ana = anaEkran(o);
  return [ana, ...PosEkrani.values.where((e) => e != ana && ekranGorunur(o, e))];
}

/// "Tümü" kutusu: web çekmecesi (aynı sıra, gizli anahtarlar hariç).
List<PosEkrani> cekmeceEkranlari(Oturum o) =>
    PosEkrani.values.where((e) => ekranGorunur(o, e) && !_cekmeceGizli.contains(e.anahtar)).toList();

/// Başka bir ekrandan (ör. adisyon "Kasaya git") kabuğa ekran değiştirme isteği.
final ekranIstegi = ValueNotifier<PosEkrani?>(null);

/// Web PanelSeritHost: tüm POS ekranlarında ortak alt şerit (kısayollar,
/// "Tümü" kutusu, kişi menüsü, cihaz durumu). Künye/kısayollar sunucudan.
Widget posAltSerit(BuildContext context, {required PosEkrani? secili, required void Function(PosEkrani) git}) {
  final durum = context.durum;
  final o = durum.oturum!;
  final ekranlar = ekranlariHesapla(o);
  final kim = o.seritKimlik;
  final kisi = (kim['kisi'] as String?) ?? o.operatorAd;
  final rol = (kim['rol'] as String?) ?? o.operatorRol;
  final sube = (kim['sube'] as String?) ?? o.sube;

  final kisayollar = <SeritKisayol>[];
  for (final k in o.seritKisayol) {
    final hedef = PosEkrani.yoldan('${k['yol'] ?? ''}');
    if (hedef == null || !ekranlar.contains(hedef)) continue;
    kisayollar.add(SeritKisayol(
      ad: '${k['ad'] ?? hedef.etiket}',
      kisa: '${k['kisa'] ?? k['ad'] ?? hedef.etiket}',
      ikon: k['ikon'] is String ? webSimge(k['ikon'] as String) : hedef.ikon,
      renk: k['renk'] as String?,
      secili: hedef == secili,
      bas: () => git(hedef),
    ));
  }
  final cekmece = cekmeceEkranlari(o);

  return AltCubuk(
    isletme: (kim['isletme'] as String?) ?? o.isletme,
    cihaz: (kim['cihaz'] as String?) ?? '${o.cihazAd} · ${platformAdi()}',
    kisi: kisi,
    rol: rol,
    kisiMenusu: (_) => KisiMenusuIci(
      ad: kisi,
      rol: rol,
      alt: [o.isletme, sube ?? ''].where((s) => s.isNotEmpty).join(' · '),
      personelDegistir: durum.kilitle,
    ),
    kisayollar: kisayollar,
    tumu: cekmece.isEmpty
        ? null
        : () => tumBolumlerAc(context, [
              for (final e in cekmece) CekmeceOgesi(ad: e.etiket, ikon: e.ikon, secili: e == secili, bas: () => git(e)),
            ]),
    cihazlar: [
      _internetOgesi(),
      if (durum.ajan != null) _ajanOgesi(durum.ajan!),
      if (durum.ajan?.usbDestekli ?? false) _usbOgesi(durum.ajan!, () => usbCihazlarAc(context, durum.ajan!)),
      for (final c in o.seritCihaz)
        _sunucuCihazi(c, mesaiQrAc: ekranlar.contains(PosEkrani.mesaiQr) ? () => git(PosEkrani.mesaiQr) : null),
    ],
    // Uygulamanın kendi sürümü; dokununca sürüm notları (uygulama + panel).
    surum: durum.surum,
  );
}

/* ───────── Alt şerit cihaz simgeleri ───────── */

String _onceSure(DateTime? t) {
  if (t == null) return '—';
  final f = DateTime.now().difference(t);
  if (f.inSeconds < 60) return '${f.inSeconds < 1 ? 1 : f.inSeconds} sn önce';
  if (f.inMinutes < 60) return '${f.inMinutes} dk önce';
  if (f.inHours < 24) return '${f.inHours} sa önce';
  return '${f.inDays} gün önce';
}

SeritCihaz _internetOgesi() {
  SeritCihaz olustur() {
    final b = sunucuBagli.value;
    return SeritCihaz(
      ad: 'İnternet',
      ikon: b ? Icons.public_rounded : Icons.public_off_rounded,
      durum: b ? 'iyi' : 'kopuk',
      balon: b ? 'Sunucuya bağlı' : 'Sunucuya ulaşılamıyor',
      aciklama: 'Uygulamanın BamBumPOS sunucusuyla bağlantısı. Siparişler, masalar ve ödemeler '
          'anında sunucuya kaydedilir ve diğer cihazlarda görünür. Bağlantı koparsa yeni işlem '
          'kaydedilemez; Wi-Fi veya mobil veriyi kontrol edin.',
      ayrintilar: [('Son yanıt', _onceSure(sunucuSonYanit))],
    );
  }

  return SeritCihaz(ad: 'İnternet', ikon: Icons.public_rounded, balon: '', dinle: sunucuBagli, canli: olustur);
}

SeritCihaz _ajanOgesi(YazdirmaAjani a) {
  SeritCihaz olustur() {
    final d = a.durum;
    final iyi = d.startsWith('Bağlı');
    final calisiyor = d.contains('taranıyor') || d == 'Bekliyor';
    return SeritCihaz(
      ad: 'Yazdırma ajanı',
      ikon: Icons.wifi_tethering_rounded,
      durum: iyi ? 'iyi' : (calisiyor ? 'uyari' : 'kopuk'),
      balon: d,
      aciklama: 'Bu cihaz, işletmenin yerel ağındaki fiş yazıcılarını ve POS / ÖKC cihazlarını '
          'bulur ve İşletme Yönetimi › Yazıcılar sayfasına bildirir. Ağ yazıcısına giden '
          'fişleri (mutfak, hesap) de bu cihaz basar.',
      ayrintilar: [
        ('Ağda bulunan yazıcı', '${a.bulunanYazicilar.length}'),
        ('Ağda bulunan POS / ÖKC', '${a.bulunanPos.length}'),
        ('Son tarama', _onceSure(a.sonTarama)),
        ('Bu açılışta basılan fiş', '${a.basilanFis}'),
        ('USB cihazlar', a.usbDestekli ? '${a.usbCihazlar.length}' : (Platform.isIOS ? 'iOS\'ta USB cihaz desteklenmez' : '—')),
      ],
      eylem: (ad: 'Ağı şimdi tara', bas: a.tara, kapat: false),
    );
  }

  return SeritCihaz(ad: 'Yazdırma ajanı', ikon: Icons.wifi_tethering_rounded, balon: '', dinle: a, canli: olustur);
}

SeritCihaz _usbOgesi(YazdirmaAjani a, VoidCallback ac) {
  SeritCihaz olustur() {
    final l = a.usbCihazlar;
    final izin = l.where((c) => c.izinGerekli).length;
    final yeni = l.where((c) => c.tur != 'bilinmiyor' && !a.usbBilinen(c)).length;
    return SeritCihaz(
      ad: 'USB cihazlar',
      ikon: Icons.usb_rounded,
      durum: a.usbHata != null || izin > 0 ? 'uyari' : 'iyi',
      balon: a.usbHata ??
          (l.isEmpty
              ? 'Bağlı USB yazıcı / POS yok'
              : [
                  '${l.length} USB cihaz',
                  if (izin > 0) '$izin izin bekliyor',
                  if (yeni > 0) '$yeni eklenmedi',
                ].join(' · ')),
      aciklama: 'Bu cihaza USB kablosuyla takılı fiş yazıcıları ve kart POS cihazları. Takılan cihaz '
          'kendiliğinden bulunur ve İşletme Yönetimi\'ne bildirilir; USB yazıcıya giden fişleri bu cihaz basar.',
      ayrintilar: [
        ('USB yazıcı', '${l.where((c) => c.tur == 'yazici').length}'),
        ('USB kart POS', '${l.where((c) => c.tur == 'pos').length}'),
        ('Son tarama', _onceSure(a.usbSonTarama)),
      ],
      eylem: (ad: 'USB cihazları yönet', bas: ac, kapat: true),
    );
  }

  return SeritCihaz(ad: 'USB cihazlar', ikon: Icons.usb_rounded, balon: '', dinle: a, canli: olustur);
}

SeritCihaz _sunucuCihazi(Json c, {VoidCallback? mesaiQrAc}) {
  final tur = '${c['ikon'] ?? ''}';
  final iyi = c['iyi'] != false;
  final (aciklama, eylem) = switch (tur) {
    'printer' || 'yazici' => (
        'İşletmede tanımlı fiş ve mutfak yazıcıları. Siparişler ilgili istasyonun yazıcısına, '
            'hesap fişi kasa yazıcısına gider. Sarı yanıyorsa en az bir yazıcı son işte hata '
            'verdi: kağıdı, gücü ve kabloyu / ağ bağlantısını kontrol edin.',
        null,
      ),
    'tablet' || 'terminal' => (
        'İşletmeye eşlenmiş POS uygulamaları (tablet, telefon, bilgisayar). Personel kendi '
            'PIN\'iyle girip sipariş alır; cihazlar İşletme Yönetimi › Cihazlar\'dan yönetilir.',
        null,
      ),
    'clock' || 'mesaiqr' => (
        'Personelin telefonuyla okutarak mesaiye giriş / çıkış yaptığı ve molaya çıktığı QR '
            'ekranları. Kod birkaç saniyede bir değişir, ekran fotoğrafıyla giriş yapılamaz.',
        mesaiQrAc == null ? null : (ad: 'Mesai / mola QR ekranını aç', bas: mesaiQrAc, kapat: true),
      ),
    _ => (null, null),
  };
  return SeritCihaz(
    ad: '${c['ad'] ?? ''}',
    ikon: webSimge((c['panelIkon'] ?? c['ikon']) as String?),
    balon: '${c['balon'] ?? ''}',
    durum: iyi ? 'iyi' : 'uyari',
    aciklama: aciklama,
    eylem: eylem,
  );
}

class Kabuk extends StatefulWidget {
  const Kabuk({super.key});

  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> {
  PosEkrani? _secili;

  /// Sekme geçiş yönü: sağdaki sekmeye geçince yeni ekran sağdan gelir.
  int _yon = 1;

  void _git(PosEkrani e) {
    final l = ekranlariHesapla(context.durum.oturum!);
    final simdi = l.indexOf(l.contains(_secili) ? _secili! : l.first);
    final yeni = l.indexOf(e);
    if (yeni >= 0 && simdi >= 0 && yeni != simdi) _yon = yeni > simdi ? 1 : -1;
    setState(() => _secili = e);
  }

  void _istek() {
    final e = ekranIstegi.value;
    if (e == null) return;
    ekranIstegi.value = null;
    _git(e);
  }

  late final _bildirim = context.durum.bildirim;
  late final _senkron = context.durum.senkron;

  @override
  void initState() {
    super.initState();
    ekranIstegi.addListener(_istek);
    _bildirim
      ..adresAc = _adresAc
      ..baslat();
    _senkron.baslat();
  }

  /// Bildirimin adresi bir POS ekranıysa oraya geç (açık adisyonu kapatarak).
  void _adresAc(String adres) {
    final yol = Uri.tryParse(adres)?.path ?? adres;
    final e = PosEkrani.yoldan(yol);
    if (!mounted || e == null || !ekranlariHesapla(context.durum.oturum!).contains(e)) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _git(e);
  }

  @override
  void dispose() {
    ekranIstegi.removeListener(_istek);
    _bildirim
      ..adresAc = null
      ..durdur();
    _senkron.durdur();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durum = context.durum;

    return ListenableBuilder(
      listenable: durum,
      builder: (context, _) {
        final o = durum.oturum!;
        final ekranlar = ekranlariHesapla(o);
        final ekran = ekranlar.contains(_secili) ? _secili! : ekranlar.first;
        final sube = (o.seritKimlik['sube'] as String?) ?? o.sube;

        return Scaffold(
          appBar: UstCubuk(
            baslik: o.isletme,
            altSatir: [sube ?? '', o.isletmeKod].where((s) => s.isNotEmpty).join(' · '),
            rozet: ekran.rozet,
            zil: true,
          ),
          bottomNavigationBar: posAltSerit(context, secili: ekran, git: _git),
          body: Column(children: [
            const GuncellemeSeridi(),
            if (durum.ajan?.usbDestekli ?? false) UsbBulunduSeridi(ajan: durum.ajan!),
            Expanded(child: EkranGecisi(anahtar: ekran, yon: _yon, child: _govde(ekran))),
          ]),
        );
      },
    );
  }

  Widget _govde(PosEkrani e) => switch (e) {
        PosEkrani.siparis => const MasaPanosu(),
        PosEkrani.kasa => const KasaEkrani(),
        PosEkrani.masalar => const MasalarEkrani(),
        PosEkrani.mutfak || PosEkrani.barista || PosEkrani.nargile => KdsEkrani(kip: 'kitchen', serit: e.serit),
        PosEkrani.komi => const KdsEkrani(kip: 'runner'),
        PosEkrani.gecmis => const GecmisEkrani(),
        PosEkrani.kasaKapanis => const KasaKapanisiEkrani(),
        PosEkrani.teslimat => const TeslimatEkrani(),
        PosEkrani.self => const SelfEkrani(),
        PosEkrani.borclar => const BorclarEkrani(),
        PosEkrani.giderler => const GiderlerEkrani(),
        PosEkrani.gunSonu => const GunSonuEkrani(),
        PosEkrani.raporlar => const RaporlarEkrani(),
        PosEkrani.mesaiQr => const MesaiQrEkrani(),
        PosEkrani.gorevler => const GorevlerEkrani(),
        PosEkrani.mesailer => const MesailerEkrani(),
      };
}
