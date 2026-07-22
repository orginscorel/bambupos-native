{{--
    Public QR menü kabuğu (ADR-003: Blade + hafif vanilla JS; JS çerçevesi YOK).
    Tam-sayfa cache uyumu (ADR-011): bu katmanda oturuma/kişiye özel içerik olamaz.
    Kiracı teması: ileride 'tenant-theme' stack'ine tek <style> bloğu basılır
    (--brand-* / --m-* değişkenleri ezilir); menu.css yeniden derlenmez.
--}}
<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <title>@yield('title', 'Menü')</title>
    <meta name="theme-color" content="#c2410c">
    {{-- Poppins ön yükleme (self-host): Türkçe menü metni latin + latin-ext'in
         ikisini de kullanır; 4 dosya ≈ 27KB, font-display: swap ile bloklamaz --}}
    <link rel="preload" href="/fonts/poppins-400-latin.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/fonts/poppins-400-latin-ext.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/fonts/poppins-700-latin.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/fonts/poppins-700-latin-ext.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="stylesheet" href="/assets/menu.css?v=20260722.1">
    @stack('tenant-theme')
</head>
<body>
    @yield('content')
    <script src="/assets/menu.js?v=20260722" defer></script>
</body>
</html>
