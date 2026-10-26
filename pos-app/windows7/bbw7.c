/*
 * BBW7.dll — BamBumPOS Windows 7 / 8.1 uyumluluk katmanı.
 *
 * Flutter motoru (flutter_windows.dll) ve share_plus eklentisi Windows 8 ile
 * gelen birkaç sistem işlevini doğrudan içe aktarıyor; Windows 7 yükleyicisi
 * bunları bulamayınca program hiç açılmıyor. windows7/yamala.py derlenmiş
 * paketteki ilgili içe aktarma tablolarını bu DLL'e çevirir:
 *   • burada YAZILAN işlevler Windows 7 karşılıklarıyla çalışır,
 *   • aynı tablodaki diğer işlevler asıl DLL'e YÖNLENDİRİLİR (bbw7.def,
 *     yamala.py üretir).
 * CRT kullanılmaz (/NODEFAULTLIB) — yalnız kernel32 / ws2_32 / shlwapi.
 */
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <shlwapi.h>

BOOL WINAPI DllMain(HINSTANCE h, DWORD neden, LPVOID ayrilmis)
{
    (void)h; (void)neden; (void)ayrilmis;
    return TRUE;
}

/* memcpy yok (CRT'siz): kernel32'nin kendi kopyalaması. n = sonlandırıcı dahil. */
static void kopyala(WCHAR *hedef, const WCHAR *kaynak, size_t n)
{
    lstrcpynW(hedef, kaynak, (int)n);
}

/* ───── kernel32: GetCurrentThreadStackLimits (Windows 8) ─────
 * x64 TEB: NT_TIB.StackBase = üst sınır, DeallocationStack (0x1478) = alt
 * sınır (koruma sayfaları dahil) — Windows 8'in döndürdüğüyle aynı. */
void WINAPI bb_GetCurrentThreadStackLimits(PULONG_PTR alt, PULONG_PTR ust)
{
    BYTE *teb = (BYTE *)NtCurrentTeb();
    *ust = (ULONG_PTR)((NT_TIB *)teb)->StackBase;
    *alt = *(ULONG_PTR *)(teb + 0x1478);
}

/* ───── synch-l1-2-0: WaitOnAddress / WakeByAddress* (Windows 8) ─────
 * Tek kilit + koşul değişkeniyle öykünme. Uyandırıcı kilidi alıp bıraktığı
 * için "değeri kontrol et → uyu" arasına giremez; sahte uyanma serbest
 * (Windows'ta da öyle — çağıranlar döngüde yeniden kontrol eder). */
static SRWLOCK g_kilit = SRWLOCK_INIT;
static CONDITION_VARIABLE g_kosul = CONDITION_VARIABLE_INIT;

static BOOL ayni(volatile const void *a, const void *b, SIZE_T n)
{
    volatile const BYTE *x = (volatile const BYTE *)a;
    const BYTE *y = (const BYTE *)b;
    SIZE_T i;
    for (i = 0; i < n; i++)
        if (x[i] != y[i]) return FALSE;
    return TRUE;
}

BOOL WINAPI bb_WaitOnAddress(volatile VOID *adres, PVOID karsilastir, SIZE_T boy, DWORD ms)
{
    BOOL sonuc = TRUE;
    AcquireSRWLockExclusive(&g_kilit);
    if (ayni(adres, karsilastir, boy)) {
        if (!SleepConditionVariableSRW(&g_kosul, &g_kilit, ms, 0)) {
            sonuc = FALSE; /* GetLastError = ERROR_TIMEOUT */
        }
    }
    ReleaseSRWLockExclusive(&g_kilit);
    return sonuc;
}

void WINAPI bb_WakeByAddressAll(PVOID adres)
{
    (void)adres;
    AcquireSRWLockExclusive(&g_kilit);
    ReleaseSRWLockExclusive(&g_kilit);
    WakeAllConditionVariable(&g_kosul);
}

void WINAPI bb_WakeByAddressSingle(PVOID adres)
{
    /* Tek kilit paylaşıldığı için yanlış bekleyeni uyandırmamak adına hepsi. */
    bb_WakeByAddressAll(adres);
}

/* ───── ws2_32: GetHostNameW (Windows 8) ───── */
int WSAAPI bb_GetHostNameW(PWSTR ad, int boy)
{
    char tampon[256];
    int n;
    if (gethostname(tampon, sizeof tampon) != 0) return SOCKET_ERROR;
    n = MultiByteToWideChar(CP_ACP, 0, tampon, -1, ad, boy);
    if (n == 0) {
        WSASetLastError(WSAEFAULT);
        return SOCKET_ERROR;
    }
    return 0;
}

/* ───── path-l1-1-0: PathCch* (Windows 8) ─────
 * shlwapi karşılıklarıyla (MAX_PATH sınırı; uygulama klasörü için yeterli). */
#define BB_E_YETERSIZ ((HRESULT)0x8007007A) /* ERROR_INSUFFICIENT_BUFFER */
#define BB_E_GECERSIZ ((HRESULT)0x80070057) /* E_INVALIDARG */

HRESULT WINAPI bb_PathCchCombineEx(PWSTR cikis, size_t cikisBoy, PCWSTR giris, PCWSTR ek, ULONG bayrak)
{
    WCHAR gecici[MAX_PATH];
    int n;
    (void)bayrak;
    if (cikis == NULL || cikisBoy == 0) return BB_E_GECERSIZ;
    if (PathCombineW(gecici, giris, ek) == NULL) {
        cikis[0] = 0;
        return BB_E_GECERSIZ;
    }
    n = lstrlenW(gecici);
    if ((size_t)n + 1 > cikisBoy) {
        cikis[0] = 0;
        return BB_E_YETERSIZ;
    }
    kopyala(cikis, gecici, (size_t)n + 1);
    return S_OK;
}

HRESULT WINAPI bb_PathCchRemoveFileSpec(PWSTR yol, size_t boy)
{
    (void)boy;
    if (yol == NULL) return BB_E_GECERSIZ;
    return PathRemoveFileSpecW(yol) ? S_OK : S_FALSE;
}

HRESULT WINAPI bb_PathAllocCanonicalize(PCWSTR giris, ULONG bayrak, PWSTR *cikis)
{
    WCHAR gecici[MAX_PATH];
    WCHAR *bellek;
    int n;
    (void)bayrak;
    if (cikis == NULL) return BB_E_GECERSIZ;
    *cikis = NULL;
    if (giris == NULL || !PathCanonicalizeW(gecici, giris)) return BB_E_GECERSIZ;
    n = lstrlenW(gecici);
    bellek = (WCHAR *)LocalAlloc(LMEM_FIXED, ((SIZE_T)n + 1) * sizeof(WCHAR));
    if (bellek == NULL) return E_OUTOFMEMORY;
    kopyala(bellek, gecici, (size_t)n + 1);
    *cikis = bellek; /* çağıran LocalFree ile bırakır (Windows 8'deki gibi) */
    return S_OK;
}

/* ───── ntdll: RtlAddGrowableFunctionTable (Windows 8) ─────
 * Dart'ın ürettiği kodun çözme (unwind) tablosu. Windows 7'de büyütülemeyen
 * RtlAddFunctionTable ile aynı kayıt yapılır; Dart tabloyu sonradan
 * büyütmüyor (RtlGrowFunctionTable içe aktarılmıyor). */
DWORD WINAPI bb_RtlAddGrowableFunctionTable(PVOID *tablo, PRUNTIME_FUNCTION fonk, DWORD adet,
                                            DWORD enCok, ULONG_PTR taban, ULONG_PTR son)
{
    (void)enCok; (void)son;
    if (!RtlAddFunctionTable(fonk, adet, (DWORD64)taban)) return 0xC0000001; /* STATUS_UNSUCCESSFUL */
    *tablo = fonk;
    return 0;
}

void WINAPI bb_RtlDeleteGrowableFunctionTable(PVOID tablo)
{
    RtlDeleteFunctionTable((PRUNTIME_FUNCTION)tablo);
}

/* ───── winrt (share_plus): Windows 8 ─────
 * Windows 7'de WinRT yok: paylaşma "desteklenmiyor" hatasıyla döner,
 * uygulamanın geri kalanı etkilenmez. */
#define BB_E_NOTIMPL ((HRESULT)0x80004001)

HRESULT WINAPI bb_RoGetActivationFactory(void *sinif, const void *iid, void **fabrika)
{
    (void)sinif; (void)iid;
    if (fabrika) *fabrika = NULL;
    return BB_E_NOTIMPL;
}

HRESULT WINAPI bb_WindowsCreateString(const WCHAR *kaynak, UINT32 boy, void **dize)
{
    (void)kaynak; (void)boy;
    if (dize) *dize = NULL;
    return BB_E_NOTIMPL;
}

HRESULT WINAPI bb_WindowsCreateStringReference(const WCHAR *kaynak, UINT32 boy, void *baslik, void **dize)
{
    (void)kaynak; (void)boy; (void)baslik;
    if (dize) *dize = NULL;
    return BB_E_NOTIMPL;
}

HRESULT WINAPI bb_WindowsDeleteString(void *dize)
{
    (void)dize;
    return S_OK;
}

BOOL WINAPI bb_RoOriginateError(HRESULT hata, void *mesaj)
{
    (void)hata; (void)mesaj;
    return FALSE;
}
