{{--
    Kiosk kabuğu (Faz 8 — Blade + hafif vanilla JS; ADR-003'ün public menü
    gerekçesinin kiosk uyarlaması, karar gerekçesi rapor + routes/kiosk.php).

    ÖNEMLİ (§18): Bu yüzey OTURUMSUZDUR. Çerez yok, localStorage yok,
    sessionStorage yok — sepet/isim yalnız sayfanın JS belleğindedir.
    "Sıfırlama" = location.reload(): önceki müşteriden hiçbir iz kalmaz.
--}}
<!DOCTYPE html>
<html lang="{{ app()->getLocale() }}" data-kiosk-a11y="0">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
    <meta name="robots" content="noindex, nofollow">
    <title>@yield('title', 'Kiosk')</title>
    <meta name="theme-color" content="#1d4ed8">
    <link rel="preload" href="/fonts/poppins-400-latin.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/fonts/poppins-400-latin-ext.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/fonts/poppins-700-latin.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/fonts/poppins-700-latin-ext.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="stylesheet" href="/assets/kiosk.css?v=20260725.4">
</head>
<body class="k-body">
    @yield('content')
    @stack('scripts')
</body>
</html>
