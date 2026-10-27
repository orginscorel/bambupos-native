import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/guncelleme.dart';
import '../core/konum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'bildirimler.dart';
import 'davet.dart';
import 'destek.dart';
import 'ekibim.dart';
import 'eslesme.dart';
import 'hedefler.dart';
import 'kabuk.dart';
import 'mesaim.dart';
import 'primler.dart';
import 'puantaj.dart';

/// PROFİLİM (sekme) — web Profile.vue karşılığı, Kardo düzeninde menü.
///
/// Avatar + ad/rol, menü satırları (kişisel/şirket bilgileri panoları,
/// hedef/prim/mesai/davet/bildirim/destek sayfaları), güvenlik (PIN, parola,
/// oturumlar), görünüm (açık/koyu/sistem) ve çıkış.
class ProfilEkrani extends StatefulWidget {
  const ProfilEkrani({super.key});
  @override
  State<ProfilEkrani> createState() => _ProfilEkraniState();
}

class _ProfilEkraniState extends State<ProfilEkrani> {
  String _surum = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _surum = '${p.version} (${p.buildNumber})');
    });
  }

  Map<String, dynamic> get _h => Uyg.hesap.value ?? const {};

  String get _rol {
    final p = _h['pozisyon']?.toString();
    if (p != null && p.isNotEmpty) return p;
    final r = (_h['roller'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return r.isEmpty ? 'Personel' : r.join(', ');
  }

  Future<void> _yenile() async {
    try {
      await Uyg.hesapYukle();
    } on ApiHata catch (e) {
      bildir('Yenilenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Uyg.hesap,
      builder: (_, _, _) => PaSayfa(
        baslik: 'Profilim',
        geri: false,
        yenile: _yenile,
        govde: Kaydir(children: [
          _kimlik(),
          const SizedBox(height: 18),
          if (Uyg.yonetici) ...[
            SatirGrubu([
              Satir(ikon: Icons.groups_rounded, baslik: 'Ekibim', alt: 'Ekip ve görevler', grad: true, onTap: () => git(context, const EkibimEkrani())),
            ]),
            const SizedBox(height: 14),
          ],
          SatirGrubu([
            Satir(ikon: Icons.person_rounded, baslik: 'Kişisel bilgiler', ikonZemin: const Color(0xFFFCE7F3), ikonRenk: const Color(0xFFDB2777), onTap: _kisisel),
            Satir(ikon: Icons.storefront_rounded, baslik: 'Şirket bilgileri', ikonZemin: const Color(0xFFDBEAFE), ikonRenk: Marka.mavi, onTap: _sirket),
            Satir(ikon: Icons.trending_up_rounded, baslik: 'Hedeflerim', ikonZemin: const Color(0xFFEDE9FE), ikonRenk: const Color(0xFF7C3AED), onTap: () => git(context, const HedeflerEkrani())),
            Satir(ikon: Icons.account_balance_wallet_rounded, baslik: 'Primlerim', ikonZemin: const Color(0xFFFEF3C7), ikonRenk: const Color(0xFFB45309), onTap: () => git(context, const PrimlerEkrani())),
            Satir(ikon: Icons.history_rounded, baslik: 'Mesai geçmişim', ikonZemin: const Color(0xFFD1FAE5), ikonRenk: const Color(0xFF047857), onTap: () => git(context, const MesaimEkrani())),
            Satir(ikon: Icons.receipt_long_rounded, baslik: 'Puantaj ve bordrom', ikonZemin: const Color(0xFFE0F2FE), ikonRenk: const Color(0xFF0284C7), onTap: () => git(context, const PuantajEkrani())),
          ]),
          const SizedBox(height: 14),
          SatirGrubu([
            Satir(
              ikon: Icons.auto_awesome_rounded,
              baslik: 'Davet et, kazan',
              alt: 'İşletme öner, abonelikten pay al',
              grad: true,
              onTap: () => git(context, const DavetEkrani()),
              sag: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: context.pa.birincilYumusak, borderRadius: BorderRadius.circular(20)),
                child: Text('Yeni', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.pa.birincil)),
              ),
            ),
            Satir(ikon: Icons.notifications_rounded, baslik: 'Bildirimler', ikonZemin: const Color(0xFFE0E7FF), ikonRenk: const Color(0xFF4338CA), onTap: () => git(context, const BildirimlerEkrani())),
            Satir(ikon: Icons.support_agent_rounded, baslik: 'Destek', ikonZemin: const Color(0xFFFFE4E6), ikonRenk: Marka.gul, onTap: () => git(context, const DestekEkrani())),
          ]),
          const BolumBasligi('Güvenlik ve cihaz'),
          SatirGrubu([
            const KonumSatiri(),
            Satir(
              ikon: Icons.pin_rounded,
              baslik: 'POS PIN',
              alt: _h['pin_var'] == true ? 'Tanımlı' : 'Henüz belirlenmedi',
              ikonZemin: const Color(0xFFFEF3C7),
              ikonRenk: const Color(0xFFD97706),
              onTap: _pin,
            ),
            Satir(ikon: Icons.lock_rounded, baslik: 'Parola', ikonZemin: const Color(0xFFFEE2E2), ikonRenk: const Color(0xFFDC2626), onTap: _parola),
            Satir(ikon: Icons.devices_rounded, baslik: 'Oturumlar', alt: 'Hesabının açık olduğu cihazlar', ikonZemin: const Color(0xFFE0F2FE), ikonRenk: const Color(0xFF0284C7), onTap: _oturumlar),
          ]),
          const BolumBasligi('Görünüm'),
          const _TemaSecici(),
          const SizedBox(height: 14),
          SatirGrubu([
            Satir(ikon: Icons.system_update_rounded, baslik: 'Uygulama güncellemesi', alt: _surum.isEmpty ? null : 'Yüklü sürüm $_surum', sag: const GuncellemeSatiriDurum(), onTap: guncellemeDenetle),
          ]),
          const SizedBox(height: 14),
          SatirGrubu([
            Satir(ikon: Icons.logout_rounded, baslik: 'Çıkış yap', baslikRenk: const Color(0xFFDC2626), ikonZemin: const Color(0xFFFEE2E2), ikonRenk: const Color(0xFFDC2626), onTap: _cikis),
          ]),
          const SizedBox(height: 18),
          Center(
            child: Column(children: [
              Opacity(opacity: .6, child: IconTheme(data: IconThemeData(color: context.pa.silik), child: const PaMark(boyut: 26, tek: true))),
              const SizedBox(height: 6),
              Text('BamBumPOS Personel${_surum.isEmpty ? '' : ' · $_surum'}', style: TextStyle(fontSize: 12, color: context.pa.silik)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _kimlik() {
    final r = context.pa;
    final isletme = _h['isletme']?.toString();
    return Column(children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: .3, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: Marka.grad,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: r.koyu ? Colors.white12 : Colors.white, width: 4),
            boxShadow: const [BoxShadow(color: Color(0x885443D2), blurRadius: 28, offset: Offset(0, 14), spreadRadius: -8)],
          ),
          alignment: Alignment.center,
          child: Text(Uyg.basHarfler, style: gosterim(32, renk: Colors.white)),
        ),
      ),
      const SizedBox(height: 12),
      Text(Uyg.ad.isEmpty ? 'Personel' : Uyg.ad, textAlign: TextAlign.center, style: gosterim(23, renk: r.metin)),
      const SizedBox(height: 2),
      Text('$_rol${isletme != null && isletme.isNotEmpty ? ' · $isletme' : ''}',
          textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 13.5, fontWeight: FontWeight.w500)),
    ]);
  }

  /* ───────────── Panolar ───────────── */

  Widget _bilgiSatiri(BuildContext ctx, String k, String? v, {bool ilk = false}) {
    final r = ctx.pa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(border: ilk ? null : Border(top: BorderSide(color: r.kenar))),
      child: Row(children: [
        Text(k, style: TextStyle(color: r.soluk, fontSize: 13.5)),
        const SizedBox(width: 12),
        Expanded(child: Text(v == null || v.isEmpty ? '—' : v, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: r.metin))),
      ]),
    );
  }

  Widget _bilgiKutusu(BuildContext ctx, List<(String, String?)> l) => Container(
        decoration: BoxDecoration(color: ctx.pa.ic, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [for (var i = 0; i < l.length; i++) _bilgiSatiri(ctx, l[i].$1, l[i].$2, ilk: i == 0)]),
      );

  void _kisisel() {
    final tel = TextEditingController(text: _h['telefon']?.toString() ?? '');
    var bekle = false;
    String? hata;
    panoAc(
      context,
      baslik: 'Kişisel bilgiler',
      alt: 'Ad ve soyad yöneticin tarafından belirlenir.',
      icerik: (ctx) => StatefulBuilder(
        builder: (ctx, ayarla) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _bilgiKutusu(ctx, [
            ('Ad soyad', Uyg.ad),
            ('E-posta', _h['eposta']?.toString()),
            ('Personel kodu', _h['personel_kodu']?.toString()),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: tel,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Telefon', helperText: 'İletişim için (isteğe bağlı)', errorText: hata, prefixIcon: const Icon(Icons.phone_rounded)),
          ),
          const SizedBox(height: 14),
          GradDugme(
            yazi: 'Kaydet',
            yukleniyor: bekle,
            onTap: () async {
              ayarla(() {
                bekle = true;
                hata = null;
              });
              try {
                await Uyg.api.put('/api/v1/portal/profile', {'phone': tel.text.trim()});
                await Uyg.hesapYukle();
                if (ctx.mounted) Navigator.pop(ctx);
                bildir('Bilgilerin güncellendi');
              } on ApiHata catch (e) {
                ayarla(() => hata = e.mesaj);
              } finally {
                if (ctx.mounted) ayarla(() => bekle = false);
              }
            },
          ),
        ]),
      ),
    );
  }

  void _sirket() {
    final g = DateTime.tryParse(_h['ise_giris']?.toString() ?? '');
    panoAc(
      context,
      baslik: 'Şirket bilgileri',
      icerik: (ctx) => _bilgiKutusu(ctx, [
        ('İşletme', _h['isletme']?.toString()),
        ('Şube', _h['sube']?.toString()),
        ('Görev', _rol),
        if ((_h['departman']?.toString() ?? '').isNotEmpty) ('Departman', _h['departman']?.toString()),
        if (g != null) ('İşe giriş', DateFormat('d MMMM y', 'tr_TR').format(g)),
      ]),
    );
  }

  Map<String, String> _hatalar(ApiHata e) {
    final m = <String, String>{};
    final h = e.govde?['errors'];
    if (h is Map) h.forEach((k, v) => m[k.toString()] = v is List && v.isNotEmpty ? v.first.toString() : v.toString());
    return m;
  }

  void _pin() {
    final pinVar = _h['pin_var'] == true;
    final mevcut = TextEditingController();
    final yeni = TextEditingController();
    var bekle = false;
    var h = <String, String>{};
    panoAc(
      context,
      baslik: 'POS PIN',
      alt: pinVar ? 'Değiştirmek için mevcut PIN’ini gir.' : 'Kasada hızlı giriş için PIN belirle.',
      icerik: (ctx) => StatefulBuilder(
        builder: (ctx, ayarla) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (pinVar) ...[
            TextField(controller: mevcut, obscureText: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Mevcut PIN', errorText: h['current_pin'])),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: yeni,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Yeni PIN', helperText: 'Ardışık ya da tekrar eden rakam olamaz', errorText: h['pin']),
          ),
          const SizedBox(height: 16),
          GradDugme(
            yazi: pinVar ? 'PIN’i değiştir' : 'PIN belirle',
            ikon: Icons.pin_rounded,
            yukleniyor: bekle,
            onTap: () async {
              ayarla(() {
                bekle = true;
                h = {};
              });
              try {
                await Uyg.api.put('/api/v1/portal/profile/pin', {'current_pin': mevcut.text, 'pin': yeni.text});
                await Uyg.hesapYukle();
                if (ctx.mounted) Navigator.pop(ctx);
                bildir('PIN kaydedildi');
              } on ApiHata catch (e) {
                final m = _hatalar(e);
                if (m.isEmpty) bildir('PIN kaydedilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
                ayarla(() => h = m);
              } finally {
                if (ctx.mounted) ayarla(() => bekle = false);
              }
            },
          ),
        ]),
      ),
    );
  }

  void _parola() {
    final mevcut = TextEditingController();
    final yeni = TextEditingController();
    final tekrar = TextEditingController();
    var bekle = false;
    var gizli = true;
    var h = <String, String>{};
    panoAc(
      context,
      baslik: 'Parola',
      alt: 'Güvenliğin için düzenli olarak değiştir.',
      icerik: (ctx) => StatefulBuilder(builder: (ctx, ayarla) {
        Widget alan(TextEditingController c, String etiket, String anahtar, {String? yardim}) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: c,
                obscureText: gizli,
                decoration: InputDecoration(
                  labelText: etiket,
                  helperText: yardim,
                  errorText: h[anahtar],
                  suffixIcon: IconButton(icon: Icon(gizli ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => ayarla(() => gizli = !gizli)),
                ),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          alan(mevcut, 'Mevcut parola', 'current_password'),
          alan(yeni, 'Yeni parola', 'password', yardim: 'En az 8 karakter'),
          alan(tekrar, 'Yeni parola (tekrar)', 'password_confirmation'),
          const SizedBox(height: 4),
          GradDugme(
            yazi: 'Parolayı değiştir',
            ikon: Icons.lock_reset_rounded,
            yukleniyor: bekle,
            onTap: () async {
              ayarla(() {
                bekle = true;
                h = {};
              });
              try {
                await Uyg.api.put('/api/v1/auth/password', {
                  'current_password': mevcut.text,
                  'password': yeni.text,
                  'password_confirmation': tekrar.text,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                bildir('Parolan güncellendi');
              } on ApiHata catch (e) {
                final m = _hatalar(e);
                if (m.isEmpty) bildir('Parola değiştirilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
                ayarla(() => h = m);
              } finally {
                if (ctx.mounted) ayarla(() => bekle = false);
              }
            },
          ),
        ]);
      }),
    );
  }

  void _oturumlar() {
    panoAc(context, baslik: 'Oturumlar', alt: 'Hesabının açık olduğu cihazlar.', icerik: (_) => const _OturumListesi());
  }

  Future<void> _cikis() async {
    final onay = await panoAc<bool>(
      context,
      baslik: 'Çıkış yapılsın mı?',
      alt: 'Tekrar girmek için telefonu yeniden eşlemen ya da parolanla girmen gerekir.',
      icerik: (ctx) => Row(children: [
        Expanded(child: YumusakDugme(yazi: 'Vazgeç', onTap: () => Navigator.pop(ctx, false), zemin: ctx.pa.ic, renk: ctx.pa.metin)),
        const SizedBox(width: 10),
        Expanded(child: YumusakDugme(yazi: 'Çıkış yap', ikon: Icons.logout_rounded, onTap: () => Navigator.pop(ctx, true), zemin: const Color(0xFFDC2626), renk: Colors.white)),
      ]),
    );
    if (onay != true) return;
    titret(2);
    await Uyg.cikis();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(HizliRota(builder: (_) => const EslesmeEkrani()), (_) => false);
  }
}

/* ───────────── Tema seçici (Açık / Koyu / Sistem) ───────────── */

class _TemaSecici extends StatelessWidget {
  const _TemaSecici();
  static const _ogeler = [
    (ThemeMode.light, Icons.light_mode_rounded, 'Açık'),
    (ThemeMode.dark, Icons.dark_mode_rounded, 'Koyu'),
    (ThemeMode.system, Icons.phone_iphone_rounded, 'Sistem'),
  ];

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: temaKipi,
      builder: (_, kip, _) {
        final secili = _ogeler.indexWhere((o) => o.$1 == kip);
        return Container(
          height: 58,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(20), border: Border.all(color: r.kenar), boxShadow: r.golge),
          child: LayoutBuilder(builder: (_, k) {
            final w = k.maxWidth / 3;
            // fit: expand → yazılar kutunun DİKEY ORTASINDA (eskiden üste yapışıktı)
            return Stack(fit: StackFit.expand, children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                left: w * secili,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(15),
                    boxShadow: const [BoxShadow(color: Color(0x665443D2), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -6)])),
              ),
              Row(children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        titret();
                        Uyg.temaDegistir(_ogeler[i].$1);
                      },
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_ogeler[i].$2, size: 18, color: i == secili ? Colors.white : r.soluk),
                        const SizedBox(width: 6),
                        Text(_ogeler[i].$3, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: i == secili ? Colors.white : r.soluk)),
                      ]),
                    ),
                  ),
              ]),
            ]);
          }),
        );
      },
    );
  }
}

/* ───────────── Oturumlar listesi (pano içi) ───────────── */

class _OturumListesi extends StatefulWidget {
  const _OturumListesi();
  @override
  State<_OturumListesi> createState() => _OturumListesiState();
}

class _OturumListesiState extends State<_OturumListesi> {
  final _fmt = DateFormat('d MMM HH:mm', 'tr_TR');
  List<Map> _l = [];
  bool _yuk = true;
  final _parola = TextEditingController();
  String? _hata;
  bool _bekle = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _parola.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/auth/sessions');
      final l = r is Map ? (r['sessions'] ?? r['data']) : r;
      if (mounted) setState(() => _l = (l is List ? l : const []).whereType<Map>().toList());
    } on ApiHata {
      // Liste gösterilemezse yalnız çıkış formu kalır.
    } finally {
      if (mounted) setState(() => _yuk = false);
    }
  }

  String _cihaz(String? ua) {
    final s = (ua ?? '').toLowerCase();
    if (s.contains('bambumpos-personel')) return 'BamBumPOS Personel uygulaması';
    if (s.contains('iphone')) return 'iPhone';
    if (s.contains('ipad')) return 'iPad';
    if (s.contains('android')) return 'Android';
    if (s.contains('windows')) return 'Windows bilgisayar';
    if (s.contains('mac')) return 'Mac';
    return ua == null || ua.isEmpty ? 'Bilinmeyen cihaz' : ua.split(' ').first;
  }

  Future<void> _digerleri() async {
    setState(() {
      _bekle = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/auth/logout-other-devices', {'password': _parola.text});
      _parola.clear();
      bildir('Diğer cihazlardaki oturumlar kapatıldı');
      await _yukle();
    } on ApiHata catch (e) {
      final h = e.govde?['errors'];
      setState(() => _hata = h is Map && h['password'] is List ? (h['password'] as List).first.toString() : e.mesaj);
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_yuk)
        for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: 8), child: Iskelet(yukseklik: 58, radius: 18))
      else
        for (final s in _l)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const PaIkon(Icons.devices_rounded, boyut: 38, zemin: Color(0xFFE0F2FE), renk: Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(_cihaz(s['user_agent']?.toString()), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: r.metin))),
                    if (s['current'] == true) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Marka.zumrut.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                        child: const Text('Bu cihaz', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Marka.zumrut)),
                      ),
                    ],
                  ]),
                  Text(
                    '${s['ip_address'] ?? ''}${s['ip_address'] != null ? ' · ' : ''}${DateTime.tryParse(s['last_activity']?.toString() ?? '') == null ? '—' : _fmt.format(DateTime.parse(s['last_activity'].toString()).toLocal())}',
                    style: TextStyle(fontSize: 12, color: r.soluk),
                  ),
                ]),
              ),
            ]),
          ),
      const SizedBox(height: 8),
      TextField(
        controller: _parola,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'Parola', helperText: 'Diğer cihazlardaki oturumları kapatmak için', errorText: _hata),
      ),
      const SizedBox(height: 12),
      GradDugme(
        yazi: 'Diğer cihazlardan çık',
        ikon: Icons.phonelink_erase_rounded,
        yukleniyor: _bekle,
        gradient: const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFDC2626)]),
        onTap: _parola.text.isEmpty ? null : _digerleri,
      ),
    ]);
  }
}
