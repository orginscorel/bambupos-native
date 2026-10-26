import 'package:flutter/material.dart';

import '../core/bildirim_merkezi.dart';
import 'cerceve.dart';

/// Sağ üstte kayan bildirimler (web useToast). Uygulamanın en üstünde durur:
/// adisyon ekranı açıkken de görünür. Dokununca ilgili ekran açılır.
class BildirimBaloncuklari extends StatelessWidget {
  const BildirimBaloncuklari({super.key, required this.merkez});
  final BildirimMerkezi merkez;

  static (Color, IconData) _ton(String tur) => switch (tur) {
        'service_call' || 'leave_requested' || 'debt_transferred' || 'order_needs_approval' || 'low_stock' =>
          (Kabuk.warning, Icons.warning_amber_rounded),
        'item_ready' => (Kabuk.success, Icons.check_circle_outline_rounded),
        'delivery_sla_breach' => (Kabuk.negative, Icons.error_outline_rounded),
        _ => (Kabuk.brand, Icons.notifications_active_outlined),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: merkez,
      builder: (context, _) {
        if (merkez.baloncuklar.isEmpty) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final dar = mq.size.width <= 640;
        return Positioned(
          top: mq.padding.top + 62,
          right: dar ? 10 : 14,
          left: dar ? 10 : null,
          width: dar ? null : 360,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final b in merkez.baloncuklar.take(4)) _kart(b)],
            ),
          ),
        );
      },
    );
  }

  Widget _kart(Baloncuk b) {
    final (renk, ikon) = _ton(b.tur);
    return Padding(
      key: ValueKey(b.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Kabuk.surface,
        elevation: 10,
        shadowColor: const Color(0x330F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Kabuk.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            merkez.kapat(b);
            if (b.id > 0) merkez.okundu(b.id);
            final a = b.adres;
            if (a != null) merkez.adresAc?.call(a);
          },
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: renk, width: 4))),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ikon, color: renk, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.baslik, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Kabuk.ink)),
                      if (b.govde != null && b.govde!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(b.govde!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Kabuk.soft)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => merkez.kapat(b),
                  icon: Icon(Icons.close_rounded, size: 16, color: Kabuk.soft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
