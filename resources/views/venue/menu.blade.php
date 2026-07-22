{{--
    /m/{token} — Public QR menüsü (Faz 2/3, ADR-003: Blade + hafif vanilla JS).
    Kiracı+şube+masa YALNIZ token'dan çözülür (ADR-008); sayfada oturuma/kişiye
    özel içerik yoktur (ADR-011 tam-sayfa cache). Arama, filtreler, ürün detayı
    ve sepet tamamen istemci tarafındadır; veri #qrm-data JSON bloğundadır.
--}}
@extends('public.layout')

@section('title', $tenantName.' — '.__('menu.title_suffix'))

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
        {{-- Servis istekleri: aynı public API'ye bağlanır; uç yoksa dürüst mesaj (sahte başarı yok) --}}
        <div class="m-services" role="group" aria-label="Servis istekleri">
            <button type="button" class="m-services__btn" data-service="waiter">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
                {{ __('menu.call_waiter') }}
            </button>
            <button type="button" class="m-services__btn" data-service="bill">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/><path d="M12 17.5v-11"/></svg>
                {{ __('menu.request_bill') }}
            </button>
            <button type="button" class="m-services__btn" data-service="water">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"/></svg>
                {{ __('menu.request_water') }}
            </button>
        </div>
    </header>

    @if ($categories !== [])
        {{-- Arama + filtre araç çubuğu (istemci tarafı; sunucuya istek atmaz → cache korunur) --}}
        <div class="m-toolbar">
            <div class="m-toolbar__search">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" data-q placeholder="{{ __('menu.search_placeholder') }}" aria-label="{{ __('menu.search_placeholder') }}" autocomplete="off">
            </div>
            <button type="button" class="m-toolbar__filter" data-open-filter>
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>
                {{ __('menu.filters') }}
                <span class="m-toolbar__badge" data-filter-badge hidden>0</span>
            </button>
        </div>

        @include('public.partials.category-strip')
    @endif

    <main class="m-main">
        @if ($categories === [])
            <section class="m-section" aria-label="Bilgi">
                <h2 class="m-section__title">{{ __('menu.title_suffix') }}</h2>
                <p class="m-empty">{{ __('menu.menu_empty') }}</p>
            </section>
        @else
            @foreach ($categories as $category)
                <section class="m-section" id="kategori-{{ $category['id'] }}" data-cat-section="{{ $category['id'] }}" aria-labelledby="kategori-baslik-{{ $category['id'] }}">
                    <h2 class="m-section__title" id="kategori-baslik-{{ $category['id'] }}">{{ $category['name'] }}</h2>
                    <div class="m-section__items">
                        @foreach ($products[$category['id']] ?? [] as $product)
                            @include('public.partials.product-card')
                        @endforeach
                    </div>
                </section>
            @endforeach

            <div class="m-noresults" data-noresults hidden>
                <p class="m-noresults__title">{{ __('menu.js.no_results') }}</p>
                <p class="m-noresults__hint">{{ __('menu.js.no_results_hint') }}</p>
                <button type="button" class="m-btn m-btn--ghost" data-clear-filters>{{ __('menu.js.filters_clear') }}</button>
            </div>
        @endif

        @if ($branchInfo !== [])
            <section class="m-section m-info" aria-labelledby="isletme-baslik">
                <h2 class="m-section__title" id="isletme-baslik">{{ __('menu.info_title') }}</h2>
                @if (!empty($branchInfo['address']))
                    <p class="m-info__row">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/></svg>
                        <span><span class="sr-only">{{ __('menu.info_address') }}: </span>{{ $branchInfo['address'] }}</span>
                    </p>
                @endif
                @if (!empty($branchInfo['phone']))
                    <p class="m-info__row">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.832 16.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 6.392 6.384"/></svg>
                        <a href="tel:{{ preg_replace('/[^+\d]/', '', $branchInfo['phone']) }}">{{ $branchInfo['phone'] }}</a>
                    </p>
                @endif
            </section>
        @endif

        <footer class="m-footer">
            <p>{{ __('menu.powered_by') }}</p>
        </footer>
    </main>

    @include('public.partials.cart-bar')

    {{-- Ortak karartma + alt sayfalar (filtre / detay / sepet) --}}
    <div class="m-scrim" data-scrim hidden></div>

    <section class="m-sheet" data-sheet="filter" role="dialog" aria-modal="true" aria-labelledby="qrm-filter-t" hidden>
        <header class="m-sheet__head">
            <h2 class="m-sheet__title" id="qrm-filter-t">{{ __('menu.js.filters_title') }}</h2>
            <button type="button" class="m-sheet__close" data-close aria-label="{{ __('menu.js.close') }}">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
            </button>
        </header>
        <div class="m-sheet__body">
            <fieldset class="m-fset">
                <legend>{{ __('menu.js.filters_cats') }}</legend>
                <div class="m-chips">
                    @foreach ($categories as $category)
                        <label class="m-chip"><input type="checkbox" data-f-cat value="{{ $category['id'] }}"><span>{{ $category['name'] }}</span></label>
                    @endforeach
                </div>
            </fieldset>
            <fieldset class="m-fset">
                <legend>{{ __('menu.js.filters_diet') }}</legend>
                <div class="m-chips">
                    @foreach ($payload['allergens'] as $aid => $a)
                        @if ($a['k'] === 'diet')
                            <label class="m-chip"><input type="checkbox" data-f-diet value="{{ $aid }}"><span>{{ $a['n'] }}</span></label>
                        @endif
                    @endforeach
                </div>
            </fieldset>
            <fieldset class="m-fset">
                <legend>{{ __('menu.js.filters_allergens') }}</legend>
                <div class="m-chips">
                    @foreach ($payload['allergens'] as $aid => $a)
                        @if ($a['k'] === 'allergen')
                            <label class="m-chip m-chip--danger"><input type="checkbox" data-f-al value="{{ $aid }}"><span>{{ $a['n'] }}</span></label>
                        @endif
                    @endforeach
                </div>
            </fieldset>
            <fieldset class="m-fset">
                <legend>{{ __('menu.js.filters_price') }}</legend>
                <div class="m-pricerange">
                    <input type="number" inputmode="numeric" min="0" data-f-pmin placeholder="{{ __('menu.js.filters_price_min') }}" aria-label="{{ __('menu.js.filters_price_min') }} (₺)">
                    <span aria-hidden="true">—</span>
                    <input type="number" inputmode="numeric" min="0" data-f-pmax placeholder="{{ __('menu.js.filters_price_max') }}" aria-label="{{ __('menu.js.filters_price_max') }} (₺)">
                </div>
            </fieldset>
        </div>
        <footer class="m-sheet__foot">
            <button type="button" class="m-btn m-btn--ghost" data-clear-filters>{{ __('menu.js.filters_clear') }}</button>
            <button type="button" class="m-btn m-btn--primary" data-close><span data-filter-count>{{ __('menu.js.filters_apply') }}</span></button>
        </footer>
    </section>

    <section class="m-sheet" data-sheet="detail" role="dialog" aria-modal="true" aria-label="Ürün detayı" hidden>
        <header class="m-sheet__head">
            <h2 class="m-sheet__title" data-detail-title></h2>
            <button type="button" class="m-sheet__close" data-close aria-label="{{ __('menu.js.close') }}">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
            </button>
        </header>
        <div class="m-sheet__body" data-detail-body></div>
        <footer class="m-sheet__foot" data-detail-foot></footer>
    </section>

    <section class="m-sheet" data-sheet="cart" role="dialog" aria-modal="true" aria-labelledby="qrm-cart-t" hidden>
        <header class="m-sheet__head">
            <h2 class="m-sheet__title" id="qrm-cart-t">{{ __('menu.js.cart_title') }}</h2>
            <button type="button" class="m-sheet__close" data-close aria-label="{{ __('menu.js.close') }}">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
            </button>
        </header>
        <div class="m-sheet__body" data-cart-body></div>
        <footer class="m-sheet__foot m-sheet__foot--col" data-cart-foot></footer>
    </section>

    <div class="m-toast" role="status" aria-live="polite" data-toast hidden></div>

    {{-- Menü verisi (istemci: detay, sepet, filtre) — kişiye özel HİÇBİR şey içermez --}}
    <script type="application/json" id="qrm-data">@json($payload)</script>
    <script>
        window.QRM_L = @json(__('menu.js'));
        {{-- Uç yapılandırması TEK yer: PublicMenuController (Siparis-Adisyon API'si yayınlanınca doldurulur) --}}
        window.QRM_CFG = { orders: @json($orderEndpoint), service: @json($serviceEndpoint) };
    </script>
@endsection
