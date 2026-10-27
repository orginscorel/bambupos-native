"""BamBumPOS pos-win7 dalı — Windows 7 SP1 x64 içe aktarma denetimi.

    python -I w7_denetim.py <paket_dizini> [rapor.txt]

Paketteki HER .exe/.dll'in (FFI ile sonradan açılanlar dahil) içe aktarma
tablolarını tarar:
  • pakette olan DLL'den alınan işlev o DLL'de var mı,
  • Windows 7'de hiç olmayan sistem DLL'i / API kümesi var mı,
  • bilinen Windows 8+ işlevi var mı,
  • PE başlığındaki "en az Windows" sürümü 6.1'den (Windows 7) büyük mü.
Gecikmeli (delay-load) içe aktarmalar UYARI olarak raporlanır (yalnız
çağrılınca yüklenir). Açılışta yüklenen zincirde sorun varsa 1 ile çıkar.

Bu, yalnızca statik bir denetimdir; gerçek Windows 7 SP1 makinede deneme
yerine geçmez.
"""
import glob
import os
import sys

import pefile

# Windows 7 SP1'de bulunmayan sistem DLL'leri.
WIN8_DLL = {
    'shcore.dll', 'dcomp.dll', 'd3d12.dll', 'dxcore.dll', 'coremessaging.dll', 'windows.storage.dll',
    'combase.dll', 'wintypes.dll', 'twinapi.appcore.dll', 'mrmcorer.dll',
    'd3d11on12.dll',
}

# Windows 7 SP1'de bulunan API kümeleri.
WIN7_APISET = {f'api-ms-win-core-{a}-l1-1-0.dll' for a in (
    'console datetime debug delayload errorhandling fibers file handle heap interlocked io '
    'libraryloader localization localregistry memory misc namedpipe processenvironment '
    'processthreads profile rtlsupport string synch sysinfo threadpool util xstate').split()}
WIN7_APISET |= {
    'api-ms-win-security-base-l1-1-0.dll', 'api-ms-win-security-lsalookup-l1-1-0.dll',
    'api-ms-win-security-sddl-l1-1-0.dll', 'api-ms-win-core-processthreads-l1-1-1.dll',
}

# Windows 7'de OLMAYAN, bilinen işlevler (Windows 8 / 8.1 / 10 / 11).
WIN8_ISLEV = {
    # kernel32 / kernelbase
    'GetSystemTimePreciseAsFileTime', 'CreateFile2', 'CopyFile2', 'SetThreadInformation', 'GetThreadInformation',
    'GetOverlappedResultEx', 'PrefetchVirtualMemory', 'SetThreadDescription', 'GetThreadDescription',
    'GetFirmwareType', 'GetProcessMitigationPolicy', 'SetProcessMitigationPolicy', 'GetPackageFamilyName',
    'GetCurrentPackageId', 'GetCurrentPackageFullName', 'GetCurrentPackagePath', 'GetPackagePathByFullName',
    'CompareObjectHandles', 'MapViewOfFile3', 'VirtualAlloc2', 'MapViewOfFileFromApp', 'VirtualAllocFromApp',
    'MapViewOfFileNuma2', 'GetSystemCpuSetInformation', 'SetThreadSelectedCpuSets', 'DiscardVirtualMemory',
    'OfferVirtualMemory', 'ReclaimVirtualMemory', 'GetCurrentThreadStackLimits', 'WaitOnAddress',
    'WakeByAddressAll', 'WakeByAddressSingle', 'InitializeSynchronizationBarrier', 'EnterSynchronizationBarrier',
    'DeleteSynchronizationBarrier', 'SetThreadpoolTimerEx', 'SetThreadpoolWaitEx', 'QueryUnbiasedInterruptTimePrecise',
    'QueryInterruptTime', 'QueryInterruptTimePrecise', 'IsWow64Process2', 'GetMachineTypeAttributes',
    'SetProcessValidCallTargets', 'GetFileInformationByName', 'GetQueuedCompletionStatusEx2',
    'RtlAddGrowableFunctionTable', 'RtlDeleteGrowableFunctionTable', 'RtlGrowFunctionTable',
    'GetAppContainerNamedObjectPath', 'AppPolicyGetProcessTerminationMethod', 'AppPolicyGetThreadInitializationType',
    'GetTempPath2W', 'GetTempPath2A',
    # path / winrt / ws2
    'PathCchCombineEx', 'PathCchRemoveFileSpec', 'PathAllocCanonicalize', 'PathCchCanonicalizeEx', 'PathCchAppendEx',
    'RoGetActivationFactory', 'RoInitialize', 'RoUninitialize', 'RoActivateInstance', 'RoOriginateError',
    'RoOriginateErrorW', 'WindowsCreateString', 'WindowsCreateStringReference', 'WindowsDeleteString',
    'WindowsGetStringRawBuffer', 'GetHostNameW', 'GetAddrInfoExCancel', 'GetAddrInfoExOverlappedResult',
    # user32 / DPI / pointer
    'GetDpiForWindow', 'GetDpiForSystem', 'SetProcessDpiAwarenessContext', 'SetThreadDpiAwarenessContext',
    'GetThreadDpiAwarenessContext', 'GetWindowDpiAwarenessContext', 'GetAwarenessFromDpiAwarenessContext',
    'AreDpiAwarenessContextsEqual', 'EnableNonClientDpiScaling', 'GetSystemMetricsForDpi', 'AdjustWindowRectExForDpi',
    'SystemParametersInfoForDpi', 'GetSystemDpiForProcess', 'GetDpiForMonitor', 'SetProcessDpiAwareness',
    'GetProcessDpiAwareness', 'LogicalToPhysicalPointForPerMonitorDPI', 'PhysicalToLogicalPointForPerMonitorDPI',
    'GetPointerType', 'GetPointerInfo', 'GetPointerFrameInfo', 'GetPointerTouchInfo', 'GetPointerPenInfo',
    'GetPointerDeviceRects', 'SkipPointerFrameMessages', 'EnableMouseInPointer', 'RegisterPointerDeviceNotifications',
    'InitializeTouchInjection', 'InjectTouchInput', 'CreateSyntheticPointerDevice', 'IsImmersiveProcess',
    'GetDisplayAutoRotationPreferences', 'SetDisplayAutoRotationPreferences', 'IsWindowArranged',
    'RegisterSuspendResumeNotification', 'UnregisterSuspendResumeNotification', 'GetIntegratedDisplaySize',
    'CreateDispatcherQueueController',
    # dxgi / d3d
    'CreateDXGIFactory2', 'DXGIGetDebugInterface1', 'DXGIDeclareAdapterRemovalSupport', 'D3D12CreateDevice',
    'DCompositionCreateDevice', 'DCompositionCreateDevice2', 'DCompositionCreateDevice3',
}

# Win7'de yalnız KB2533623 (ya da yerine geçen KB3063858) güncellemesiyle gelenler.
KB2533623 = {'SetDefaultDllDirectories', 'AddDllDirectory', 'RemoveDllDirectory'}


def ac(yol):
    pe = pefile.PE(yol, fast_load=True)
    pe.parse_data_directories(directories=[
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_IMPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT'],
    ])
    return pe


def adi(i):
    return i.name.decode() if i.name else f'#{i.ordinal}'


def main():
    try:  # Windows konsolu cp1252: Türkçe çıktı patlamasın.
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass
    dizin = sys.argv[1]
    rapor_yolu = sys.argv[2] if len(sys.argv) > 2 else None
    paket = {}
    for f in glob.glob(os.path.join(dizin, '**', '*'), recursive=True):
        if f.lower().endswith(('.exe', '.dll')) and os.path.isfile(f):
            paket.setdefault(os.path.basename(f).lower(), f)

    disa, tablolar = {}, {}
    for ad, yol in paket.items():
        pe = ac(yol)
        exp = getattr(pe, 'DIRECTORY_ENTRY_EXPORT', None)
        disa[ad] = {x.name.decode() for x in exp.symbols if x.name} if exp else set()
        oh = pe.OPTIONAL_HEADER
        tablolar[ad] = {
            'imp': [(e.dll.decode().lower(), [adi(i) for i in e.imports]) for e in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', [])],
            'gec': [(e.dll.decode().lower(), [adi(i) for i in e.imports]) for e in getattr(pe, 'DIRECTORY_ENTRY_DELAY_IMPORT', [])],
            'alt': (oh.MajorSubsystemVersion, oh.MinorSubsystemVersion),
            'os': (oh.MajorOperatingSystemVersion, oh.MinorOperatingSystemVersion),
            'mak': pe.FILE_HEADER.Machine,
        }
        pe.close()

    # Açılış zinciri: exe'den başlayıp hem normal hem gecikmeli (ön denetimde
    # main.cpp yükler) içe aktarmalarla paketteki DLL'lere uzanır.
    exe = [k for k in paket if k.endswith('.exe')]
    zincir, sira = set(exe), list(exe)
    while sira:
        k = sira.pop()
        for d, _ in tablolar[k]['imp'] + tablolar[k]['gec']:
            if d in paket and d not in zincir:
                zincir.add(d)
                sira.append(d)

    satirlar, hata, uyari = [], [], []

    def sorun(ad, metin, gecikmeli=False):
        hedef = uyari if (gecikmeli or ad not in zincir) else hata
        hedef.append(f'{ad}: {metin}')

    for ad in sorted(paket):
        t = tablolar[ad]
        if t['mak'] != 0x8664:
            sorun(ad, f'x64 değil (makine {hex(t["mak"])})')
        # Alt sistem sürümünü Windows 7 yükleyicisi yalnız EXE için denetler;
        # DLL'lerde (ör. Windows 10 SDK'nın Windows 7 için dağıttığı UCRT
        # api-ms-win-*.dll'leri: 10.0, d3dcompiler_47.dll: 6.2) bakmaz.
        if ad.endswith('.exe') and t['alt'] > (6, 1):
            sorun(ad, f'PE alt sistem sürümü {t["alt"][0]}.{t["alt"][1]} > 6.1 (Windows 7 yükleyicisi reddeder)')
        for tur, liste in (('', t['imp']), (' (gecikmeli)', t['gec'])):
            gec = bool(tur)
            for d, islevler in liste:
                if d in paket:
                    eksik = [i for i in islevler if not i.startswith('#') and i not in disa[d]]
                    for i in eksik:
                        sorun(ad, f'{d}!{i}{tur} paketteki DLL\'de yok', gec)
                    continue
                if d.startswith('api-ms-win-crt-') or d in ('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll',
                                                          'ucrtbase.dll', 'concrt140.dll', 'msvcp140_1.dll',
                                                          'msvcp140_2.dll'):
                    sorun(ad, f'{d}{tur} pakette yok (C++ / Universal CRT eklenmeli)', gec)
                    continue
                if d in WIN8_DLL:
                    sorun(ad, f'{d}{tur} Windows 7\'de yok', gec)
                    continue
                if d.startswith('api-ms-win-') and d not in WIN7_APISET:
                    sorun(ad, f'{d}{tur} API kümesi Windows 7\'de yok ({", ".join(islevler[:6])})', gec)
                    continue
                for i in islevler:
                    if i in WIN8_ISLEV:
                        sorun(ad, f'{d}!{i}{tur} Windows 8+ işlevi', gec)
                    elif i in KB2533623:
                        uyari.append(f'{ad}: {d}!{i}{tur} Windows 7\'de KB2533623 güncellemesi ister')

    satirlar.append(f'Windows 7 SP1 x64 içe aktarma denetimi — {len(paket)} ikili dosya, açılış zincirinde {len(zincir)}')
    satirlar.append('Açılış zinciri: ' + ', '.join(sorted(zincir)))
    satirlar.append('Zincir dışı (FFI / sonradan yüklenen): ' + (', '.join(sorted(set(paket) - zincir)) or '-'))
    satirlar.append('')
    satirlar.append(f'HATA ({len(hata)}):' + ('' if hata else ' yok'))
    satirlar += [f'  ✗ {x}' for x in hata]
    satirlar.append(f'UYARI ({len(uyari)}):' + ('' if uyari else ' yok'))
    satirlar += [f'  ! {x}' for x in uyari]
    satirlar.append('')
    satirlar.append('Dosya başına sistem DLL içe aktarmaları:')
    for ad in sorted(paket):
        sistem = sorted({d for d, _ in tablolar[ad]['imp'] if d not in paket})
        gec = sorted({d for d, _ in tablolar[ad]['gec']})
        satirlar.append(f'  {ad} [alt sistem {tablolar[ad]["alt"][0]}.{tablolar[ad]["alt"][1]}]: '
                        f'{", ".join(sistem) or "-"}' + (f' | gecikmeli: {", ".join(gec)}' if gec else ''))
    metin = '\n'.join(satirlar)
    print(metin)
    if rapor_yolu:
        with open(rapor_yolu, 'w', encoding='utf-8-sig') as f:
            f.write(metin.replace('\n', '\r\n') + '\r\n')
    sys.exit(1 if hata else 0)


if __name__ == '__main__':
    main()
