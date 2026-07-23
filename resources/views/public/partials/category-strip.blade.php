{{--
    Story tarzı kategori şeridi: yatay kaydırmalı yuvarlak baloncuklar.
    Görsel önceliği: 1) kategorinin kendi görseli (panelde tanımlıysa),
    2) kategorideki İLK görselli ürün — aynı dosya ürün kartında da
    kullanılır, tarayıcı tek indirme yapar (ek yük yok), 3) panelde
    tanımlı kategori rengi, o da yoksa paletten deterministik renk +
    kategori baş harfi (kasıtlı, "bozuk" değil).
    Scroll-spy menu.js'teki mevcut data-cat-link sözleşmesiyle çalışır;
    aktif kategori story "izleniyor" halkasıyla vurgulanır (is-active).
    $products / $catMeta opsiyoneldir (menu-demo yalnız $categories verir).
--}}
@php
    // Koyu tonlar: beyaz baş harfle her iki temada da AA kontrast verir.
    $storyPalette = ['#c2410c', '#0e7490', '#15803d', '#7c3aed', '#be185d', '#a16207', '#4338ca', '#b91c1c'];
@endphp
<nav class="m-catstrip" aria-label="{{ __('menu.categories_label') }}" data-catstrip>
    <ul class="m-catstrip__list">
        @foreach ($categories as $ci => $category)
            @php
                // 1) Kategorinin kendi görseli, 2) yoksa kategorideki ilk görselli ürün (kart verisinden; ek sorgu yok)
                $storyImg = ($catMeta ?? [])[$category['id']]['image'] ?? null;
                if (!$storyImg) {
                    foreach (($products ?? [])[$category['id']] ?? [] as $storyP) {
                        if (!empty($storyP['image'])) { $storyImg = $storyP['image']; break; }
                    }
                }
                // Panel rengi yalnız güvenli hex biçimindeyse kullanılır (style enjeksiyonu yok)
                $metaColor = ($catMeta ?? [])[$category['id']]['color'] ?? null;
                $storyColor = (is_string($metaColor) && preg_match('/^#[0-9a-fA-F]{3,8}$/', $metaColor))
                    ? $metaColor
                    : $storyPalette[$ci % count($storyPalette)];
            @endphp
            <li>
                <a class="m-story" href="#kategori-{{ $category['id'] }}" data-cat-link="{{ $category['id'] }}">
                    <span class="m-story__ring">
                        @if ($storyImg)
                            <img class="m-story__img" src="{{ $storyImg }}" alt=""
                                 width="56" height="56" loading="lazy" decoding="async">
                        @else
                            <span class="m-story__img m-story__img--tint" style="background: {{ $storyColor }}" aria-hidden="true">{{ mb_strtoupper(mb_substr(trim($category['name']), 0, 1), 'UTF-8') }}</span>
                        @endif
                    </span>
                    <span class="m-story__name">{{ $category['name'] }}</span>
                </a>
            </li>
        @endforeach
    </ul>
</nav>
