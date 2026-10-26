import 'bicim.dart';

typedef Json = Map<String, dynamic>;

Json _json(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Json> _liste(Object? v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];
String? _metin(Object? v) => v?.toString();

/* ───────────── Oturum ───────────── */

class Oturum {
  Oturum(this.ham);
  final Json ham;

  Json get _cihaz => _json(ham['cihaz']);
  int get cihazId => tamSayi(_cihaz['id']);
  String get cihazAd => _metin(_cihaz['ad']) ?? 'Cihaz';
  String get istasyon => _metin(_cihaz['istasyon']) ?? '';
  String get istasyonEtiket => _metin(_cihaz['istasyon_etiket']) ?? istasyon;
  bool get paraGorur => _cihaz['para'] == true;
  bool get kilitli => _cihaz['kilitli'] == true;

  String get isletme => _metin(_json(ham['isletme'])['ad']) ?? '';
  String get isletmeKod => _metin(_json(ham['isletme'])['kod']) ?? '';
  String? get sube => _metin(_json(ham['sube'])['ad']);
  int get subeId => tamSayi(_json(ham['sube'])['id']);

  Json? get _operator => ham['operator'] is Map ? _json(ham['operator']) : null;
  bool get operatorVar => _operator != null;
  String get operatorAd => _metin(_operator?['name']) ?? '';
  String get operatorRol => _metin(_operator?['rol']) ?? '';

  late final Set<String> yetkiler =
      (ham['yetkiler'] is List ? (ham['yetkiler'] as List).map((e) => e.toString()) : const <String>[]).toSet();

  bool yetki(String anahtar) => yetkiler.contains(anahtar);
  bool get carilerAcik => _json(ham['ozellikler'])['cariler'] == true;

  /// İşletme Yönetimi › Eklentiler. Liste hiç gelmediyse (eski sunucu)
  /// varsayılan AÇIK sayılır — sunucu zaten kapalı özelliğin verisini vermez.
  bool eklenti(String anahtar, {bool varsayilan = true}) {
    final e = ham['eklentiler'];
    if (e is! Map || !e.containsKey(anahtar)) return varsayilan;
    return e[anahtar] == true;
  }

  /// Sunucu saati ile cihaz saati arasındaki fark (süre rozetleri doğru olsun).
  Duration get saatFarki {
    final t = DateTime.tryParse(_metin(ham['sunucu_saati']) ?? '');
    return t == null ? Duration.zero : t.difference(DateTime.now());
  }
}

/* ───────────── Pano ───────────── */

class AdisyonOzet {
  AdisyonOzet(this.ham);
  final Json ham;

  int get id => tamSayi(ham['id']);
  int get surum => tamSayi(ham['version']);
  String? get masaAdi => _metin(ham['table_name']);
  String? get cariAdi => _metin(ham['receivable_name']);
  String get kanal => _metin(ham['channel']) ?? 'table';
  String get kanalEtiket => _metin(ham['channel_label']) ?? '';
  String get durum => _metin(ham['status']) ?? '';
  String get durumEtiket => _metin(ham['status_label']) ?? '';
  bool get acik => ham['is_open'] == true;
  int get kalemSayisi => tamSayi(ham['items_count']);
  int get servisEdilen => tamSayi(ham['served_count']);
  String get kaynakEtiket => _metin(ham['source_label']) ?? '';
  String get servisTuruEtiket => _metin(ham['service_type_label']) ?? '';
  String get servisTuru => _metin(ham['service_type']) ?? '';
  String get odemeDurumu => _metin(ham['payment_state']) ?? 'unpaid';
  String get odemeEtiket => _metin(ham['payment_label']) ?? '';
  List<String> get bagliMasalar => (ham['linked_table_names'] is List) ? (ham['linked_table_names'] as List).map((e) => e.toString()).toList() : const [];
  int get toplam => tamSayi(ham['total_minor']);
  int get odenen => tamSayi(ham['paid_minor']);
  int get kalan => tamSayi(ham['remaining_minor']);
  int get araToplam => tamSayi(ham['items_total_minor']);
  int get indirim => tamSayi(ham['discount_minor']) + tamSayi(ham['iskonto_minor']);
  int get ikram => tamSayi(ham['comp_total_minor']);
  int get servisUcreti => tamSayi(ham['service_charge_minor']);
  int get yuvarlama => tamSayi(ham['rounding_minor']);
  int? get kisi => ham['guest_count'] == null ? null : tamSayi(ham['guest_count']);
  String? get not => _metin(ham['note']);
  String? get musteri => _metin(ham['customer_name']);
  String? get acan => _metin(ham['opened_by']);
  String? get acilis => _metin(ham['placed_at']) ?? _metin(ham['created_at']);
  bool get hesapIstendi => durum == 'bill_requested';
  bool get onayBekliyor => durum == 'pending_approval';

  String get baslik => masaAdi ?? cariAdi ?? musteri ?? (kanalEtiket.isNotEmpty ? '$kanalEtiket #$id' : 'Adisyon #$id');
}

class Masa {
  Masa(this.ham);
  final Json ham;

  int get id => tamSayi(ham['id']);
  String get ad => _metin(ham['name']) ?? '';
  String get alan => _metin(ham['area_name']) ?? 'Salon';
  int? get numara => ham['number'] == null ? null : tamSayi(ham['number']);
  int? get kapasite => ham['capacity'] == null ? null : tamSayi(ham['capacity']);
  int get alanSira => tamSayi(ham['area_sort'], 9999);
  String get durum => _metin(ham['status']) ?? 'available';
  late final List<AdisyonOzet> adisyonlar = _liste(ham['orders']).map(AdisyonOzet.new).toList();
  Json? get rezervasyon => ham['reservation'] is Map ? _json(ham['reservation']) : null;
  Json? get bagli => ham['linked_to'] is Map ? _json(ham['linked_to']) : null;

  bool get dolu => adisyonlar.isNotEmpty;
  bool get servisDisi => durum == 'out_of_service';
}

class CariKart {
  CariKart(this.ham);
  final Json ham;
  int get id => tamSayi(ham['id']);
  String get ad => _metin(ham['name']) ?? '';
  int get borc => tamSayi(ham['balance_minor']);
  late final List<AdisyonOzet> adisyonlar = _liste(ham['orders']).map(AdisyonOzet.new).toList();
}

class ServisTalebi {
  ServisTalebi(this.ham);
  final Json ham;
  int get id => tamSayi(ham['id']);
  String get tur => _metin(ham['kind']) ?? '';
  String get etiket => _metin(ham['kind_label']) ?? 'Talep';
  int? get masaId => ham['table_id'] == null ? null : tamSayi(ham['table_id']);
  String get masa => _metin(ham['table_name']) ?? '';
  String? get zaman => _metin(ham['created_at']);
}

class Pano {
  Pano(Json ham)
      : masalar = _liste(ham['tables']).map(Masa.new).toList(),
        cariler = _liste(ham['receivables']).map(CariKart.new).toList(),
        kanalSiparisleri = _liste(ham['channel_orders']).map(AdisyonOzet.new).toList(),
        onayBekleyen = _liste(ham['pending_approval']).map(AdisyonOzet.new).toList(),
        talepler = _liste(ham['service_requests']).map(ServisTalebi.new).toList();

  final List<Masa> masalar;
  final List<CariKart> cariler;
  final List<AdisyonOzet> kanalSiparisleri;
  final List<AdisyonOzet> onayBekleyen;
  final List<ServisTalebi> talepler;

  /// Alan sekmeleri, işletmenin tanımladığı sırayla.
  List<String> get alanlar {
    final sira = <String, int>{};
    for (final m in masalar) {
      sira.putIfAbsent(m.alan, () => m.alanSira);
    }
    final l = sira.keys.toList()..sort((a, b) => sira[a]!.compareTo(sira[b]!));
    return l;
  }

  /// Masa / cari / kanal fark etmeksizin tüm açık adisyonlar (kasa listesi).
  List<AdisyonOzet> get acikAdisyonlar {
    final gorulen = <int>{};
    final l = <AdisyonOzet>[];
    for (final a in [
      ...masalar.expand((m) => m.adisyonlar),
      ...cariler.expand((c) => c.adisyonlar),
      ...kanalSiparisleri,
    ]) {
      if (a.acik && gorulen.add(a.id)) l.add(a);
    }
    return l;
  }
}

/* ───────────── Adisyon detayı ───────────── */

class Kalem {
  Kalem(this.ham);
  final Json ham;

  int get id => tamSayi(ham['id']);
  int? get urunId => ham['product_id'] == null ? null : tamSayi(ham['product_id']);
  String get ad => _metin(ham['name']) ?? '';
  String? get varyant => _metin(ham['variant_name']);
  int get adet => tamSayi(ham['qty']);
  int get bekleyenAdet => tamSayi(ham['pending_qty']);
  String get durum => _metin(ham['status']) ?? '';
  String get durumEtiket => _metin(ham['status_label']) ?? '';
  bool get aktif => ham['is_active'] == true;
  bool get ikram => ham['is_comp'] == true;
  bool get odendi => ham['is_settled'] == true;
  int get tutar => tamSayi(ham['line_total_minor']);
  String? get not => _metin(ham['note']);
  String? get istasyon => _metin(ham['station_label']);
  bool get hazirliksiz => ham['no_prep'] == true;
  List<String> get secenekler =>
      _liste(ham['options']).map((o) => _metin(o['option_name']) ?? '').where((s) => s.isNotEmpty).toList();

  /// Henüz hazırlığa gitmemiş satır (silinebilir, iptal gerekmez).
  bool get taslak => durum == 'placed' && bekleyenAdet >= adet;
  int get birimFiyat => tamSayi(ham['unit_price_minor']) + tamSayi(ham['options_price_minor']);
  String? get ikramNedeni => _metin(ham['comp_reason']);
  /// Kalemin ilk eklenme saati ve ekleyeni (web: kalem dökümü).
  ({String? saat, String? kisi}) get ilkEkleme {
    final d = _liste(ham['dokum']);
    if (d.isEmpty) return (saat: null, kisi: null);
    return (saat: _metin(d.first['saat']), kisi: _metin(d.first['kisi']));
  }
}

class Adisyon extends AdisyonOzet {
  Adisyon(super.ham);

  late final List<Kalem> kalemler = _liste(ham['items']).map(Kalem.new).toList();
  List<Kalem> get aktifKalemler => kalemler.where((k) => k.aktif).toList();
  int get gonderilmemis => aktifKalemler.fold(0, (t, k) => t + (k.hazirliksiz ? 0 : k.bekleyenAdet));
  late final List<Json> olaylar = _liste(ham['events']);
}

/* ───────────── Katalog ───────────── */

class Kategori {
  Kategori(this.ham);
  final Json ham;
  int get id => tamSayi(ham['id']);
  int? get ustId => ham['parent_id'] == null ? null : tamSayi(ham['parent_id']);
  String get ad => _metin(ham['name']) ?? '';
  String? get renk => _metin(ham['color']);
}

class Varyant {
  Varyant(this.ham);
  final Json ham;
  int get id => tamSayi(ham['id']);
  String get ad => _metin(ham['name']) ?? '';
  int get fiyat => tamSayi(ham['price_minor']);
  bool get varsayilan => ham['is_default'] == true;
}

class Secenek {
  Secenek(this.ham);
  final Json ham;
  int get id => tamSayi(ham['id']);
  String get ad => _metin(ham['name']) ?? '';
  int get fiyat => tamSayi(ham['price_minor']);
  bool get varsayilan => ham['is_default'] == true;
}

class SecenekGrubu {
  SecenekGrubu(this.ham);
  final Json ham;
  int get id => tamSayi(ham['id']);
  String get ad => _metin(ham['name']) ?? '';
  bool get tekli => (_metin(ham['selection_type']) ?? 'single') == 'single';
  bool get zorunlu => ham['is_required'] == true;
  int get enAz => tamSayi(ham['min_select']);
  int? get enCok => ham['max_select'] == null ? null : tamSayi(ham['max_select']);
  late final List<Secenek> secenekler = _liste(ham['options']).map(Secenek.new).toList();
}

class Urun {
  Urun(this.ham) : arama = aramaAnahtari(_metin(ham['name']) ?? '');
  final Json ham;
  final String arama;

  int get id => tamSayi(ham['id']);
  int? get kategoriId => ham['category_id'] == null ? null : tamSayi(ham['category_id']);
  String get ad => _metin(ham['name']) ?? '';
  int get fiyat {
    final ind = ham['discounted_price_minor'];
    return ind != null ? tamSayi(ind) : tamSayi(ham['price_minor']);
  }

  bool get mevcut => ham['is_available'] != false;
  int get kullanim => tamSayi(ham['eklenme_adedi']);
  String? get gorsel => _metin(ham['image_thumb_url']) ?? _metin(ham['image_url']);
  late final List<Varyant> varyantlar = _liste(ham['variants']).map(Varyant.new).toList();
  late final List<SecenekGrubu> gruplar = _liste(ham['option_groups']).map(SecenekGrubu.new).toList();

  bool get secimGerekir => varyantlar.length > 1 || gruplar.isNotEmpty;

  /// Varsayılan varyantla görünen fiyat.
  int get gorunenFiyat {
    if (varyantlar.isEmpty) return fiyat;
    final v = varyantlar.firstWhere((v) => v.varsayilan, orElse: () => varyantlar.first);
    return v.fiyat > 0 ? v.fiyat : fiyat;
  }
}

class Katalog {
  Katalog(Json ham)
      : kategoriler = _liste(ham['categories']).map(Kategori.new).toList(),
        urunler = _liste(ham['products']).map(Urun.new).toList();

  final List<Kategori> kategoriler;
  final List<Urun> urunler;

  late final Map<int, Urun> _idIle = {for (final u in urunler) u.id: u};
  Urun? urun(int id) => _idIle[id];

  /// En sık eklenenler (sunucu zaten kullanım sırasıyla gönderiyor).
  late final List<Urun> sikKullanilan = urunler.where((u) => u.kullanim > 0).take(30).toList();

  /// Ürünü olan kategoriler (boş sekme gösterilmez). Alt kategorinin
  /// ürünleri üst kategoride de listelenir.
  late final List<Kategori> doluKategoriler = () {
    final dolu = urunler.map((u) => u.kategoriId).whereType<int>().toSet();
    final ust = {for (final k in kategoriler) k.id: k.ustId};
    final kok = <int>{};
    for (final id in dolu) {
      var k = id;
      var guvenlik = 0;
      while (ust[k] != null && guvenlik++ < 8) {
        k = ust[k]!;
      }
      kok.add(k);
    }
    return kategoriler.where((k) => k.ustId == null && kok.contains(k.id)).toList();
  }();

  late final Map<int, List<Urun>> _kategoriUrunleri = () {
    final ust = {for (final k in kategoriler) k.id: k.ustId};
    final m = <int, List<Urun>>{};
    for (final u in urunler) {
      var k = u.kategoriId;
      var guvenlik = 0;
      while (k != null && guvenlik++ < 8) {
        (m[k] ??= []).add(u);
        k = ust[k];
      }
    }
    return m;
  }();

  List<Urun> kategoriUrunleri(int kategoriId) => _kategoriUrunleri[kategoriId] ?? const [];
}
