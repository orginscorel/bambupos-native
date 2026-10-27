// pos-win7 dalı — açılış günlüğü, DLL ön denetimi ve çökme yakalayıcı.
// Yalnız Windows 7'de de bulunan Win32 işlevleri kullanılır; Windows 8+
// işlevleri (varsa) GetProcAddress ile çalışma anında aranır.
#include "baslangic_log.h"

#include <windows.h>

#include <dbghelp.h>
#include <signal.h>

#include <exception>
#include <iterator>
#include <set>
#include <string>
#include <vector>

namespace {

std::wstring g_log_dizini;
std::wstring g_log_yolu;

std::wstring ExeDizini() {
  wchar_t yol[MAX_PATH * 2] = {};
  DWORD n = ::GetModuleFileNameW(nullptr, yol, static_cast<DWORD>(std::size(yol)));
  std::wstring s(yol, n);
  size_t p = s.find_last_of(L"\\/");
  return p == std::wstring::npos ? s : s.substr(0, p);
}

std::wstring ExeYolu() {
  wchar_t yol[MAX_PATH * 2] = {};
  DWORD n = ::GetModuleFileNameW(nullptr, yol, static_cast<DWORD>(std::size(yol)));
  return std::wstring(yol, n);
}

bool DosyaVar(const std::wstring& yol) {
  DWORD a = ::GetFileAttributesW(yol.c_str());
  return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

std::string Utf8(const std::wstring& s) {
  if (s.empty()) return std::string();
  int n = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
  if (n <= 0) return std::string();
  std::string out(static_cast<size_t>(n), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), &out[0], n, nullptr, nullptr);
  return out;
}

std::wstring Ascii(const char* s) {
  std::wstring out;
  for (; s && *s; ++s) out.push_back(static_cast<wchar_t>(static_cast<unsigned char>(*s)));
  return out;
}

std::wstring Hex(unsigned long long v) {
  wchar_t b[32] = {};
  swprintf_s(b, L"0x%llX", v);
  return b;
}

std::wstring HataMetni(DWORD kod) {
  wchar_t* tampon = nullptr;
  DWORD n = ::FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr, kod,
      0, reinterpret_cast<wchar_t*>(&tampon), 0, nullptr);
  std::wstring s = std::to_wstring(kod);
  if (n && tampon) {
    std::wstring m(tampon, n);
    while (!m.empty() && (m.back() == L'\r' || m.back() == L'\n' || m.back() == L' ')) m.pop_back();
    s += L" (" + m + L")";
  }
  if (tampon) ::LocalFree(tampon);
  return s;
}

void Yaz(const std::wstring& satir) {
  if (g_log_yolu.empty()) return;
  // 2 MB'ı geçerse bir öncekine taşınır (baslangic.log.1).
  WIN32_FILE_ATTRIBUTE_DATA bilgi;
  if (::GetFileAttributesExW(g_log_yolu.c_str(), GetFileExInfoStandard, &bilgi) &&
      (bilgi.nFileSizeHigh > 0 || bilgi.nFileSizeLow > 2u * 1024u * 1024u)) {
    ::MoveFileExW(g_log_yolu.c_str(), (g_log_yolu + L".1").c_str(), MOVEFILE_REPLACE_EXISTING);
  }
  HANDLE h = ::CreateFileW(g_log_yolu.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  LARGE_INTEGER boy = {};
  DWORD yazilan = 0;
  if (::GetFileSizeEx(h, &boy) && boy.QuadPart == 0) {
    // UTF-8 BOM: Windows 7 Not Defteri Türkçe karakterleri doğru göstersin.
    static const unsigned char kBom[] = {0xEF, 0xBB, 0xBF};
    ::WriteFile(h, kBom, sizeof(kBom), &yazilan, nullptr);
  }
  SYSTEMTIME t;
  ::GetLocalTime(&t);
  wchar_t zaman[64] = {};
  swprintf_s(zaman, L"%04hu-%02hu-%02hu %02hu:%02hu:%02hu.%03hu [native] ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute,
             t.wSecond, t.wMilliseconds);
  std::string veri = Utf8(std::wstring(zaman) + satir + L"\r\n");
  ::WriteFile(h, veri.data(), static_cast<DWORD>(veri.size()), &yazilan, nullptr);
  ::CloseHandle(h);
}

std::wstring DosyaSurumu(const std::wstring& yol) {
  HMODULE v = ::LoadLibraryW(L"version.dll");
  if (!v) return L"?";
  using BoyutF = DWORD(WINAPI*)(LPCWSTR, LPDWORD);
  using BilgiF = BOOL(WINAPI*)(LPCWSTR, DWORD, DWORD, LPVOID);
  using SorguF = BOOL(WINAPI*)(LPCVOID, LPCWSTR, LPVOID*, PUINT);
  auto boyut = reinterpret_cast<BoyutF>(::GetProcAddress(v, "GetFileVersionInfoSizeW"));
  auto bilgi = reinterpret_cast<BilgiF>(::GetProcAddress(v, "GetFileVersionInfoW"));
  auto sorgu = reinterpret_cast<SorguF>(::GetProcAddress(v, "VerQueryValueW"));
  std::wstring sonuc = L"?";
  if (boyut && bilgi && sorgu) {
    DWORD bos = 0;
    DWORD n = boyut(yol.c_str(), &bos);
    if (n) {
      std::vector<BYTE> tampon(n);
      VS_FIXEDFILEINFO* ffi = nullptr;
      UINT uz = 0;
      if (bilgi(yol.c_str(), 0, n, tampon.data()) &&
          sorgu(tampon.data(), L"\\", reinterpret_cast<LPVOID*>(&ffi), &uz) && ffi) {
        sonuc = std::to_wstring(HIWORD(ffi->dwFileVersionMS)) + L"." + std::to_wstring(LOWORD(ffi->dwFileVersionMS)) +
                L"." + std::to_wstring(HIWORD(ffi->dwFileVersionLS)) + L"." +
                std::to_wstring(LOWORD(ffi->dwFileVersionLS));
      }
    }
  }
  ::FreeLibrary(v);
  return sonuc;
}

std::wstring SistemDizini() {
  wchar_t b[MAX_PATH] = {};
  UINT n = ::GetSystemDirectoryW(b, MAX_PATH);
  return std::wstring(b, n);
}

void SistemBilgisiYaz() {
  using RtlGetVersionF = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  OSVERSIONINFOEXW os = {};
  os.dwOSVersionInfoSize = sizeof(os);
  auto rtl = reinterpret_cast<RtlGetVersionF>(::GetProcAddress(::GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  if (rtl && rtl(reinterpret_cast<PRTL_OSVERSIONINFOW>(&os)) == 0) {
    Yaz(L"Windows " + std::to_wstring(os.dwMajorVersion) + L"." + std::to_wstring(os.dwMinorVersion) + L"." +
        std::to_wstring(os.dwBuildNumber) + L" " + os.szCSDVersion +
        (os.wProductType == VER_NT_WORKSTATION ? L" (istemci)" : L" (sunucu)"));
    if (os.dwMajorVersion == 6 && os.dwMinorVersion == 1 && os.wServicePackMajor < 1) {
      Yaz(L"UYARI: Windows 7 Service Pack 1 kurulu değil — SP1 zorunludur.");
    }
  }
  SYSTEM_INFO si = {};
  ::GetNativeSystemInfo(&si);
  Yaz(std::wstring(L"İşlemci mimarisi: ") +
      (si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 ? L"x64" : std::to_wstring(si.wProcessorArchitecture)));
  Yaz(L"Uygulama: " + ExeYolu());
  const std::wstring sys = SistemDizini();
  // d3d11.dll 6.2.x = Windows 7 Platform Update (KB2670838) kurulu.
  Yaz(L"d3d11.dll sürümü: " + DosyaSurumu(sys + L"\\d3d11.dll") + L" (6.2.x = KB2670838 Platform Update var)");
  Yaz(std::wstring(L"Sistem Universal CRT (ucrtbase.dll, KB2999226/KB3118401): ") +
      (DosyaVar(sys + L"\\ucrtbase.dll") ? L"var" : L"yok (uygulama klasöründekiler kullanılır)"));
  const std::wstring exe = ExeDizini();
  Yaz(std::wstring(L"d3dcompiler_47.dll: ") +
      (DosyaVar(exe + L"\\d3dcompiler_47.dll") ? L"uygulama klasöründe"
                                                : (DosyaVar(sys + L"\\d3dcompiler_47.dll") ? L"sistemde" : L"YOK")));
}

// Bir DLL'in içe aktarmalarını tek tek dener: eksik DLL / işlev listesi.
void EksikleriBul(const std::wstring& yol, int derinlik, std::set<std::wstring>& gorulen,
                  std::vector<std::wstring>& eksik) {
  if (derinlik > 3 || !gorulen.insert(yol).second) return;
  HMODULE h = ::LoadLibraryExW(yol.c_str(), nullptr, DONT_RESOLVE_DLL_REFERENCES);
  if (!h) {
    eksik.push_back(yol + L" açılamadı: " + HataMetni(::GetLastError()));
    return;
  }
  auto taban = reinterpret_cast<const BYTE*>(h);
  auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(taban);
  auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(taban + dos->e_lfanew);
  const IMAGE_DATA_DIRECTORY& dizin = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (dizin.VirtualAddress) {
    auto d = reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(taban + dizin.VirtualAddress);
    const std::wstring exe = ExeDizini();
    for (; d->Name; ++d) {
      std::wstring dll = Ascii(reinterpret_cast<const char*>(taban + d->Name));
      std::wstring yerel = exe + L"\\" + dll;
      std::wstring hedef = DosyaVar(yerel) ? yerel : dll;
      HMODULE b = ::LoadLibraryW(hedef.c_str());
      if (!b) {
        DWORD kod = ::GetLastError();
        eksik.push_back(dll + L" yüklenemedi: " + HataMetni(kod));
        if (DosyaVar(yerel)) EksikleriBul(yerel, derinlik + 1, gorulen, eksik);
        continue;
      }
      DWORD rva = d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk;
      for (auto th = reinterpret_cast<const IMAGE_THUNK_DATA*>(taban + rva); th->u1.AddressOfData; ++th) {
        if (IMAGE_SNAP_BY_ORDINAL(th->u1.Ordinal)) continue;
        auto ad = reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(taban + th->u1.AddressOfData);
        if (!::GetProcAddress(b, reinterpret_cast<const char*>(ad->Name))) {
          eksik.push_back(dll + L"!" + Ascii(reinterpret_cast<const char*>(ad->Name)) + L" bulunamadı (Windows 8+ işlevi?)");
        }
      }
      ::FreeLibrary(b);
    }
  }
  ::FreeLibrary(h);
}

LONG WINAPI CokusFiltresi(EXCEPTION_POINTERS* ep) {
  static LONG bir_kez = 0;
  if (::InterlockedExchange(&bir_kez, 1) != 0) return EXCEPTION_CONTINUE_SEARCH;
  const EXCEPTION_RECORD* r = ep ? ep->ExceptionRecord : nullptr;
  std::wstring mesaj = L"ÇÖKME: istisna kodu " + Hex(r ? r->ExceptionCode : 0);
  if (r) {
    mesaj += L", adres " + Hex(reinterpret_cast<unsigned long long>(r->ExceptionAddress));
    HMODULE m = nullptr;
    if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                             reinterpret_cast<LPCWSTR>(r->ExceptionAddress), &m) && m) {
      wchar_t ad[MAX_PATH] = {};
      ::GetModuleFileNameW(m, ad, MAX_PATH);
      mesaj += std::wstring(L", modül ") + ad + L" +" +
               Hex(reinterpret_cast<unsigned long long>(r->ExceptionAddress) - reinterpret_cast<unsigned long long>(m));
    }
  }
  mesaj += L", iş parçacığı " + std::to_wstring(::GetCurrentThreadId());
  Yaz(mesaj);

  // Küçük döküm dosyası (destek için): logs\cokus-YYYYMMDD-HHMMSS.dmp
  HMODULE dbg = ::LoadLibraryW(L"dbghelp.dll");
  using DokumF = BOOL(WINAPI*)(HANDLE, DWORD, HANDLE, MINIDUMP_TYPE, PMINIDUMP_EXCEPTION_INFORMATION,
                               PMINIDUMP_USER_STREAM_INFORMATION, PMINIDUMP_CALLBACK_INFORMATION);
  auto dokum = dbg ? reinterpret_cast<DokumF>(::GetProcAddress(dbg, "MiniDumpWriteDump")) : nullptr;
  if (dokum && !g_log_dizini.empty()) {
    SYSTEMTIME t;
    ::GetLocalTime(&t);
    wchar_t ad[64] = {};
    swprintf_s(ad, L"\\cokus-%04hu%02hu%02hu-%02hu%02hu%02hu.dmp", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
    std::wstring yol = g_log_dizini + ad;
    HANDLE f = ::CreateFileW(yol.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f != INVALID_HANDLE_VALUE) {
      MINIDUMP_EXCEPTION_INFORMATION bilgi = {};
      bilgi.ThreadId = ::GetCurrentThreadId();
      bilgi.ExceptionPointers = ep;
      bilgi.ClientPointers = FALSE;
      BOOL ok = dokum(::GetCurrentProcess(), ::GetCurrentProcessId(), f, MiniDumpNormal, ep ? &bilgi : nullptr,
                      nullptr, nullptr);
      ::CloseHandle(f);
      Yaz(ok ? L"Döküm dosyası: " + yol : L"Döküm yazılamadı: " + HataMetni(::GetLastError()));
    }
  }
  ::MessageBoxW(nullptr,
                (L"BamBumPOS beklenmedik şekilde kapandı.\n\n" + mesaj + L"\n\nAyrıntılar:\n" + g_log_yolu).c_str(),
                L"BamBumPOS", MB_OK | MB_ICONERROR | MB_TOPMOST);
  return EXCEPTION_EXECUTE_HANDLER;
}

void AbortYakala(int) {
  Yaz(L"ÇÖKME: abort() çağrıldı (C++ çalışma kütüphanesi / motor iç hatası).");
}

void TerminateYakala() {
  Yaz(L"ÇÖKME: std::terminate çağrıldı.");
  ::MessageBoxW(nullptr, (L"BamBumPOS beklenmedik şekilde kapandı (terminate).\n\nAyrıntılar:\n" + g_log_yolu).c_str(),
                L"BamBumPOS", MB_OK | MB_ICONERROR | MB_TOPMOST);
  ::ExitProcess(3);
}

}  // namespace

std::wstring BaslangicLogYolu() { return g_log_yolu; }

void BaslangicLog(const std::wstring& mesaj) { Yaz(mesaj); }

void BaslangicLogKur() {
  wchar_t yerel[MAX_PATH * 2] = {};
  DWORD n = ::GetEnvironmentVariableW(L"LOCALAPPDATA", yerel, static_cast<DWORD>(std::size(yerel)));
  std::wstring kok = (n > 0 && n < std::size(yerel)) ? std::wstring(yerel, n) + L"\\BamBumPOS" : ExeDizini();
  ::CreateDirectoryW(kok.c_str(), nullptr);
  g_log_dizini = kok + L"\\logs";
  ::CreateDirectoryW(g_log_dizini.c_str(), nullptr);
  g_log_yolu = g_log_dizini + L"\\baslangic.log";
  Yaz(L"──────── BamBumPOS (Windows 7 derlemesi) başlıyor · pid " + std::to_wstring(::GetCurrentProcessId()) +
      L" ────────");
  SistemBilgisiYaz();
}

void CokusYakalayiciKur() {
  ::SetUnhandledExceptionFilter(CokusFiltresi);
  std::set_terminate(TerminateYakala);
  signal(SIGABRT, AbortYakala);
  // Windows'un kendi "çalışmayı durdurdu" kutusu yerine bizimki.
  ::SetErrorMode(::GetErrorMode() | SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
}

void HataKutusu(const std::wstring& mesaj) {
  Yaz(L"HATA: " + mesaj);
  ::MessageBoxW(nullptr, (mesaj + L"\n\nAyrıntılar:\n" + g_log_yolu).c_str(), L"BamBumPOS", MB_OK | MB_ICONERROR);
}

bool BaglantilariDenetle() {
  const std::wstring exe = ExeDizini();
  std::vector<std::wstring> dosyalar = {L"flutter_windows.dll"};
  WIN32_FIND_DATAW fd;
  HANDLE f = ::FindFirstFileW((exe + L"\\*_plugin.dll").c_str(), &fd);
  if (f != INVALID_HANDLE_VALUE) {
    do {
      dosyalar.push_back(fd.cFileName);
    } while (::FindNextFileW(f, &fd));
    ::FindClose(f);
  }
  bool hepsi = true;
  std::wstring ozet;
  for (const auto& d : dosyalar) {
    const std::wstring yol = exe + L"\\" + d;
    if (!DosyaVar(yol)) {
      hepsi = false;
      ozet += d + L": dosya YOK\n";
      Yaz(d + L": dosya YOK");
      continue;
    }
    HMODULE h = ::LoadLibraryExW(yol.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (h) {
      Yaz(d + L": yüklendi");
      continue;  // Açık kalır: gecikmeli yükleme aynı modülü kullanır.
    }
    DWORD kod = ::GetLastError();
    hepsi = false;
    Yaz(d + L": YÜKLENEMEDİ, hata " + HataMetni(kod));
    std::set<std::wstring> gorulen;
    std::vector<std::wstring> eksik;
    EksikleriBul(yol, 0, gorulen, eksik);
    ozet += d + L" yüklenemedi (hata " + std::to_wstring(kod) + L")\n";
    for (const auto& e : eksik) {
      Yaz(L"  eksik: " + e);
      ozet += L"  • " + e + L"\n";
    }
  }
  if (!hepsi) {
    HataKutusu(L"BamBumPOS başlatılamadı: gerekli bileşenler yüklenemedi.\n\n" + ozet +
               L"\nWindows 7 SP1 için gerekenler: Service Pack 1, KB2670838 (Platform Update), KB2999226 "
               L"(Universal C Runtime). Uygulama klasöründeki baslat.bat ayrıntılı denetim yapar.");
  }
  return hepsi;
}
