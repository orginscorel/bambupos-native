{{-- Tasarım sistemi kanıtı: public menü kabuğu demo verisiyle. Gerçek veri Catalog modülünden gelecek. --}}
@extends('public.layout')

@section('title', $venue['name'] . ' — Menü')

@section('content')
    <header class="m-header">
        <div class="m-header__row">
            <span class="m-header__logo" aria-hidden="true">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="5" height="5" x="3" y="3" rx="1"/><rect width="5" height="5" x="16" y="3" rx="1"/><rect width="5" height="5" x="3" y="16" rx="1"/><path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/><path d="M12 7v3a2 2 0 0 1-2 2H7"/><path d="M3 12h.01"/><path d="M12 3h.01"/><path d="M12 16v.01"/><path d="M16 12h1"/><path d="M21 12v.01"/><path d="M12 21v-1"/></svg>
            </span>
            <div class="m-header__meta">
                <h1 class="m-header__name">{{ $venue['name'] }}</h1>
                <p class="m-header__table">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
                    {{ $venue['table'] }}
                </p>
            </div>
        </div>
    </header>

    @include('public.partials.category-strip', ['categories' => $categories])

    <main class="m-main">
        @foreach ($categories as $category)
            <section class="m-section" id="kategori-{{ $category['id'] }}" data-cat-section="{{ $category['id'] }}" aria-labelledby="kategori-baslik-{{ $category['id'] }}">
                <h2 class="m-section__title" id="kategori-baslik-{{ $category['id'] }}">{{ $category['name'] }}</h2>
                <div class="m-section__items">
                    @foreach ($category['products'] as $product)
                        @include('public.partials.product-card', ['product' => $product])
                    @endforeach
                </div>
            </section>
        @endforeach

        <footer class="m-footer">
            <p>powered by bogahost</p>
        </footer>
    </main>

    @include('public.partials.cart-bar')
@endsection
