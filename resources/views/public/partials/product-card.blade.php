{{-- Ürün kartı. $product: PublicMenuController::buildMenu kart dizisi (id, name,
     description, price_minor, old_price_minor, image, sold_out, is_new,
     is_chef_pick, is_bestseller, spiciness, diets[], has_config).
     Detay ve sepet verisi #qrm-data JSON'undan okunur (ADR-003/011).
     Eski çağıranlar (tasarım demosu) için varsayılanlar doldurulur. --}}
@php
    $product += [
        'description' => null, 'old_price_minor' => null, 'image' => null,
        'sold_out' => !empty($product['unavailable']), 'is_new' => false,
        'is_chef_pick' => false, 'is_bestseller' => false, 'spiciness' => 0,
        'diets' => [], 'has_config' => false, 'out_reason' => 'stock',
    ];
@endphp
<article class="m-product {{ $product['sold_out'] ? 'is-unavailable' : '' }}" data-pid="{{ $product['id'] }}">
    <div class="m-product__body">
        <h3 class="m-product__name">{{ $product['name'] }}</h3>

        @if ($product['is_new'] || $product['is_chef_pick'] || $product['is_bestseller'] || $product['spiciness'] > 0 || $product['diets'] !== [])
            <p class="m-product__tags">
                @if ($product['is_bestseller'])<span class="m-tag m-tag--best">{{ __('menu.js.tag_best') }}</span>@endif
                @if ($product['is_new'])<span class="m-tag m-tag--new">{{ __('menu.js.tag_new') }}</span>@endif
                @if ($product['is_chef_pick'])<span class="m-tag m-tag--chef">{{ __('menu.js.tag_chef') }}</span>@endif
                @if ($product['spiciness'] > 0)
                    <span class="m-tag m-tag--spicy" role="img" aria-label="{{ __('menu.js.spicy') }} {{ $product['spiciness'] }}/3">
                        @for ($i = 0; $i < min(3, $product['spiciness']); $i++)<svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5"/></svg>@endfor
                    </span>
                @endif
                @foreach ($product['diets'] as $diet)
                    <span class="m-tag m-tag--diet">{{ $diet }}</span>
                @endforeach
            </p>
        @endif

        @if (!empty($product['description']))
            <p class="m-product__desc">{{ $product['description'] }}</p>
        @endif

        <p class="m-product__price">
            ₺ {{ number_format($product['price_minor'] / 100, 2, ',', '.') }}
            @if ($product['old_price_minor'] !== null)
                <s class="m-product__oldprice">₺ {{ number_format($product['old_price_minor'] / 100, 2, ',', '.') }}</s>
            @endif
            @if ($product['sold_out'])
                <span class="m-product__flag">
                    {{-- durum yalnız renkle anlatılmaz: ikon + metin --}}
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>
                    {{ $product['out_reason'] === 'window' ? __('menu.js.off_hours') : __('menu.js.sold_out') }}
                </span>
            @endif
        </p>
    </div>

    @if (!empty($product['image']))
        {{-- Dokununca büyütme (lightbox, menu.js): buton kart yüzeyini kaplayan
             .m-product__open'ın ÜZERİNDE durur; görselsiz üründe tetikleyici yok --}}
        <button type="button" class="m-product__zoom" data-lightbox="{{ $product['id'] }}" aria-label="{{ $product['name'] }} — {{ __('menu.js.zoom') }}">
            <img class="m-product__img" src="{{ $product['image'] }}" alt="" loading="lazy" decoding="async" width="88" height="88">
        </button>
    @else
        <span class="m-product__img m-product__img--empty" aria-hidden="true">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2"/><path d="M7 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/></svg>
        </span>
    @endif

    {{-- Kartın tamamı detay açar (yüzeyi kaplayan erişilebilir buton) --}}
    <button type="button" class="m-product__open" data-detail="{{ $product['id'] }}">
        <span class="sr-only">{{ $product['name'] }} — detayları gör</span>
    </button>

    <button
        type="button"
        class="m-product__add"
        data-add="{{ $product['id'] }}"
        aria-label="{{ $product['name'] }} — {{ __('menu.js.add_to_cart') }}"
        @if ($product['sold_out']) disabled @endif
    >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
    </button>
</article>
