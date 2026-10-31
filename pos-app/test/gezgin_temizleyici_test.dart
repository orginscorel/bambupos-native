import 'package:bambumpos_pos/core/gezgin_temizleyici.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Durum extends ChangeNotifier {
  bool calisma = true;
  void ayarla(bool v) {
    calisma = v;
    notifyListeners();
  }
}

void main() {
  testWidgets('çalışmadan çıkınca üstteki sayfa ve pencere kapanır', (t) async {
    final d = _Durum();
    final g = GlobalKey<NavigatorState>();
    final b = GezginTemizleyici(dinle: d, calismada: () => d.calisma, gezgin: g);
    await t.pumpWidget(MaterialApp(navigatorKey: g, home: const Text('kok')));
    g.currentState!.push(MaterialPageRoute<void>(builder: (_) => PopScope(canPop: false, child: const Text('adisyon'))));
    await t.pumpAndSettle();
    showDialog<void>(context: g.currentContext!, builder: (_) => const Text('pencere'));
    await t.pumpAndSettle();
    expect(find.text('pencere'), findsOneWidget);

    d.ayarla(false);
    await t.pumpAndSettle();
    expect(find.text('adisyon'), findsNothing);
    expect(find.text('pencere'), findsNothing);
    expect(find.text('kok'), findsOneWidget);
    b.dispose();
  });

  testWidgets('çalışmada kalırken sayfalara dokunulmaz', (t) async {
    final d = _Durum();
    final g = GlobalKey<NavigatorState>();
    final b = GezginTemizleyici(dinle: d, calismada: () => d.calisma, gezgin: g);
    await t.pumpWidget(MaterialApp(navigatorKey: g, home: const Text('kok')));
    g.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('adisyon')));
    await t.pumpAndSettle();
    d.ayarla(true);
    await t.pumpAndSettle();
    expect(find.text('adisyon'), findsOneWidget);
    b.dispose();
  });
}
