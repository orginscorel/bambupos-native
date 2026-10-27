import 'package:flutter/material.dart';

import 'bicim.dart';

enum IcgoruTur { iyi, kotu, uyari, bilgi }

class Icgoru {
  const Icgoru(this.tur, this.ikon, this.metin);
  final IcgoruTur tur;
  final IconData ikon;
  final String metin;
}

/// DURUM AKIŞI: patron özetinden (overview) kısa, okunur cümleler türetir.
/// Uydurma yok — yalnız yanıtta olan alanlardan; alan yoksa cümle de yok.
/// [kiyas] "düne göre" gibi; [geciken] = ops-delayed rapor satırları (bugün).
List<Icgoru> durumAkisi(Map veri, {required String kiyas, bool bugun = true, List<Map<String, dynamic>>? geciken}) {
  final l = <Icgoru>[];
  final sales = veri.m('sales');
  final delta = sales.m('delta_pct');
  final ops = veri.m('operations');
  final acik = veri.m('open');

  // Ciro kıyası
  final dc = delta.d('revenue');
  if (dc != null && dc.abs() >= 1) {
    l.add(Icgoru(dc > 0 ? IcgoruTur.iyi : IcgoruTur.kotu, dc > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        'Ciro $kiyas ${Bicim.yuzde(dc.abs())} ${dc > 0 ? 'fazla' : 'az'}.'));
  } else if (dc != null) {
    l.add(Icgoru(IcgoruTur.bilgi, Icons.trending_flat_rounded, 'Ciro $kiyas aynı seviyede.'));
  }

  // Adisyon başı ortalama
  final da = delta.d('avg_basket');
  if (da != null && da.abs() >= 5) {
    l.add(Icgoru(da > 0 ? IcgoruTur.iyi : IcgoruTur.uyari, Icons.receipt_rounded,
        'Ortalama adisyon ${Bicim.yuzde(da.abs())} ${da > 0 ? 'yükseldi' : 'düştü'} (${Bicim.para(sales.i('avg_basket_minor'), tam: true)}).'));
  }

  // Geciken açık masalar (yalnız bugün; 45 dk+)
  if (bugun && geciken != null) {
    final uzun = geciken.where((r) => r.i('age_minutes') >= 45).toList();
    if (uzun.isNotEmpty) {
      final enUzun = uzun.map((r) => r.i('age_minutes')).reduce((a, b) => a > b ? a : b);
      l.add(Icgoru(IcgoruTur.uyari, Icons.timer_rounded,
          '${uzun.length} açık adisyon 45 dk+ bekliyor (en uzun ${Bicim.dakika(enUzun)}).'));
    }
  }

  // Açık masalar
  final masa = acik.i('open_tables');
  if (bugun && masa > 0) {
    l.add(Icgoru(IcgoruTur.bilgi, Icons.table_restaurant_rounded,
        '$masa açık masada ${Bicim.para(acik.i('open_amount_minor'), tam: true)} hesap bekliyor.'));
  }

  // En yoğun saat
  final pk = ops.m('peak_hour');
  if (pk.isNotEmpty && pk.i('orders') > 0) {
    l.add(Icgoru(IcgoruTur.bilgi, Icons.schedule_rounded,
        'En yoğun saat ${pk.i('hour').toString().padLeft(2, '0')}:00 (${pk.i('orders')} adisyon).'));
  }

  // En iyi gün (çok günlü dönem)
  final bd = ops.m('best_day');
  if (!bugun && bd.isNotEmpty && veri.l('by_day').length > 1) {
    final g = Bicim.gunCoz(bd.s('date'));
    if (g != null) {
      l.add(Icgoru(IcgoruTur.iyi, Icons.emoji_events_rounded,
          'En iyi gün ${Bicim.gunAy(g)} ${Bicim.gunAdi(g)}: ${Bicim.para(bd.i('revenue_minor'), tam: true)}.'));
    }
  }

  // İptal oranı
  final ip = ops.d('cancellation_rate');
  if (ip != null && ip >= 5) {
    l.add(Icgoru(IcgoruTur.kotu, Icons.cancel_rounded, 'İptal oranı yüksek: ${Bicim.yuzde(ip)} (${ops.i('cancelled_orders')} adisyon).'));
  }

  // İndirim + ikram payı
  final ind = veri.m('discounts');
  final verilen = ind.i('discount_minor') + ind.i('comp_minor') + ind.i('iskonto_minor');
  final ciro = sales.i('revenue_minor');
  if (ciro > 0 && verilen > 0) {
    final pay = verilen * 100 / (ciro + verilen);
    if (pay >= 5) {
      l.add(Icgoru(IcgoruTur.uyari, Icons.local_offer_rounded,
          'İndirim ve ikram cironun ${Bicim.yuzde(double.parse(pay.toStringAsFixed(1)))} kadar (${Bicim.para(verilen, tam: true)}).'));
    }
  }

  // Kasa sağlaması
  final kasa = veri.m('kasa');
  if (kasa.isNotEmpty && kasa['saglama_tamam'] == false) {
    l.add(const Icgoru(IcgoruTur.kotu, Icons.point_of_sale_rounded, 'Kasa sağlaması tutmuyor: kasadaki nakit ile tahsilat farklı.'));
  }

  // Stok
  final st = veri.m('inventory');
  if (st.i('critical') > 0) {
    l.add(Icgoru(IcgoruTur.kotu, Icons.inventory_2_rounded, '${st.i('critical')} stok kalemi kritik seviyede.'));
  } else if (st.i('low') > 0) {
    l.add(Icgoru(IcgoruTur.uyari, Icons.inventory_2_rounded, '${st.i('low')} stok kalemi azaldı.'));
  }

  // Borca yazılan
  final borc = veri.m('debts');
  if (borc.b('enabled') && borc.i('total_minor') > 0) {
    l.add(Icgoru(IcgoruTur.bilgi, Icons.receipt_long_rounded,
        '${Bicim.para(borc.i('total_minor'), tam: true)} borca yazıldı (${borc.i('kisi')} kişi) — ciroda var, kasaya girmedi.'));
  }

  // Teslimat
  final tes = veri.m('delivery');
  if (tes.i('failed') > 0) {
    l.add(Icgoru(IcgoruTur.kotu, Icons.delivery_dining_rounded, '${tes.i('failed')} paket teslim edilemedi.'));
  }

  // En çok satan
  final top = veri.l('top_products');
  if (top.isNotEmpty && top.first.i('qty') > 0) {
    l.add(Icgoru(IcgoruTur.bilgi, Icons.star_rounded, 'En çok satan: ${top.first.s('name')} (${Bicim.sayi(top.first.i('qty'))} adet).'));
  }

  // Ekip
  if (bugun) {
    final ms = veri.l('on_shift');
    final sira = veri.l('upcoming_today');
    if (ms.isNotEmpty || sira.isNotEmpty) {
      final ek = sira.isEmpty
          ? ''
          : ' Sıradaki: ${sira.first.s('name', '—')} ${DateTime.tryParse(sira.first.s('start')) == null ? '' : Bicim.saat(DateTime.parse(sira.first.s('start')))}.';
      l.add(Icgoru(IcgoruTur.bilgi, Icons.badge_rounded, '${ms.length} kişi mesaide.$ek'));
    }
  }

  if (ciro == 0 && sales.i('orders') == 0) {
    l.insert(0, const Icgoru(IcgoruTur.bilgi, Icons.hourglass_empty_rounded, 'Bu dönemde henüz kapanan adisyon yok.'));
  }
  return l;
}
