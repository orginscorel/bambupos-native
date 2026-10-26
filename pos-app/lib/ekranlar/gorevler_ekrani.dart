import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'cerceve.dart';
import 'ortak.dart';

/// GÖREVLER — web /panel/gorevler (Staff/StaffTasks.vue) birebiri.
///
/// SALT OKUNUR takip ekranı (işletme kararı 2026-10-25): görev ekleme
/// İşletme Yönetimi / patron panelinden, durum değiştirme personel
/// uygulamasından yapılır. Burada yalnız kimin hangi görevi hangi durumda
/// taşıdığı görünür. Üstte dört rakam, altında süzgeçli TEK liste; sıralama
/// önce geciken, sonra bitmemiş, sonra son tarihi yakın olan.
class GorevlerEkrani extends StatefulWidget {
  const GorevlerEkrani({super.key});

  @override
  State<GorevlerEkrani> createState() => _GorevlerEkraniState();
}

const _durumAdlari = {'open': 'Açık', 'in_progress': 'Devam ediyor', 'done': 'Tamamlandı'};
const _oncelikAdlari = {'low': 'Düşük', 'normal': 'Normal', 'high': 'Yüksek'};
const _aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

class _GorevlerEkraniState extends State<GorevlerEkrani> {
  bool _yukleniyor = true;
  List<Map<String, dynamic>> _gorevler = const [];
  String _suzgec = 'hepsi';

  bool get _gorebilir {
    final o = context.durum.oturum!;
    return o.yetki('tasks.view') || o.yetkiler.contains('*');
  }

  @override
  void initState() {
    super.initState();
    if (_gorebilir) {
      _yukle();
    } else {
      _yukleniyor = false;
    }
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await context.api.get('/api/v1/tasks');
      if (!mounted) return;
      final liste = r is Map ? r['tasks'] : null;
      setState(() => _gorevler = (liste as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList());
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Görevler yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  static DateTime? _tarih(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  bool _gecikti(Map<String, dynamic> t) {
    final son = _tarih(t['due_at']);
    return t['status'] != 'done' && son != null && son.isBefore(DateTime.now());
  }

  /// tr-TR {day:'numeric', month:'short', hour, minute} → "26 Eki 14:30".
  static String _tarihYaz(Object? v) {
    final d = _tarih(v);
    if (d == null) return '';
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${d.day} ${_aylar[d.month - 1]} ${iki(d.hour)}:${iki(d.minute)}';
  }

  List<Map<String, dynamic>> get _gorunen {
    final liste = _suzgec == 'hepsi' ? [..._gorevler] : _gorevler.where((t) => t['status'] == _suzgec).toList();
    int son(Map<String, dynamic> t) => _tarih(t['due_at'])?.millisecondsSinceEpoch ?? 1 << 53;
    liste.sort((a, b) {
      final ag = _gecikti(a) ? 0 : 1, bg = _gecikti(b) ? 0 : 1;
      if (ag != bg) return ag - bg;
      final ab = a['status'] == 'done' ? 1 : 0, bb = b['status'] == 'done' ? 1 : 0;
      if (ab != bb) return ab - bb;
      return son(a).compareTo(son(b));
    });
    return liste;
  }

  int _sayi(String durum) => _gorevler.where((t) => t['status'] == durum).length;

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final genis = g >= 1024;

    final icerik = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text('Görevler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.36, color: Kabuk.ink)),
          Text('atanan görevlerin durumu', style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
        ]),
      ),
    ];

    if (!_gorebilir) {
      icerik.add(_bos('Erişim yok', 'Görevleri görüntülemek için yetkiniz bulunmuyor.'));
    } else {
      icerik.add(_rakamlar(g));
      if (_yukleniyor) {
        icerik.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Text('Yükleniyor…', textAlign: TextAlign.center, style: TextStyle(color: Kabuk.soft)),
        ));
      } else if (_gorevler.isEmpty) {
        icerik.add(_bos('Henüz görev yok', 'Görev atandığında burada listelenir. Görev ekleme işletme yönetimi ve patron panelinden yapılır.'));
      } else {
        icerik.add(_suzgecSeridi());
        final liste = _gorunen;
        if (g >= 900) icerik.add(_sutunBasligi());
        if (liste.isEmpty) {
          icerik.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
            child: Text('Bu süzgeçte görev yok.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Kabuk.soft)),
          ));
        } else {
          for (final t in liste) {
            icerik.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _satir(t, g >= 900)));
          }
        }
      }
    }

    return ColoredBox(
      color: Kabuk.sunken,
      child: RefreshIndicator(
        onRefresh: _gorebilir ? _yukle : () async {},
        child: ListView(
          padding: EdgeInsets.fromLTRB(genis ? 18 : 14, genis ? 12 : 10, genis ? 18 : 14, genis ? 22 : 20),
          children: icerik,
        ),
      ),
    );
  }

  Widget _bos(String baslik, String metin) => Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        child: Column(children: [
          Text(baslik, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Kabuk.ink)),
          const SizedBox(height: 4),
          Text(metin, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Kabuk.soft)),
        ]),
      );

  Widget _rakamlar(double g) {
    final gec = _gorevler.where(_gecikti).length;
    final kutular = [
      ('Açık görev', _sayi('open'), 'henüz başlanmadı', Kabuk.ink),
      ('Devam eden', _sayi('in_progress'), 'üzerinde çalışılıyor', Kabuk.brand),
      ('Geciken', gec, 'son tarihi geçti', gec > 0 ? Kabuk.negative : Kabuk.ink),
      ('Tamamlanan', _sayi('done'), 'bitirilen görev', Kabuk.success),
    ];
    final sutun = g >= 900 ? 4 : 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, k) {
        final w = (k.maxWidth - 8 * (sutun - 1)) / sutun;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (ad, n, alt, renk) in kutular)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ad, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
                Text(_yukleniyor ? '—' : '$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4, color: renk)),
                Text(alt, style: TextStyle(fontSize: 11, color: Kabuk.soft)),
              ]),
            ),
        ]);
      }),
    );
  }

  Widget _suzgecSeridi() {
    final suzgecler = [
      ('hepsi', 'Tümü', _gorevler.length),
      for (final e in _durumAdlari.entries) (e.key, e.value, _sayi(e.key)),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      child: Row(children: [
        for (final (k, ad, n) in suzgecler)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: _suzgec == k ? Kabuk.sunken : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _suzgec = k),
                  child: SizedBox(
                    height: 32,
                    child: Center(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '$ad '),
                          TextSpan(text: '$n', style: TextStyle(color: (_suzgec == k ? Kabuk.ink : Kabuk.soft).withValues(alpha: .7))),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _suzgec == k ? Kabuk.ink : Kabuk.soft),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  static const _oranlar = [2.6, 1.2, .7, 1.05, .9];

  Widget _sutunBasligi() {
    final adlar = ['GÖREV', 'ATANAN', 'ÖNCELİK', 'SON TARİH', 'DURUM'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 7),
      child: Row(children: [
        for (var i = 0; i < adlar.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            flex: (_oranlar[i] * 100).round(),
            child: Text(adlar[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .77, color: Kabuk.soft)),
          ),
        ],
      ]),
    );
  }

  Widget _rozet(String metin, Color renk, {Color? kenar, Color? zemin, FontWeight kalinlik = FontWeight.w700}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(color: zemin, borderRadius: koseYuvarlak, border: Border.all(color: kenar ?? Kabuk.line)),
        child: Text(metin, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: kalinlik, color: renk)),
      );

  Widget _satir(Map<String, dynamic> t, bool tablo) {
    final durum = '${t['status'] ?? 'open'}';
    final bitti = durum == 'done';
    final gec = _gecikti(t);
    final atanan = t['assigned_to'] is Map ? t['assigned_to'] as Map : null;
    final oncelik = '${t['priority'] ?? 'normal'}';
    final aciklama = t['description']?.toString();

    final gorev = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(
        '${t['title'] ?? ''}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: Kabuk.ink,
          decoration: bitti ? TextDecoration.lineThrough : null,
          decorationColor: Kabuk.soft,
        ),
      ),
      if (aciklama != null && aciklama.isNotEmpty)
        Text(aciklama, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
    ]);

    final kisi = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (atanan != null) ...[
        Text('${atanan['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Kabuk.ink)),
        if (atanan['position'] != null)
          Text('${atanan['position']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Kabuk.soft)),
      ] else
        Text('—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Kabuk.soft)),
    ]);

    final oncRenk = switch (oncelik) {
      'normal' => Kabuk.brand,
      'high' => Kabuk.negative,
      _ => Kabuk.soft,
    };
    final onc = _rozet(
      _oncelikAdlari[oncelik] ?? oncelik,
      oncRenk,
      kenar: oncelik == 'low' ? null : Color.lerp(Kabuk.line, oncRenk, .4),
      kalinlik: FontWeight.w800,
    );

    final sonRenk = gec ? Kabuk.negative : Kabuk.ink;
    final son = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(t['due_at'] != null ? _tarihYaz(t['due_at']) : '—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: sonRenk)),
      if (gec)
        Text('gecikti', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Kabuk.negative))
      else if (bitti && t['completed_at'] != null)
        Text('bitti ${_tarihYaz(t['completed_at'])}', style: TextStyle(fontSize: 11, color: Kabuk.soft)),
    ]);

    final durumRenk = switch (durum) {
      'in_progress' => Kabuk.brand,
      'done' => Kabuk.success,
      _ => Kabuk.soft,
    };
    final rozet = _rozet(_durumAdlari[durum] ?? durum, durumRenk, zemin: Kabuk.sunken);

    final govde = tablo
        ? Row(children: [
            for (final (i, w) in [gorev, kisi, Align(alignment: Alignment.centerLeft, child: onc), son, Align(alignment: Alignment.centerLeft, child: rozet)].indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(flex: (_oranlar[i] * 100).round(), child: w),
            ],
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            gorev,
            const SizedBox(height: 6),
            Row(children: [Expanded(child: kisi), const SizedBox(width: 10), onc]),
            const SizedBox(height: 6),
            Row(children: [Expanded(child: son), const SizedBox(width: 10), rozet]),
          ]);

    return Opacity(
      opacity: bitti ? .82 : 1,
      child: Container(
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Geciken görev kenarından belli olur (satır kırmızıya boyanmaz).
            if (gec) Container(width: 3, color: Kabuk.negative),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: EdgeInsets.fromLTRB(gec ? 11 : 14, 10, 14, 10),
                alignment: Alignment.centerLeft,
                child: govde,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
