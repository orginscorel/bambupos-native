"""BamBumPOS — Windows paketini Windows 7 SP1 / 8.1 için hazırlar.

    python yamala.py yamala  <paket_dizini> <bbw7.def>
    python yamala.py denetle <paket_dizini>

yamala : Windows 8+ işlevi içe aktaran tabloları BBW7.dll'e çevirir, o
         tablodaki diğer işlevler için bbw7.def'e yönlendirme yazar ve
         "en az Windows 10" işaretini 6.1'e (Windows 7) indirir.
denetle: paketteki her .exe/.dll'in içe aktarmalarını Windows 7'de
         bulunmayanlara karşı tarar; bulursa listeler ve 1 ile çıkar.
         Yeni bir Flutter sürümü yeni bir Windows 8+ işlevi eklerse derleme
         burada durur (sessizce bozuk paket çıkmaz).
"""
import glob
import os
import sys

import pefile

SHIM = 'BBW7.dll'

# bbw7.c'de YAZILAN işlevler (ad → C'deki karşılığı bb_<ad>).
YAZILAN = {
    'GetCurrentThreadStackLimits', 'WaitOnAddress', 'WakeByAddressAll', 'WakeByAddressSingle',
    'GetHostNameW', 'PathCchCombineEx', 'PathCchRemoveFileSpec', 'PathAllocCanonicalize',
    'RtlAddGrowableFunctionTable', 'RtlDeleteGrowableFunctionTable',
    'RoGetActivationFactory', 'WindowsCreateString', 'WindowsCreateStringReference',
    'WindowsDeleteString', 'RoOriginateError',
}

# Windows 7'de OLMAYAN, bilinen işlevler (sistem DLL'lerinde).
WIN8_ISLEV = YAZILAN | {
    'GetSystemTimePreciseAsFileTime', 'CreateFile2', 'CopyFile2', 'SetThreadInformation',
    'GetThreadInformation', 'GetOverlappedResultEx', 'PrefetchVirtualMemory', 'SetThreadDescription',
    'GetThreadDescription', 'GetFirmwareType', 'GetProcessMitigationPolicy', 'SetProcessMitigationPolicy',
    'GetPackageFamilyName', 'GetCurrentPackageId', 'GetCurrentPackageFullName', 'CompareObjectHandles',
    'MapViewOfFile3', 'VirtualAlloc2', 'MapViewOfFileFromApp', 'VirtualAllocFromApp',
    'GetSystemCpuSetInformation', 'SetThreadSelectedCpuSets', 'DiscardVirtualMemory', 'OfferVirtualMemory',
    'ReclaimVirtualMemory', 'GetDpiForWindow', 'GetDpiForSystem', 'SetProcessDpiAwarenessContext',
    'SetThreadDpiAwarenessContext', 'EnableNonClientDpiScaling', 'GetSystemMetricsForDpi',
    'AdjustWindowRectExForDpi', 'SystemParametersInfoForDpi', 'GetPointerType', 'GetPointerInfo',
    'GetPointerFrameInfo', 'EnableMouseInPointer', 'RegisterPointerDeviceNotifications',
    'InitializeTouchInjection', 'RtlGrowFunctionTable', 'GetDpiForMonitor', 'SetProcessDpiAwareness',
    'CreateDispatcherQueueController', 'RoInitialize', 'RoUninitialize', 'RoActivateInstance',
    'WindowsGetStringRawBuffer', 'GetAddrInfoExCancel', 'GetQueuedCompletionStatusEx2',
}

# Windows 7'de hiç bulunmayan DLL'ler (pakette de yoksa).
WIN8_DLL = {'shcore.dll', 'dcomp.dll', 'd3d12.dll', 'coremessaging.dll', 'windows.storage.dll',
            'api-ms-win-core-winrt-l1-1-0.dll'}

# Windows 7 SP1'de bulunan API kümeleri (api-ms-win-core-*-l1-1-0 ailesi).
WIN7_APISET = {f'api-ms-win-core-{a}-l1-1-0.dll' for a in (
    'console datetime debug delayload errorhandling fibers file handle heap interlocked io '
    'libraryloader localization localregistry memory misc namedpipe processenvironment '
    'processthreads profile rtlsupport string synch sysinfo threadpool util xstate').split()}
WIN7_APISET |= {'api-ms-win-security-base-l1-1-0.dll', 'api-ms-win-security-lsalookup-l1-1-0.dll',
                'api-ms-win-security-sddl-l1-1-0.dll'}


def ikililer(dizin):
    """Programın AÇILIŞTA yüklediği dosyalar: BamBumPOS.exe'den başlayıp
    paketteki DLL'lere uzanan doğrudan içe aktarma zinciri. FFI ile sonradan
    açılan DLL'ler (dartjni, flutter_local_notifications_windows) zincirde
    yoktur; Windows 7'de yüklenemezlerse Dart tarafı hatayı yakalar."""
    paket = {os.path.basename(f).lower(): f for f in glob.glob(os.path.join(dizin, '*'))
             if f.lower().endswith(('.exe', '.dll'))}
    exe = [k for k in paket if k.endswith('.exe')]
    sira, gorulen = list(exe), set(exe)
    while sira:
        k = sira.pop()
        pe = ac(paket[k])
        for e in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', []):
            d = e.dll.decode().lower()
            if d in paket and d not in gorulen:
                gorulen.add(d)
                sira.append(d)
        pe.close()
    if SHIM.lower() in paket:
        gorulen.add(SHIM.lower())
    return sorted(paket[k] for k in gorulen)


def ac(yol):
    pe = pefile.PE(yol, fast_load=True)
    pe.parse_data_directories(directories=[
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_IMPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT'],
    ])
    return pe


def adi(i):
    return i.name.decode() if i.name else None


def cevrilmeli(dll, adlar):
    d = dll.lower()
    if d.startswith(('api-ms-win-core-path-', 'api-ms-win-core-synch-l1-2-', 'api-ms-win-core-winrt-')):
        return True
    return any(a in YAZILAN for a in adlar if a)


def yamala(dizin, def_yolu):
    yonlendir = {}  # işlev → satır
    for yol in ikililer(dizin):
        if os.path.basename(yol).lower() == SHIM.lower():
            continue
        pe = ac(yol)
        degisti = False
        for e in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', []):
            dll = e.dll.decode()
            adlar = [adi(i) for i in e.imports]
            if not cevrilmeli(dll, adlar):
                continue
            if None in adlar:
                sys.exit(f'HATA: {os.path.basename(yol)} {dll} sıra numarasıyla içe aktarıyor; yönlendirilemez.')
            asil = dll[:-4] if dll.lower().endswith('.dll') else dll
            for a in adlar:
                if a in YAZILAN:
                    satir = f'    {a}=bb_{a}'
                elif dll.lower().startswith('api-ms-win-'):
                    sys.exit(f'HATA: {dll}!{a} bbw7.c\'de yazılı değil (API kümesi yönlendirilemez).')
                else:
                    satir = f'    {a}={asil}.{a}'
                onceki = yonlendir.get(a)
                if onceki and onceki != satir:
                    sys.exit(f'HATA: {a} iki farklı DLL\'den geliyor ({onceki.strip()} / {satir.strip()}).')
                yonlendir[a] = satir
            uzunluk = len(e.dll)
            yeni = SHIM.encode().ljust(uzunluk, b'\0')
            if len(SHIM) > uzunluk:
                sys.exit(f'HATA: {dll} adı {SHIM} için kısa.')
            pe.set_bytes_at_rva(e.struct.Name, yeni)
            print(f'  {os.path.basename(yol)}: {dll} → {SHIM} ({len(adlar)} işlev)')
            degisti = True
        oh = pe.OPTIONAL_HEADER
        if (oh.MajorSubsystemVersion, oh.MinorSubsystemVersion) > (6, 1):
            oh.MajorSubsystemVersion, oh.MinorSubsystemVersion = 6, 1
            degisti = True
        if (oh.MajorOperatingSystemVersion, oh.MinorOperatingSystemVersion) > (6, 1):
            oh.MajorOperatingSystemVersion, oh.MinorOperatingSystemVersion = 6, 1
            degisti = True
        if degisti:
            oh.CheckSum = pe.generate_checksum()
            veri = pe.write()
            pe.close()
            with open(yol, 'wb') as f:
                f.write(veri)
        else:
            pe.close()
    # Her iki ucu da garanti olsun diye yazılanların hepsi dışa aktarılır.
    for a in sorted(YAZILAN):
        yonlendir.setdefault(a, f'    {a}=bb_{a}')
    with open(def_yolu, 'w', encoding='ascii') as f:
        f.write('LIBRARY BBW7\nEXPORTS\n')
        f.write('\n'.join(yonlendir[a] for a in sorted(yonlendir)) + '\n')
    print(f'bbw7.def: {len(yonlendir)} dışa aktarma')


def denetle(dizin):
    paket = {os.path.basename(y).lower(): y for y in ikililer(dizin)}

    disa = {}
    for ad, yol in paket.items():
        pe = ac(yol)
        disa[ad] = {x.name.decode() for x in getattr(pe, 'DIRECTORY_ENTRY_EXPORT', None).symbols if x.name} \
            if hasattr(pe, 'DIRECTORY_ENTRY_EXPORT') else set()
        pe.close()
    sorun = []
    for ad, yol in paket.items():
        pe = ac(yol)
        tablolar = [(e, '') for e in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', [])] + \
                   [(e, ' (gecikmeli)') for e in getattr(pe, 'DIRECTORY_ENTRY_DELAY_IMPORT', [])]
        oh = pe.OPTIONAL_HEADER
        if (oh.MajorSubsystemVersion, oh.MinorSubsystemVersion) > (6, 1):
            sorun.append(f'{ad}: alt sistem sürümü {oh.MajorSubsystemVersion}.{oh.MinorSubsystemVersion}')
        for e, tur in tablolar:
            dll = e.dll.decode().lower()
            gecikmeli = bool(tur)
            for i in e.imports:
                a = adi(i)
                if dll in paket:  # pakette: işlev o dosyada olmalı
                    if a and a not in disa[dll]:
                        sorun.append(f'{ad}{tur}: {dll}!{a} paketteki dosyada yok')
                    continue
                if gecikmeli:
                    continue  # gecikmeli: yalnız çağrılınca yüklenir
                if dll in WIN8_DLL or (dll.startswith('api-ms-win-core-') and dll not in WIN7_APISET):
                    sorun.append(f'{ad}: {dll}!{a} (Windows 7\'de yok)')
                elif a in WIN8_ISLEV:
                    sorun.append(f'{ad}: {dll}!{a} (Windows 8+ işlevi)')
        pe.close()
    if sorun:
        print('Windows 7 uyumsuzlukları:\n  ' + '\n  '.join(sorun))
        sys.exit(1)
    print(f'Windows 7 denetimi temiz ({len(paket)} dosya).')


if __name__ == '__main__':
    if len(sys.argv) >= 4 and sys.argv[1] == 'yamala':
        yamala(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == 'denetle':
        denetle(sys.argv[2])
    else:
        sys.exit(__doc__)
