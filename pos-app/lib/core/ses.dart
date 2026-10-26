import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Bildirim sesi ve görev çubuğu uyarısı (Windows).
///
/// Web'in WebAudio bipi (880 Hz, iki kısa ton) aynı biçimde bellekte WAV
/// olarak üretilir ve winmm!PlaySoundW ile çalınır — eklenti yok, Windows
/// 7'de de var. Android / iOS / macOS'ta sesi sistem bildirimi çalar
/// (bildirim_merkezi.dart).
class BildirimSesi {
  BildirimSesi._();

  static Pointer<Uint8>? _wav;

  static void bip() {
    if (!Platform.isWindows) return;
    try {
      final wav = _wav ??= _bellegeYaz(_ikiTon());
      _playSound(wav.cast(), nullptr, _sndMemory | _sndAsync | _sndNoDefault);
    } catch (_) {
      // Ses aygıtı yoksa sessiz geç.
    }
  }

  /// Pencere öndeyken değilse görev çubuğu düğmesi yanıp söner.
  static void dikkatCek() {
    if (!Platform.isWindows) return;
    try {
      final ad = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = _findWindow(ad, nullptr);
      calloc.free(ad);
      if (hwnd == nullptr) return;
      final bilgi = calloc<_FlashWInfo>()
        ..ref.cbSize = sizeOf<_FlashWInfo>()
        ..ref.hwnd = hwnd
        ..ref.dwFlags = 0x3 | 0xC // FLASHW_ALL | FLASHW_TIMERNOFG
        ..ref.uCount = 0
        ..ref.dwTimeout = 0;
      _flashWindowEx(bilgi);
      calloc.free(bilgi);
    } catch (_) {}
  }

  /* ───── WAV: 22 050 Hz, 16 bit, tek kanal, 2 × 0,30 sn 880 Hz ───── */

  static Uint8List _ikiTon() {
    const hz = 22050, ton = 0.30, ara = 0.05;
    final ornek = ((ton * 2 + ara) * hz).round();
    final veri = ByteData(44 + ornek * 2);
    void yazi(int o, String s) {
      for (var i = 0; i < 4; i++) {
        veri.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    yazi(0, 'RIFF');
    veri.setUint32(4, 36 + ornek * 2, Endian.little);
    yazi(8, 'WAVE');
    yazi(12, 'fmt ');
    veri
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, hz, Endian.little)
      ..setUint32(28, hz * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    yazi(36, 'data');
    veri.setUint32(40, ornek * 2, Endian.little);
    for (var i = 0; i < ornek; i++) {
      final t = i / hz;
      final bas = t < ton ? 0.0 : ton + ara;
      final yerel = t - bas;
      double s = 0;
      if (yerel >= 0 && yerel < ton) {
        // Web'deki gibi hızlı yükseliş, üstel sönüm.
        final zarf = yerel < 0.02 ? yerel / 0.02 : math.exp(-(yerel - 0.02) * 12);
        s = math.sin(2 * math.pi * 880 * yerel) * zarf * 0.4;
      }
      veri.setInt16(44 + i * 2, (s * 32767).round(), Endian.little);
    }
    return veri.buffer.asUint8List();
  }

  static Pointer<Uint8> _bellegeYaz(Uint8List b) {
    final p = malloc<Uint8>(b.length); // çalarken bellekte kalmalı: hiç bırakılmaz
    p.asTypedList(b.length).setAll(0, b);
    return p;
  }

  static const _sndAsync = 0x1, _sndNoDefault = 0x2, _sndMemory = 0x4;

  static final _playSound = DynamicLibrary.open('winmm.dll')
      .lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Void>, Uint32), int Function(Pointer<Utf16>, Pointer<Void>, int)>(
          'PlaySoundW');
  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _findWindow = _user32.lookupFunction<Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>),
      Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
  static final _flashWindowEx =
      _user32.lookupFunction<Int32 Function(Pointer<_FlashWInfo>), int Function(Pointer<_FlashWInfo>)>('FlashWindowEx');
}

final class _FlashWInfo extends Struct {
  @Uint32()
  external int cbSize;
  external Pointer<Void> hwnd;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int uCount;
  @Uint32()
  external int dwTimeout;
}
