{{--
    /m/{token} — QR açılış menüsü (Venue fazı).
    Kiracı+şube+masa YALNIZ token'dan çözülür (ADR-008); bu sayfada
    oturuma/kişiye özel içerik yoktur (ADR-011 tam-sayfa cache).
    Catalog public menü fazı bu görünümü kategori/varyantlarla devralacak;
    veri süzgeci (token'dan çözülen tenant/branch) aynı kalacak.
--}}
@extends('public.layout')

@section('title', $tenantName.' — Menü')

@section('content')
    <header class="m-header">
        <div class="m-header__row">
            <span class="m-header__logo" aria-hidden="true">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="5" height="5" x="3" y="3" rx="1"/><rect width="5" height="5" x="16" y="3" rx="1"/><rect width="5" height="5" x="3" y="16" rx="1"/><path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/><path d="M12 7v3a2 2 0 0 1-2 2H7"/><path d="M3 12h.01"/><path d="M12 3h.01"/><path d="M12 16v.01"/><path d="M16 12h1"/><path d="M21 12v.01"/><path d="M12 21v-1"/></svg>
            </span>
            <div class="m-header__meta">
                <h1 class="m-header__name">{{ $tenantName }}</h1>
                <p class="m-header__table">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
                    {{ $branchName }}@if ($tableLabel) — Masa: {{ $tableLabel }} @endif
                </p>
            </div>
        </div>
    </header>

    <main class="m-main">
        @if ($products->isEmpty())
            <section class="m-section" aria-label="Bilgi">
                <h2 class="m-section__title">Menü</h2>
                <p style="padding: 12px 0; color: #666; font-size: 15px;">
                    Bu şube menüsünü henüz yayınlamadı. Lütfen personelden basılı menü isteyin.
                </p>
            </section>
        @else
            <section class="m-section" aria-labelledby="menu-baslik">
                <h2 class="m-section__title" id="menu-baslik">Menü</h2>
                <div class="m-section__items">
                    @foreach ($products as $product)
                        <article class="m-product">
                            <div class="m-product__body">
                                <h3 class="m-product__name">{{ $product->name }}</h3>
                                <p class="m-product__price">₺ {{ number_format($product->price_minor / 100, 2, ',', '.') }}</p>
                            </div>
                        </article>
                    @endforeach
                </div>
            </section>
        @endif

        <footer class="m-footer">
            <p>powered by bogahost</p>
        </footer>
    </main>
@endsection
