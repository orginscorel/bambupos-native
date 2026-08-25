@extends('marketing.layout')

@section('title', $page['title'])
@section('description', $page['desc'])

@php($ic = \App\Modules\Marketing\Support\Icons::all())

@section('content')

@include('marketing.partials.breadcrumb', ['crumbs' => [
    ['t' => 'Ana Sayfa', 'u' => '/'],
    ['t' => 'Çözümler'],
    ['t' => $page['label']],
]])

{{-- HERO --}}
<section class="page-hero">
    <div class="wrap split">
        <div>
            <span class="eyebrow">{!! $ic[$page['icon'] ?? 'grid'] !!} {{ $page['label'] }}</span>
            <h1>{{ $page['hero'] }}</h1>
            <p class="lead">{{ $page['lead'] }}</p>
            <div style="display:flex;gap:12px;flex-wrap:wrap">
                <a href="/#demo" class="btn btn-primary btn-lg">Ücretsiz Demo Talep Et {!! $ic['arrow'] !!}</a>
                <a href="/fiyatlandirma" class="btn btn-line btn-lg">Fiyatlandırma</a>
            </div>
        </div>
        <div class="reveal">
            @if(!empty($page['hero_screen']))
                <div class="sc-media">
                    @include('marketing.partials.showcase-device', [
                        'scScreen' => $page['hero_screen'],
                        'scUrl' => $page['hero_url'] ?? 'panel.bambumpos.com',
                        'scAlt' => $page['label'].' — BamBumPOS ekranı',
                    ])
                </div>
            @else
                @php($shot = $page['shot'] ?? null)
                @if($shot === 'phone-menu')
                    @include('marketing.partials.mockup-phone')
                @elseif(in_array($shot, ['app-dashboard', 'app-mutfak', 'app-masalar'], true))
                    <div class="shot">
                        <div class="frame-bar"><i></i><i></i><i></i><span class="fb-url">{{ $page['label'] }} — BamBumPOS</span></div>
                        <img src="/assets/site/shots/{{ $shot }}.jpg?v=2" width="1440" height="900" loading="eager" decoding="async" alt="{{ $page['label'] }} — BamBumPOS ekranı">
                    </div>
                @else
                    @include('marketing.partials.mockup-dash', ['mockTitle' => $page['label'].' — BamBumPOS'])
                @endif
            @endif
        </div>
    </div>
</section>

{{-- 3 FAYDA --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="grid g-3">
            @foreach($page['benefits'] as $i => $b)
                <div class="card reveal @if($i%3) d{{ $i%3 }} @endif">
                    <div class="c-ic">{!! $ic[$b[0]] ?? $ic['check'] !!}</div>
                    <h3 style="font-size:17px">{{ $b[1] }}</h3><p>{{ $b[2] }}</p>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- ÖZELLİKLER --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['grid'] !!} Özellikler</span><h2>{{ $page['label'] }} ile neler yapabilirsiniz</h2></div>
        <div class="grid g-2" style="margin-top:44px;gap:16px">
            @foreach($page['features'] as $i => $f)
                <div class="card reveal" style="display:flex;gap:16px;align-items:flex-start">
                    <span style="width:44px;height:44px;border-radius:11px;flex:none;background:var(--teal-50);border:1px solid var(--teal-100);color:var(--teal-700);display:grid;place-items:center">{!! $ic[$f[0]] ?? $ic['check'] !!}</span>
                    <div><h3 style="font-size:16px;margin:0 0 5px">{{ $f[1] }}</h3><p>{{ $f[2] }}</p></div>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- SHOWCASE — animasyonlu gerçek ekranlarla anlatım --}}
@if(!empty($page['showcases']))
    @foreach($page['showcases'] as $si => $sc)
        <section class="sec {{ $si % 2 === 0 ? 'bg-2' : '' }}">
            <div class="wrap">
                <div class="showcase {{ $si % 2 === 1 ? 'rev' : '' }}">
                    <div class="sc-txt">
                        <span class="eyebrow">{!! $ic[$sc['icon'] ?? 'zap'] ?? $ic['zap'] !!} {{ $sc['eyebrow'] ?? 'Öne çıkan' }}</span>
                        <h2>{{ $sc['title'] }}</h2>
                        <p>{{ $sc['body'] }}</p>
                        <ul class="sc-list">
                            @foreach($sc['bullets'] as $b)<li>{!! $ic['check'] !!} <span>{{ $b }}</span></li>@endforeach
                        </ul>
                        <div class="sc-cta"><a href="/#demo" class="btn btn-primary">Demo’da görün {!! $ic['arrow'] !!}</a></div>
                    </div>
                    <div class="sc-media">
                        @include('marketing.partials.showcase-device', [
                            'scScreen' => $sc['screen'] ?? 'adisyon',
                            'scUrl' => $sc['url'] ?? 'panel.bambumpos.com',
                            'scAlt' => $sc['title'],
                            'scDelay' => ($si * 2).'s',
                        ])
                    </div>
                </div>
            </div>
        </section>
    @endforeach
@endif

{{-- KAZANÇ / İSTATİSTİK ŞERİDİ (dürüst ürün nitelikleri) --}}
@if(!empty($page['stats']))
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['trend'] !!} Neden BamBumPOS</span><h2>{{ $page['label'] }} ile ne kazanırsınız</h2></div>
        <div class="pg-stats" style="margin-top:38px">
            @foreach($page['stats'] as $s)
                <div class="pg-stat reveal"><div class="pg-stat-n">{{ $s[0] }}</div><div class="pg-stat-l">{{ $s[1] }}</div></div>
            @endforeach
        </div>
    </div>
</section>
@endif

{{-- NASIL ÇALIŞIR --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['layers'] !!} Nasıl çalışır</span><h2>Üç adımda {{ $page['label'] }}</h2></div>
        <div class="flow" style="margin-top:44px">
            @foreach($page['steps'] as $i => $st)
                <div class="step reveal @if($i%3) d{{ $i%3 }} @endif"><div class="num">{{ $i+1 }}</div><h4>{{ $st[0] }}</h4><p>{{ $st[1] }}</p></div>
            @endforeach
        </div>
    </div>
</section>

{{-- SSS --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['shield'] !!} SSS</span><h2>{{ $page['label'] }} hakkında</h2></div>
        <div class="faq">
            @foreach($page['faq'] as $qa)
                <details class="qa"><summary>{{ $qa[0] }} <span class="x">+</span></summary><p>{{ $qa[1] }}</p></details>
            @endforeach
        </div>
    </div>
</section>

{{-- İLGİLİ --}}
@if(!empty($page['related']))
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head"><h2 style="font-size:24px">İlgili çözümler</h2></div>
        <div class="related-grid" style="margin-top:24px">
            @foreach($page['related'] as $r)
                <a href="{{ $r[1] }}"><span class="rt">{{ $r[0] }}</span><span class="rl">İncele {!! $ic['arrow'] !!}</span></a>
            @endforeach
        </div>
    </div>
</section>
@endif

@include('marketing.partials.cta-band', ['ctaTitle' => $page['label'].' ile işletmenizi hızlandırın'])
@endsection

@push('schema')
<script type="application/ld+json">
{!! json_encode([
    '@'.'context' => 'https://schema.org',
    '@type' => 'FAQPage',
    'mainEntity' => collect($page['faq'])->map(fn ($qa) => [
        '@type' => 'Question', 'name' => $qa[0],
        'acceptedAnswer' => ['@type' => 'Answer', 'text' => $qa[1]],
    ])->all(),
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) !!}
</script>
@endpush
