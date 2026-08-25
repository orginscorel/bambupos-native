<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
        <title inertia>{{ config('app.name', 'QR Menu') }}</title>
        {{-- Sunucu saati (ms epoch): panel saati istemci saatine güvenmez,
             bu değerden ofset hesaplar (PanelLayout.vue) --}}
        <meta name="app-server-epoch" content="{{ now()->getTimestampMs() }}" />
        {{-- Favicon: public/favicon.ico BOŞTU (0 bayt) → sekmede kimliksiz
             görünüyordu. SVG favicon modern tarayıcıların tamamında çalışır ve
             tek dosyayla her boyutta net kalır; ?v= sürüm damgası, tarayıcı
             favicon'u agresif cache'lediği için gerekli. --}}
        <link rel="icon" href="/favicon.svg?v=2" type="image/svg+xml" />
        <link rel="apple-touch-icon" href="/favicon.svg?v=2" />

        {{-- UYGULAMA KURULUMU (PWA): panelin telefona/tablete/bilgisayara
             "uygulama" olarak kurulabilmesi için manifest + tema rengi.
             Kurulunca kendi simgesiyle, tarayıcı çubuğu olmadan, tam ekran
             açılır ve bildirim alabilir. Kurulum rehberi: /native --}}
        <link rel="manifest" href="/bambumpos.webmanifest?v=2" />
        <meta name="theme-color" content="#5443D2" />
        <meta name="application-name" content="BamBumPOS" />
        <meta name="mobile-web-app-capable" content="yes" />
        {{-- iOS: ana ekrana eklenince tam ekran + koyu durum çubuğu --}}
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
        <meta name="apple-mobile-web-app-title" content="BamBumPOS" />
        <link rel="apple-touch-icon" sizes="192x192" href="/icons/bambumpos-192.png" />
        {{-- Poppins gövde (400) ön yükleme: Türkçe arayüz latin + latin-ext'in
             ikisini de kullanır; 500/700 CSS keşfiyle hemen ardından gelir --}}
        <link rel="preload" href="/fonts/poppins-400-latin.woff2" as="font" type="font/woff2" crossorigin />
        <link rel="preload" href="/fonts/poppins-400-latin-ext.woff2" as="font" type="font/woff2" crossorigin />
        {{-- Tema önyüklemesi: localStorage > sistem tercihi; FOUC engellenir --}}
        <script>
            (function () {
                try {
                    var t = localStorage.getItem('theme');
                    if (t !== 'dark' && t !== 'light') {
                        t = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
                    }
                    document.documentElement.dataset.theme = t;
                } catch (e) {
                    document.documentElement.dataset.theme = 'light';
                }
            })();
        </script>
        {{-- Personel Portalı (host-farkındalıklı): yalnız portal host'unda
             kurulabilir PWA manifest + mobil meta. Panel host'unda HİÇ
             render edilmez → panel head'i BYTE-AYNI kalır. --}}
        @if (request()->getHost() === config('portal.host'))
            <link rel="manifest" href="/portal.webmanifest" />
            <meta name="theme-color" content="#2563eb" />
            <meta name="mobile-web-app-capable" content="yes" />
            <meta name="apple-mobile-web-app-capable" content="yes" />
            <meta name="apple-mobile-web-app-status-bar-style" content="default" />
            <meta name="apple-mobile-web-app-title" content="Personel" />
        @endif
        @vite(['resources/css/app.css', 'resources/js/app.ts'])
        @inertiaHead
    </head>
    <body class="font-sans antialiased">
        {{-- AÇILIŞ EKRANI: uygulama kurulu açıldığında Vue yüklenene kadar
             beyaz ekran görünüyordu ("uygulama açılmadı" hissi). Marka
             ekranı + belirsiz ilerleme çubuğu, Vue mount olunca app.ts
             tarafından kaldırılır (#bhx-splash). --}}
        <div id="bhx-splash" aria-hidden="true">
            <div class="bhx-splash-mark">
                <img src="/favicon.svg?v=2" width="72" height="72" alt="" />
            </div>
            <p class="bhx-splash-name">BamBumPOS</p>
            <div class="bhx-splash-bar"><span></span></div>
        </div>
        <style>
            #bhx-splash{position:fixed;inset:0;z-index:2147483000;display:flex;flex-direction:column;
                align-items:center;justify-content:center;gap:14px;background:#5443D2;
                transition:opacity .28s ease, visibility .28s ease}
            #bhx-splash.bhx-hide{opacity:0;visibility:hidden}
            .bhx-splash-mark{width:88px;height:88px;border-radius:22px;background:rgba(255,255,255,.14);
                display:flex;align-items:center;justify-content:center;
                box-shadow:0 12px 40px rgba(0,0,0,.22)}
            .bhx-splash-name{margin:0;color:#fff;font:700 17px/1.2 Poppins,system-ui,sans-serif;
                letter-spacing:.02em}
            .bhx-splash-bar{width:168px;height:4px;border-radius:99px;background:rgba(255,255,255,.22);
                overflow:hidden}
            .bhx-splash-bar span{display:block;width:40%;height:100%;border-radius:99px;background:#fff;
                animation:bhx-slide 1.1s ease-in-out infinite}
            @keyframes bhx-slide{0%{transform:translateX(-100%)}100%{transform:translateX(320%)}}
            @media (prefers-reduced-motion: reduce){
                .bhx-splash-bar span{animation:none;width:100%}
            }
        </style>

        @inertia
    </body>
</html>
