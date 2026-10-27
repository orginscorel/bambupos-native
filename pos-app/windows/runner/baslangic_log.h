// pos-win7 dalı — açılış günlüğü ve çökme yakalayıcı (yalnız bu dalda).
//
// Windows 7 SP1 bilgisayarda uygulama açılmıyorsa nedeni şu dosyada görünür:
//   %LOCALAPPDATA%\BamBumPOS\logs\baslangic.log
// Aynı dosyaya Dart tarafı da (lib/core/baslangic_log.dart) yazar.
#ifndef RUNNER_BASLANGIC_LOG_H_
#define RUNNER_BASLANGIC_LOG_H_

#include <string>

// Günlük dizinini hazırlar, oturum başlığını (Windows sürümü, exe yolu) yazar.
void BaslangicLogKur();

// Zaman damgalı tek satır yazar ("[native]" önekiyle).
void BaslangicLog(const std::wstring& mesaj);

// Günlük dosyasının tam yolu.
std::wstring BaslangicLogYolu();

// Çökme yakalayıcı: SetUnhandledExceptionFilter + std::terminate + abort.
// Çökmede günlüğe istisna kodu/modül yazar, logs\ altına .dmp bırakır ve
// kullanıcıya kısa bir uyarı penceresi gösterir.
void CokusYakalayiciKur();

// Flutter motorunu ve eklenti DLL'lerini (gecikmeli yüklenir) ÖNCEDEN yükler.
// Yüklenemeyen olursa eksik DLL / işlevi bulup günlüğe yazar, kullanıcıya
// pencere gösterir ve false döner (uygulama başlatılmaz).
bool BaglantilariDenetle();

// Günlüğe yazar ve kullanıcıya hata penceresi gösterir.
void HataKutusu(const std::wstring& mesaj);

#endif  // RUNNER_BASLANGIC_LOG_H_
