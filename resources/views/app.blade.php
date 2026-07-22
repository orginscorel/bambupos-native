<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
        <title inertia>{{ config('app.name', 'QR Menu') }}</title>
        {{-- Sunucu saati (ms epoch): panel saati istemci saatine güvenmez,
             bu değerden ofset hesaplar (PanelLayout.vue) --}}
        <meta name="app-server-epoch" content="{{ now()->getTimestampMs() }}" />
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
        @vite(['resources/css/app.css', 'resources/js/app.ts'])
        @inertiaHead
    </head>
    <body class="font-sans antialiased">
        @inertia
    </body>
</html>
