@php
    $site = config('site');
    $seo = $site['seo'];
    $pageTitle = trim($__env->yieldContent('title')) ?: $seo['default_title'];
    $fullTitle = $pageTitle . (str_contains($pageTitle, 'BamBumPOS') ? '' : $seo['title_suffix']);
    $desc = trim($__env->yieldContent('description')) ?: $seo['default_description'];
    $canonical = trim($__env->yieldContent('canonical')) ?: url()->current();
    $ogImage = trim($__env->yieldContent('og_image')) ?: url($seo['og_image']);
    $bodyClass = trim($__env->yieldContent('body_class'));
    $ver = '202607311959';
@endphp
<!doctype html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <script>document.documentElement.classList.add('js')</script>
    <title>{{ $fullTitle }}</title>
    <meta name="description" content="{{ $desc }}">
    <link rel="canonical" href="{{ $canonical }}">
    <meta name="theme-color" content="#0b2018">
    @hasSection('robots')<meta name="robots" content="@yield('robots')">@endif

    {{-- Open Graph / Twitter --}}
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="BamBumPOS">
    <meta property="og:title" content="{{ $pageTitle }}">
    <meta property="og:description" content="{{ $desc }}">
    <meta property="og:url" content="{{ $canonical }}">
    <meta property="og:image" content="{{ $ogImage }}">
    <meta property="og:locale" content="{{ $seo['locale'] }}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{{ $pageTitle }}">
    <meta name="twitter:description" content="{{ $desc }}">
    <meta name="twitter:image" content="{{ $ogImage }}">

    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect width='100' height='100' rx='22' fill='%232563eb'/><text x='50' y='72' font-size='60' text-anchor='middle' fill='white' font-family='Arial' font-weight='bold'>B</text></svg>">
    <link rel="preload" as="font" type="font/woff2" href="/fonts/poppins-500-latin.woff2" crossorigin>
    <link rel="preload" as="font" type="font/woff2" href="/fonts/poppins-700-latin.woff2" crossorigin>
    <link rel="stylesheet" href="{{ asset('assets/site/site.css') }}?v={{ $ver }}">
    @stack('head')

    {{-- Organization schema (her sayfada) --}}
    <script type="application/ld+json">
    {!! json_encode([
        '@'.'context' => 'https://schema.org',
        '@type' => 'Organization',
        'name' => 'BamBumPOS',
        'url' => url('/'),
        'description' => $seo['default_description'],
        'contactPoint' => [
            '@type' => 'ContactPoint',
            'contactType' => 'sales',
            'email' => $site['contact']['email'],
            'telephone' => $site['contact']['phone_raw'],
        ],
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) !!}
    </script>
    @stack('schema')
</head>
<body @if($bodyClass) class="{{ $bodyClass }}" @endif>
    @includeWhen($site['announcement']['enabled'] ?? false, 'marketing.partials.announcement')
    @include('marketing.partials.header')

    <main>
        @yield('content')
    </main>

    @include('marketing.partials.footer')

    <div class="scrim" id="scrim"></div>
    <script src="{{ asset('assets/site/site.js') }}?v={{ $ver }}" defer></script>
    @stack('scripts')
</body>
</html>
