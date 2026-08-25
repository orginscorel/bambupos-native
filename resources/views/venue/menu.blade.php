{{--
    /m/{token} — Public QR menüsü (Faz 2/3, ADR-003: Blade + hafif vanilla JS).
    Kiracı+şube+masa YALNIZ token'dan çözülür (ADR-008); sayfada oturuma/kişiye
    özel içerik yoktur (ADR-011 tam-sayfa cache). Arama, filtreler, ürün detayı
    ve sepet tamamen istemci tarafındadır; veri #qrm-data JSON bloğundadır.
--}}
@extends('public.layout')

@section('title', $tenantName.' — '.__('menu.title_suffix'))

{{-- §9 feature-flag: "QR menüden sipariş" kapalıysa GÖVDEYE `m-no-order`
     sınıfı basılır → sepet/ekle kontrolleri CSS ile gizlenir (JS ile üretilen
     ürün-detay footer'ı dahil). Backend zaten sipariş POST'unu 403 ile
     reddeder; bu yalnız görünürlük. AYNI sınıf masasız "Genel Menü" QR'ında
     da (hasTable=false) basılır: backend sipariş ucu masasız istekte 404
     döner (PublicOrderController), o yüzden buton hiç gösterilmez — yanıltıcı
     "henüz devrede değil" hatasına düşülmez (bkz. aşağıdaki uyarı bandı).
     Çıktı token'a deterministik → cache korunur. --}}
@section('body_class', (($menuFeatures['qr_ordering'] ?? true) && !empty($hasTable)) ? '' : 'm-no-order')

@section('content')
    <header class="m-header">
        {{-- Dil seçici (sol üst): ?lang ile sunucu tarafı yeniden render; menü,
             İşletme Vitrini ve durum kartı tümü seçilen dilde. Query anahtarı
             cache'i dile göre ayırır (her dil kendi tam-sayfa cache'i). --}}
        @php($curLang = app()->getLocale())
        <nav class="m-langswitch" aria-label="{{ __('menu.language') }}">
            @foreach (['tr' => 'TR', 'en' => 'EN', 'de' => 'DE'] as $lc => $lbl)
                <a href="?lang={{ $lc }}" hreflang="{{ $lc }}"
                   class="m-langswitch__opt {{ $curLang === $lc ? 'is-active' : '' }}"
                   @if ($curLang === $lc) aria-current="true" @endif
                   rel="nofollow">{{ $lbl }}</a>
            @endforeach
        </nav>
        {{-- Koyu/açık tema düğmesi (sağ üst): cihaz tercihini elle geçersiz kılar,
             seçim localStorage'da kalıcı, geçiş yumuşak. --}}
        <button type="button" class="m-theme-toggle" data-theme-toggle aria-label="{{ __('menu.theme_toggle') }}" title="{{ __('menu.theme_toggle') }}" data-theme-fallback="Tema">
            <svg class="m-theme-toggle__moon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>
            <svg class="m-theme-toggle__sun" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg>
        </button>
        {{-- Ortalanmış kimlik bloğu: kafenin logosu (Ayarlar > İşletme / Marka)
             ortada ve büyük gösterilir — "avatar" değil, marka vitrinidir.
             Logo yoksa kasıtlı yedek: marka renkli dairede baş harf.
             Masa bilgisi altında küçük/ikincil kalır; başlık şişmez. --}}
        <div class="m-header__identity">
            @if (!empty($brandLogoUrl))
                <img class="m-header__logo m-header__logo--img" src="{{ $brandLogoUrl }}"
                     alt="{{ $tenantName }}" width="76" height="76" decoding="async">
            @else
                <span class="m-header__logo" aria-hidden="true">{{ mb_strtoupper(mb_substr(trim($tenantName), 0, 1), 'UTF-8') }}</span>
            @endif
            <h1 class="m-header__name">{{ $tenantName }}</h1>
            {{-- Kısa, işletmeye özgü OLMAYAN genel karşılama metni (sabit i18n) —
                 uydurma marka/kampanya iddiası değildir, yalnız kibar bir ilk izlenim. --}}
            <p class="m-header__welcome">{{ __('menu.welcome') }}</p>
            <div class="m-header__meta">
                @if ($tableLabel)
                    <p class="m-header__table">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
                        {{ __('menu.table_label') }}: {{ $tableLabel }}
                    </p>
                @endif
                {{-- Açık/kapalı rozeti: buildBranchInfo() bugünün çalışma saatine göre
                     hesaplar (İşletme Vitrini ile AYNI kaynak); saat tanımlı değilse
                     rozet hiç basılmaz (belirsiz durumu "kapalı" gibi göstermeyiz). --}}
                @if (array_key_exists('open_now', $branchInfo))
                    <span class="m-badge m-header__status {{ $branchInfo['open_now'] ? 'm-badge--open' : 'm-badge--closed' }}">
                        {{ $branchInfo['open_now'] ? __('menu.open_now') : __('menu.closed_now') }}
                    </span>
                @endif
            </div>
        </div>
        {{-- Servis istekleri: aynı public API'ye bağlanır; uç yoksa dürüst mesaj (sahte başarı yok).
             §9 feature-flag: "Garson/su/hesap çağır" kapalıysa blok HİÇ render edilmez (ADR: kapalı=yok).
             hasTable=false (masasız "Genel Menü" QR'ı): blok da HİÇ render edilmez — servis
             talebi backend'de masaya bağlıdır (ServiceRequest.table_id DB'de NOT NULL,
             ServiceRequestController masasız istekte 404 döner). --}}
        @if (!empty($hasTable) && (($menuFeatures['service_calls'] ?? true) || ($menuFeatures['sarjmatik'] ?? false)))
        <div class="m-services" role="group" aria-label="{{ __('menu.services_group') }}">
            @if ($menuFeatures['service_calls'] ?? true)
            <button type="button" class="m-services__btn m-services__btn--primary" data-service="waiter">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
                {{ __('menu.call_waiter') }}
            </button>
            <button type="button" class="m-services__btn" data-service="bill">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/><path d="M12 17.5v-11"/></svg>
                {{ __('menu.request_bill') }}
            </button>
            <button type="button" class="m-services__btn" data-service="water">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 2.69s5 6.15 5 10.31a5 5 0 0 1-10 0c0-4.16 5-10.31 5-10.31Z"/></svg>
                {{ __('menu.request_water') }}
            </button>
            @endif
            {{-- Şarjmatik eklentisi: yalnız 'sarjmatik' feature'ı açıkken görünür. --}}
            @if ($menuFeatures['sarjmatik'] ?? false)
            <button type="button" class="m-services__btn" data-service="sarjmatik">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/><path d="M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/></svg>
                {{ __('menu.js.request_sarjmatik') }}
            </button>
            @endif
        </div>
        @endif
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

    @if (!empty($preview))
        <div style="position:sticky;top:0;z-index:50;background:#1d4ed8;color:#fff;text-align:center;font-size:13px;font-weight:600;padding:8px 12px;">
            {{ __('menu.preview_banner') }}
        </div>
    @elseif (empty($hasTable) && (($menuFeatures['qr_ordering'] ?? true) || ($menuFeatures['service_calls'] ?? true) || ($menuFeatures['sarjmatik'] ?? false)))
        {{-- Masasız "Genel Menü" QR'ı (QrController::branchImage): işletme sipariş/servisi
             açık tutuyor ama BU QR masaya bağlı değil, backend sipariş/servis uçları bu
             yüzden çalışmaz (bkz. yukarıdaki body_class + m-services notları). Yanıltıcı
             "henüz devrede değil" hatası yerine baştan dürüst yönlendirme. --}}
        <div style="position:sticky;top:0;z-index:49;background:#334155;color:#fff;text-align:center;font-size:13px;font-weight:600;padding:8px 12px;">
            {{ __('menu.no_table_notice') }}
        </div>
    @endif

    <main class="m-main">
        {{-- Öne çıkanlar: yatay kaydırmalı şerit. Veri PublicMenuController::buildFeatured
             tarafından derlenir (öncelik: şef önerisi/çok satan işaretli görselli ürünler;
             yeterli yoksa kategori başına ilk görselli ürün). Kart, mevcut ürün kartıyla
             AYNI veri şeklini kullanır → tıklama menu.js'teki data-detail/data-add genel
             dinleyicileriyle çalışır (ayrı JS gerekmez); qr_ordering kapalıyken "ekle"
             düğmesi diğer tüm kartlarla aynı CSS kuralıyla (.m-no-order [data-add]) gizlenir. --}}
        @if (!empty($featured))
            <section class="m-section m-featured" aria-labelledby="one-cikanlar-baslik">
                <h2 class="m-section__title" id="one-cikanlar-baslik">{{ __('menu.featured_title') }}</h2>
                <div class="m-featured__scroll">
                    @foreach ($featured as $fp)
                        <article class="m-fcard" data-pid="{{ $fp['id'] }}">
                            <button type="button" class="m-fcard__open" data-detail="{{ $fp['id'] }}">
                                <span class="m-fcard__imgwrap">
                                    <img class="m-fcard__img" src="{{ $fp['image'] }}" alt="" loading="lazy" decoding="async" width="132" height="108">
                                    @if ($fp['is_bestseller'])
                                        <span class="m-tag m-tag--best m-fcard__badge">{{ __('menu.js.tag_best') }}</span>
                                    @elseif ($fp['is_chef_pick'])
                                        <span class="m-tag m-tag--chef m-fcard__badge">{{ __('menu.js.tag_chef') }}</span>
                                    @elseif ($fp['is_new'])
                                        <span class="m-tag m-tag--new m-fcard__badge">{{ __('menu.js.tag_new') }}</span>
                                    @endif
                                </span>
                                <span class="m-fcard__name">{{ $fp['name'] }}</span>
                                <span class="m-fcard__price">₺ {{ number_format($fp['price_minor'] / 100, 2, ',', '.') }}</span>
                            </button>
                            <button type="button" class="m-fcard__add" data-add="{{ $fp['id'] }}" aria-label="{{ $fp['name'] }} — {{ __('menu.js.add_to_cart') }}">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
                            </button>
                        </article>
                    @endforeach
                </div>
            </section>
        @endif

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
            @php($days = __('menu.days'))
            <section class="m-section m-info m-showcase" aria-labelledby="isletme-baslik">
                <h2 class="m-section__title" id="isletme-baslik">{{ __('menu.info_title') }}</h2>

                {{-- Çalışma saatleri: bugünkü durum başta, altında açılır tam liste --}}
                @if (!empty($branchInfo['hours']))
                    @php($openNow = $branchInfo['open_now'] ?? null)
                    @php($today = collect($branchInfo['hours'])->firstWhere('today', true))
                    <details class="m-sc-card m-sc-hours">
                        <summary class="m-sc-row m-sc-summary">
                            <span class="m-sc-ic" aria-hidden="true">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>
                            </span>
                            <span class="m-sc-main">
                                <span class="m-sc-label">{{ __('menu.hours_title') }}</span>
                                @if ($today)
                                    <span class="m-sc-sub">
                                        {{ $days[$today['d']] ?? '' }} ·
                                        @if ($today['closed'] || empty($today['open']))
                                            {{ __('menu.hours_closed') }}
                                        @else
                                            {{ $today['open'] }} – {{ $today['close'] }}
                                        @endif
                                    </span>
                                @endif
                            </span>
                            @if (!is_null($openNow))
                                <span class="m-badge {{ $openNow ? 'm-badge--open' : 'm-badge--closed' }}">
                                    {{ $openNow ? __('menu.open_now') : __('menu.closed_now') }}
                                </span>
                            @endif
                            <span class="m-sc-chevron" aria-hidden="true">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>
                            </span>
                        </summary>
                        <ul class="m-sc-week">
                            @foreach ($branchInfo['hours'] as $h)
                                <li class="m-sc-day {{ $h['today'] ? 'is-today' : '' }}">
                                    <span class="m-sc-dname">{{ $days[$h['d']] ?? '' }}</span>
                                    <span class="m-sc-dtime">
                                        @if ($h['closed'] || empty($h['open']))
                                            <span class="m-sc-off">{{ __('menu.hours_closed') }}</span>
                                        @else
                                            {{ $h['open'] }} – {{ $h['close'] }}
                                        @endif
                                    </span>
                                </li>
                            @endforeach
                        </ul>
                    </details>
                @endif

                {{-- WiFi: tek dokunuşla şifre kopyalama --}}
                @if (!empty($branchInfo['wifi']))
                    <div class="m-sc-card m-sc-row m-sc-wifi">
                        <span class="m-sc-ic" aria-hidden="true">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13a10 10 0 0 1 14 0"/><path d="M8.5 16.5a5 5 0 0 1 7 0"/><path d="M2 8.82a15 15 0 0 1 20 0"/><line x1="12" y1="20" x2="12.01" y2="20"/></svg>
                        </span>
                        <span class="m-sc-main">
                            <span class="m-sc-label">{{ __('menu.wifi_title') }}</span>
                            <span class="m-sc-sub">
                                {{ $branchInfo['wifi']['ssid'] }}
                                @if (!empty($branchInfo['wifi']['password']))
                                    · <span class="m-sc-pass">{{ $branchInfo['wifi']['password'] }}</span>
                                @endif
                            </span>
                        </span>
                        @if (!empty($branchInfo['wifi']['password']))
                            <button type="button" class="m-sc-copy"
                                    data-copy="{{ $branchInfo['wifi']['password'] }}"
                                    data-copied="{{ __('menu.copied') }}"
                                    aria-label="{{ __('menu.wifi_copy') }}">
                                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
                                <span>{{ __('menu.copy') }}</span>
                            </button>
                        @endif
                    </div>
                @endif

                {{-- Konum (harita) --}}
                @if (!empty($branchInfo['address']))
                    <div class="m-sc-card m-sc-row">
                        <span class="m-sc-ic" aria-hidden="true">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/></svg>
                        </span>
                        <span class="m-sc-main">
                            <span class="m-sc-label">{{ __('menu.info_address') }}</span>
                            <span class="m-sc-sub">{{ $branchInfo['address'] }}</span>
                        </span>
                        @if (!empty($branchInfo['maps_url']))
                            <a class="m-sc-copy m-sc-map" href="{{ $branchInfo['maps_url'] }}" target="_blank" rel="noopener nofollow" aria-label="{{ __('menu.get_directions') }}">
                                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 11 22 2l-9 19-2-8-8-2z"/></svg>
                                <span>{{ __('menu.directions') }}</span>
                            </a>
                        @endif
                    </div>
                @endif

                {{-- Telefon --}}
                @if (!empty($branchInfo['phone']))
                    <div class="m-sc-card m-sc-row">
                        <span class="m-sc-ic" aria-hidden="true">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13.832 16.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 6.392 6.384"/></svg>
                        </span>
                        <span class="m-sc-main">
                            <span class="m-sc-label">{{ __('menu.info_phone') }}</span>
                            <a class="m-sc-sub m-sc-link" href="tel:{{ preg_replace('/[^+\d]/', '', $branchInfo['phone']) }}">{{ $branchInfo['phone'] }}</a>
                        </span>
                    </div>
                @endif

                {{-- Sosyal medya --}}
                @if (!empty($branchInfo['social']))
                    @php($socNames = ['instagram' => 'Instagram', 'facebook' => 'Facebook', 'x' => 'X', 'tiktok' => 'TikTok', 'youtube' => 'YouTube', 'whatsapp' => 'WhatsApp', 'website' => __('menu.social_website')])
                    <div class="m-sc-card m-sc-socwrap">
                        <span class="m-sc-socwrap__label">{{ __('menu.social_title') }}</span>
                        <div class="m-sc-social" aria-label="{{ __('menu.social_title') }}">
                            @foreach ($branchInfo['social'] as $s)
                                <a class="m-sc-soc m-sc-soc--{{ $s['key'] }}" href="{{ $s['url'] }}" target="_blank" rel="noopener nofollow" aria-label="{{ $socNames[$s['key']] ?? $s['key'] }}">
                                    <span class="m-sc-soc__ic" aria-hidden="true">
                                    @switch($s['key'])
                                        @case('instagram')
                                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="20" height="20" x="2" y="2" rx="5" ry="5"/><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/><line x1="17.5" y1="6.5" x2="17.51" y2="6.5"/></svg>
                                            @break
                                        @case('facebook')
                                            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/></svg>
                                            @break
                                        @case('x')
                                            <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
                                            @break
                                        @case('tiktok')
                                            <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12.53.02C13.84 0 15.14.01 16.44 0c.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>
                                            @break
                                        @case('youtube')
                                            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M23 12s0-3.9-.5-5.6c-.3-1-1-1.7-2-2C18.8 4 12 4 12 4s-6.8 0-8.5.4c-1 .3-1.7 1-2 2C1 8.1 1 12 1 12s0 3.9.5 5.6c.3 1 1 1.7 2 2 1.7.4 8.5.4 8.5.4s6.8 0 8.5-.4c1-.3 1.7-1 2-2 .5-1.7.5-5.6.5-5.6zM10 15.5v-7l6 3.5z"/></svg>
                                            @break
                                        @case('whatsapp')
                                            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.2-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5.1-.2 0-.4 0-.5s-.7-1.6-.9-2.2c-.2-.6-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.5s1.1 2.9 1.2 3.1c.2.2 2.1 3.3 5.2 4.6 2.6 1.1 3.1.9 3.7.8.6-.1 1.7-.7 2-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.5 15.3L2 22l4.8-1.4A10 10 0 1 0 12 2z"/></svg>
                                            @break
                                        @default
                                            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
                                    @endswitch
                                    </span>
                                    <span class="m-sc-soc__name">{{ $socNames[$s['key']] ?? $s['key'] }}</span>
                                </a>
                            @endforeach
                        </div>
                    </div>
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

    <section class="m-sheet" data-sheet="detail" role="dialog" aria-modal="true" aria-labelledby="qrm-detail-t" hidden>
        <header class="m-sheet__head">
            <h2 class="m-sheet__title" id="qrm-detail-t" data-detail-title></h2>
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

    {{-- Sipariş durumu takibi: müşteri sipariş verince canlı "Hazırlanıyor → Hazır"
         kartı (10 sn polling). Uç zaten hazır: GET /api/v1/public/orders/{token}. --}}
    <style>
        .m-ostatus{position:fixed;left:12px;right:12px;bottom:calc(14px + env(safe-area-inset-bottom,0px));z-index:60;
            background:var(--m-surface);color:var(--m-text);border:1px solid var(--m-border);border-radius:16px;
            box-shadow:var(--m-shadow, 0 8px 28px -8px rgb(0 0 0 / .35));padding:12px 14px;max-width:520px;margin:0 auto;
            display:flex;flex-direction:column;gap:9px;font-size:14px;animation:m-ostatus-in .25s ease;}
        @keyframes m-ostatus-in{from{transform:translateY(12px);opacity:0}to{transform:none;opacity:1}}
        .m-ostatus__top{display:flex;align-items:center;justify-content:space-between;gap:10px;}
        .m-ostatus__badge{font-weight:800;font-size:15px;display:flex;align-items:center;gap:8px;}
        .m-ostatus__dot{width:9px;height:9px;border-radius:99px;background:var(--m-primary);box-shadow:0 0 0 0 var(--m-primary);animation:m-ostatus-pulse 1.6s infinite;}
        @keyframes m-ostatus-pulse{0%{box-shadow:0 0 0 0 rgb(37 99 235 / .5)}70%{box-shadow:0 0 0 8px rgb(37 99 235 / 0)}100%{box-shadow:0 0 0 0 rgb(37 99 235 / 0)}}
        .m-ostatus__close{display:inline-flex;align-items:center;justify-content:center;min-width:44px;min-height:44px;margin:-8px -8px -8px 0;background:none;border:0;color:var(--m-text-muted);font-size:22px;line-height:1;cursor:pointer;}
        .m-ostatus__steps{display:flex;gap:6px;}
        .m-ostatus__step{flex:1;height:6px;border-radius:99px;background:var(--m-border);transition:background .3s;}
        .m-ostatus__step.is-on{background:var(--m-primary);}
        .m-ostatus__hint{color:var(--m-text-muted);font-size:12px;line-height:1.35;}
    </style>
    <div class="m-ostatus" data-order-status role="status" aria-live="polite" hidden></div>

    {{-- Menü verisi (istemci: detay, sepet, filtre) — kişiye özel HİÇBİR şey içermez --}}
    <script type="application/json" id="qrm-data">@json($payload)</script>
    <script>
        window.QRM_L = @json(__('menu.js'));
        {{-- Uç yapılandırması TEK yer: PublicMenuController (Siparis-Adisyon API'si yayınlanınca doldurulur) --}}
        window.QRM_CFG = { orders: @json($orderEndpoint), service: @json($serviceEndpoint), preview: @json(!empty($preview)) };

        /* Tema düğmesi: etkin temayı (data-theme yoksa cihaz tercihi) ters çevir,
           html[data-theme]'e yaz, localStorage'da sakla (erken init head'de). */
        (function () {
            var btn = document.querySelector('[data-theme-toggle]');
            if (!btn) return;
            btn.addEventListener('click', function () {
                var root = document.documentElement;
                var cur = root.getAttribute('data-theme');
                var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                var effective = cur || (prefersDark ? 'dark' : 'light');
                var next = effective === 'dark' ? 'light' : 'dark';
                root.setAttribute('data-theme', next);
                try { localStorage.setItem('qrm-theme', next); } catch (e) {}
            });
        })();

        /* İşletme Vitrini: WiFi şifresini panoya kopyala (tek dokunuş, geri bildirimli). */
        (function () {
            document.addEventListener('click', function (e) {
                var btn = e.target.closest && e.target.closest('.m-sc-copy[data-copy]');
                if (!btn) return;
                var val = btn.getAttribute('data-copy') || '';
                var done = function () {
                    if (btn.classList.contains('is-copied')) return;
                    var label = btn.querySelector('span');
                    var old = label ? label.textContent : '';
                    btn.classList.add('is-copied');
                    if (label) label.textContent = btn.getAttribute('data-copied') || 'OK';
                    setTimeout(function () {
                        btn.classList.remove('is-copied');
                        if (label) label.textContent = old;
                    }, 1600);
                };
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(val).then(done).catch(fallback);
                } else { fallback(); }
                function fallback() {
                    try {
                        var ta = document.createElement('textarea');
                        ta.value = val; ta.setAttribute('readonly', '');
                        ta.style.position = 'absolute'; ta.style.left = '-9999px';
                        document.body.appendChild(ta); ta.select();
                        document.execCommand('copy'); document.body.removeChild(ta);
                        done();
                    } catch (err) {}
                }
            });
        })();
    </script>
@endsection
