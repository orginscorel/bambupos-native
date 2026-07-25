{{-- Ürün kartı. $product: ['id','name','description','price_minor','price_formatted','image'(ops.),'unavailable'(ops.)] --}}
<article class="m-product {{ !empty($product['unavailable']) ? 'is-unavailable' : '' }}">
    <div class="m-product__body">
        <h3 class="m-product__name">{{ $product['name'] }}</h3>
        @if (!empty($product['description']))
            <p class="m-product__desc">{{ $product['description'] }}</p>
        @endif
        <p class="m-product__price">
            {{ $product['price_formatted'] }}
            @if (!empty($product['unavailable']))
                <span class="m-product__flag">
                    {{-- durum yalnız renkle anlatılmaz: ikon + metin --}}
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>
                    Tükendi
                </span>
            @endif
        </p>
    </div>
    @if (!empty($product['image']))
        <img class="m-product__img" src="{{ $product['image'] }}" alt="" loading="lazy" width="88" height="88">
    @else
        <span class="m-product__img m-product__img--empty" aria-hidden="true">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2"/><path d="M7 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/></svg>
        </span>
    @endif
    <button
        type="button"
        class="m-product__add"
        data-add-item
        data-item-id="{{ $product['id'] }}"
        data-item-name="{{ $product['name'] }}"
        data-item-price-minor="{{ $product['price_minor'] }}"
        aria-label="{{ $product['name'] }} sepete ekle"
        @if (!empty($product['unavailable'])) disabled @endif
    >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
    </button>
</article>
