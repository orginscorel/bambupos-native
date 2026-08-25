@extends('marketing.layout')

@section('title', $page['title'])
@section('description', $page['desc'])

@php($ic = \App\Modules\Marketing\Support\Icons::all())

@section('content')

@include('marketing.partials.breadcrumb', ['crumbs' => [
    ['t' => 'Ana Sayfa', 'u' => '/'],
    ['t' => 'POS Sistemleri'],
    ['t' => $page['label']],
]])

{{-- HERO --}}
<section class="page-hero">
    <div class="wrap split">
        <div>
            <span class="eyebrow">{!! $ic['store'] !!} {{ $page['label'] }}</span>
            <h1>{{ $page['hero'] }}</h1>
            <p class="lead">{{ $page['lead'] }}</p>
            <div style="display:flex;gap:12px;flex-wrap:wrap">
                <a href="/#demo" class="btn btn-primary btn-lg">Ücretsiz Demo Talep Et {!! $ic['arrow'] !!}</a>
                <a href="/fiyatlandirma" class="btn btn-line btn-lg">Fiyatlandırma</a>
            </div>
            @if(!empty($page['hero_badges']))
                <div class="hero-note" style="margin-top:20px">
                    @foreach($page['hero_badges'] as $hb)<span><span class="ck">{!! $ic['check'] !!}</span> {{ $hb }}</span>@endforeach
                </div>
            @endif
        </div>
        <div class="sc-media">
            @include('marketing.partials.showcase-device', [
                'scScreen' => $page['hero_screen'] ?? 'adisyon',
                'scUrl' => $page['hero_url'] ?? 'panel.bambumpos.com',
                'scAlt' => $page['name'].' için BamBumPOS ekranı',
            ])
        </div>
    </div>
</section>

{{-- PROBLEMLER --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head"><span class="eyebrow">{!! $ic['target'] !!} Zorluklar</span><h2>{{ $page['name'] }} işletmelerinde en sık karşılaşılan sorunlar</h2></div>
        <div class="prob" style="margin-top:34px;grid-template-columns:repeat(3,1fr);display:grid;gap:16px">
            @foreach($page['problems'] as $p)
                <div class="p reveal"><h4>{{ $p[0] }}</h4><p>{{ $p[1] }}</p></div>
            @endforeach
        </div>
    </div>
</section>

{{-- ÇÖZÜM / ÖZELLİKLER --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['check'] !!} BamBumPOS çözümü</span><h2>{{ $page['name'] }} operasyonunu uçtan uca yönetin</h2></div>
        <div class="grid g-3" style="margin-top:44px">
            @foreach($page['features'] as $i => $f)
                <div class="card reveal @if($i%3) d{{ $i%3 }} @endif">
                    <div class="c-ic">{!! $ic[$f[0]] ?? $ic['grid'] !!}</div>
                    <h3 style="font-size:17px">{{ $f[1] }}</h3><p>{{ $f[2] }}</p>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- SHOWCASE — animasyonlu gerçek ekranlarla anlatım (alternatif yerleşim) --}}
@if(!empty($page['showcases']))
    @foreach($page['showcases'] as $si => $sc)
        <section class="sec {{ $si % 2 === 0 ? '' : 'bg-2' }}">
            <div class="wrap">
                <div class="showcase {{ $si % 2 === 1 ? 'rev' : '' }}">
                    <div class="sc-txt">
                        <span class="eyebrow">{!! $ic[$sc['icon'] ?? 'zap'] ?? $ic['zap'] !!} {{ $sc['eyebrow'] ?? 'Öne çıkan' }}</span>
                        <h2>{{ $sc['title'] }}</h2>
                        <p>{{ $sc['body'] }}</p>
                        <ul class="sc-list">
                            @foreach($sc['bullets'] as $b)
                                <li>{!! $ic['check'] !!} <span>{{ $b }}</span></li>
                            @endforeach
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
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['trend'] !!} Neden BamBumPOS</span><h2>{{ $page['name'] }} için tek platformun getirisi</h2></div>
        <div class="pg-stats" style="margin-top:38px">
            @foreach($page['stats'] as $s)
                <div class="pg-stat reveal"><div class="pg-stat-n">{{ $s[0] }}</div><div class="pg-stat-l">{{ $s[1] }}</div></div>
            @endforeach
        </div>
    </div>
</section>
@endif

{{-- MODÜLLER + SENARYO --}}
<section class="sec">
    <div class="wrap split">
        <div>
            <span class="eyebrow">{!! $ic['layers'] !!} Nasıl çalışır</span>
            <h2>Bir günlük akış, {{ $page['name'] }} için</h2>
            <p class="lead">{{ $page['scenario'] }}</p>
            <a href="/#demo" class="btn btn-primary">Demo’da Görün {!! $ic['arrow'] !!}</a>
        </div>
        <div>
            <div style="font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--soft);margin-bottom:14px">Bu sektörde öne çıkan modüller</div>
            <div class="chips">
                @foreach($page['modules'] as $m)<span class="chip">{{ $m }}</span>@endforeach
            </div>
        </div>
    </div>
</section>

{{-- ÇEVRİMDIŞI / GÜVEN --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="cp-callout" style="max-width:900px">
            <span class="cp-callout-ic">{!! $ic['shield'] !!}</span>
            <div>
                <b>İnternet kesilse bile satış durmaz</b>
                <p>BamBumPOS yerel çalışma moduyla bağlantı olmadan da çalışır; bağlantı geri geldiğinde tüm siparişler ve ödemeler otomatik senkronlanır. Veriniz şifreli ve yedeklidir.</p>
            </div>
        </div>
    </div>
</section>

{{-- SSS --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['shield'] !!} SSS</span><h2>{{ $page['name'] }} için sık sorulanlar</h2></div>
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

@include('marketing.partials.cta-band', ['ctaTitle' => $page['name'].' işletmenizi bugün dijitalleştirin'])
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
