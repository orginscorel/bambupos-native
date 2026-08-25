@extends('marketing.layout')

@section('title', ($page['meta_title'] ?? $page['title']) . ' — BamBumPOS')
@section('description', \Illuminate\Support\Str::limit(strip_tags($page['meta_desc'] ?? $page['lead']), 155))

@php($ic = \App\Modules\Marketing\Support\Icons::all())
@php($c = config('site.contact'))
@php($icon = fn($k) => $ic[$k] ?? $ic['grid'])

@section('content')

@include('marketing.partials.breadcrumb', ['crumbs' => [
    ['t' => 'Ana Sayfa', 'u' => '/'],
    ['t' => $page['crumb'] ?? 'Kurumsal'],
    ['t' => $page['eyebrow']],
]])

{{-- ALT SAYFA HERO --}}
<section class="cp-hero">
    <div class="wrap">
        <span class="eyebrow">{!! $ic[$page['icon']] ?? $ic['store'] !!} {{ $page['eyebrow'] }}</span>
        <h1>{{ $page['title'] }}</h1>
        <p class="lead">{{ $page['lead'] }}</p>
        <div class="cp-hero-cta">
            <a href="/#demo" class="btn btn-primary btn-lg">Ücretsiz Demo Talep Et {!! $ic['arrow'] !!}</a>
            <a href="/fiyatlandirma" class="btn btn-line btn-lg">Fiyatlandırma</a>
        </div>
        @if(!empty($page['hero_badges']))
            <div class="cp-hero-badges">
                @foreach($page['hero_badges'] as $hb)
                    <span class="cp-badge">{!! $ic['check'] !!} {{ $hb }}</span>
                @endforeach
            </div>
        @endif
    </div>
</section>

@php($vis = 0)
@foreach($page['blocks'] as $b)
    @php($type = $b['type'] ?? 'prose')
    @php($alt = $vis % 2 === 1)
    @php($vis++)

    @if($type === 'cta')
        @include('marketing.partials.cta-band', ['ctaTitle' => $b['title'] ?? null, 'ctaText' => $b['text'] ?? null])
        @php($vis--)  {{-- CTA kendi koyu bandı; alternatif sırayı bozmasın --}}
    @else
    <section class="sec {{ $alt ? 'bg-2' : '' }}">
        <div class="wrap">
            @if($type === 'prose')
                <div class="cp-prose">
                    @if(!empty($b['title']))<h2>{{ $b['title'] }}</h2>@endif
                    @foreach((array)($b['body'] ?? []) as $para)
                        <p>{{ $para }}</p>
                    @endforeach
                </div>

            @elseif($type === 'features')
                @if(!empty($b['title']))<div class="sec-head center"><h2>{{ $b['title'] }}</h2>@if(!empty($b['lead']))<p>{{ $b['lead'] }}</p>@endif</div>@endif
                <div class="grid g-3" style="margin-top:{{ empty($b['title']) ? '0' : '40px' }}">
                    @foreach($b['items'] as $f)
                        <div class="card reveal">
                            <div class="c-ic">{!! $icon($f[0]) !!}</div>
                            <h3 style="font-size:17px">{{ $f[1] }}</h3><p>{{ $f[2] }}</p>
                        </div>
                    @endforeach
                </div>

            @elseif($type === 'cards')
                @if(!empty($b['title']))<div class="sec-head center"><h2>{{ $b['title'] }}</h2>@if(!empty($b['lead']))<p>{{ $b['lead'] }}</p>@endif</div>@endif
                <div class="cp-cards" style="margin-top:{{ empty($b['title']) ? '0' : '40px' }}">
                    @foreach($b['items'] as $f)
                        @php($tag = 'div')@php($href = $f['url'] ?? null)
                        <{{ $href ? 'a' : 'div' }} class="cp-card reveal" @if($href)href="{{ $href }}"@endif>
                            <span class="cp-card-ic">{!! $icon($f['icon'] ?? 'grid') !!}</span>
                            <h3>{{ $f['title'] }}</h3>
                            <p>{{ $f['desc'] }}</p>
                            @if($href)<span class="cp-card-l">İncele {!! $ic['arrow'] !!}</span>@endif
                        </{{ $href ? 'a' : 'div' }}>
                    @endforeach
                </div>

            @elseif($type === 'stats')
                @if(!empty($b['title']))<div class="sec-head center"><h2>{{ $b['title'] }}</h2>@if(!empty($b['lead']))<p>{{ $b['lead'] }}</p>@endif</div>@endif
                <div class="cp-stats" style="margin-top:{{ empty($b['title']) ? '0' : '36px' }}">
                    @foreach($b['items'] as $s)
                        <div class="cp-stat reveal"><div class="cp-stat-n">{{ $s[0] }}</div><div class="cp-stat-l">{{ $s[1] }}</div></div>
                    @endforeach
                </div>

            @elseif($type === 'steps')
                @if(!empty($b['title']))<div class="sec-head center"><h2>{{ $b['title'] }}</h2>@if(!empty($b['lead']))<p>{{ $b['lead'] }}</p>@endif</div>@endif
                <div class="cp-steps" style="margin-top:{{ empty($b['title']) ? '0' : '40px' }}">
                    @foreach($b['items'] as $i => $st)
                        <div class="cp-step reveal">
                            <span class="cp-step-n">{{ $i + 1 }}</span>
                            <h3>{{ $st[0] }}</h3>
                            <p>{{ $st[1] }}</p>
                        </div>
                    @endforeach
                </div>

            @elseif($type === 'split')
                <div class="cp-split">
                    <div class="cp-split-txt">
                        @if(!empty($b['eyebrow']))<span class="eyebrow">{!! $icon($b['icon'] ?? 'zap') !!} {{ $b['eyebrow'] }}</span>@endif
                        <h2>{{ $b['title'] }}</h2>
                        @foreach((array)($b['body'] ?? []) as $para)<p>{{ $para }}</p>@endforeach
                    </div>
                    <ul class="cp-checks">
                        @foreach($b['items'] as $li)
                            <li>{!! $ic['check'] !!} <span>{{ $li }}</span></li>
                        @endforeach
                    </ul>
                </div>

            @elseif($type === 'checklist')
                @if(!empty($b['title']))<div class="sec-head center"><h2>{{ $b['title'] }}</h2>@if(!empty($b['lead']))<p>{{ $b['lead'] }}</p>@endif</div>@endif
                <ul class="cp-checks cp-checks-grid" style="margin-top:{{ empty($b['title']) ? '0' : '32px' }}">
                    @foreach($b['items'] as $li)
                        <li>{!! $ic['check'] !!} <span>{{ $li }}</span></li>
                    @endforeach
                </ul>

            @elseif($type === 'callout')
                <div class="cp-callout">
                    <span class="cp-callout-ic">{!! $icon($b['icon'] ?? 'zap') !!}</span>
                    <div>
                        @if(!empty($b['title']))<b>{{ $b['title'] }}</b>@endif
                        <p>{{ $b['body'] }}</p>
                    </div>
                </div>

            @elseif($type === 'faq')
                <div class="sec-head center"><span class="eyebrow">{!! $ic['shield'] !!} {{ $b['title'] ?? 'SSS' }}</span></div>
                <div class="faq">
                    @foreach($b['items'] as $qa)
                        <details class="qa"><summary>{{ $qa[0] }} <span class="x">+</span></summary><p>{{ $qa[1] }}</p></details>
                    @endforeach
                </div>

            @elseif($type === 'contact')
                <div class="cp-contact">
                    <a class="cp-cc" href="mailto:{{ $c['email'] }}">
                        <span class="cp-cc-ic">{!! $ic['headset'] !!}</span>
                        <b>Satış & bilgi</b><span>{{ $c['email'] }}</span>
                    </a>
                    <a class="cp-cc" href="mailto:{{ $c['support_email'] }}">
                        <span class="cp-cc-ic">{!! $ic['shield'] !!}</span>
                        <b>Destek</b><span>{{ $c['support_email'] }}</span>
                    </a>
                    <a class="cp-cc" href="https://wa.me/{{ ltrim($c['whatsapp'],'+') }}" target="_blank" rel="noopener">
                        <span class="cp-cc-ic">{!! $ic['phone'] !!}</span>
                        <b>WhatsApp</b><span>Hızlı yanıt hattı</span>
                    </a>
                    <span class="cp-cc">
                        <span class="cp-cc-ic">{!! $ic['calendar'] !!}</span>
                        <b>Çalışma saatleri</b><span>{{ $c['hours'] }}</span>
                    </span>
                </div>
            @endif
        </div>
    </section>
    @endif
@endforeach

{{-- Sayfanın son bloğu zaten 'cta' ise sondaki bandı EKLEME (çift CTA olmasın) --}}
@php($lastType = !empty($page['blocks']) ? ($page['blocks'][array_key_last($page['blocks'])]['type'] ?? '') : '')
@unless($lastType === 'cta')
    @include('marketing.partials.cta-band', ['ctaTitle' => $page['cta_title'] ?? 'İşletmenizi bugün dijitalleştirin'])
@endunless
@endsection

@push('head')
<style>
  .cp-hero{ padding: 54px 0 30px; text-align:center; }
  .cp-hero .eyebrow{ justify-content:center; }
  .cp-hero h1{ font-size: clamp(30px, 4.4vw, 50px); font-weight:800; letter-spacing:-.03em; line-height:1.08; margin:16px auto 0; max-width:20ch; }
  .cp-hero .lead{ font-size: clamp(16px,1.7vw,19px); color:var(--muted); margin:16px auto 0; max-width:62ch; line-height:1.6; }
  .cp-hero-cta{ display:flex; gap:12px; justify-content:center; flex-wrap:wrap; margin-top:26px; }
  .cp-hero-badges{ display:flex; gap:10px 20px; justify-content:center; flex-wrap:wrap; margin-top:22px; }
  .cp-badge{ display:inline-flex; align-items:center; gap:7px; font-size:13.5px; font-weight:600; color:var(--ink-2); }
  .cp-badge svg{ width:16px; height:16px; color:var(--teal); }

  .cp-prose{ max-width:768px; margin:0 auto; }
  .cp-prose h2{ font-size:clamp(22px,2.6vw,30px); font-weight:800; letter-spacing:-.02em; margin:0 0 16px; }
  .cp-prose p{ font-size:16.5px; color:var(--ink-2); line-height:1.78; margin:0 0 14px; }
  .cp-prose p:last-child{ margin-bottom:0; }

  /* Linkli kart ızgarası */
  .cp-cards{ display:grid; grid-template-columns:repeat(3,1fr); gap:18px; }
  .cp-card{ display:flex; flex-direction:column; padding:24px; border:1px solid var(--line); border-radius:var(--radius-lg); background:var(--card); box-shadow:var(--shadow-xs); text-decoration:none; transition:transform .22s var(--ease), box-shadow .22s, border-color .22s; }
  a.cp-card:hover{ transform:translateY(-4px); box-shadow:var(--shadow); border-color:var(--teal-100); }
  .cp-card-ic{ width:46px; height:46px; border-radius:12px; background:var(--teal-50); border:1px solid var(--teal-100); color:var(--teal-700); display:grid; place-items:center; margin-bottom:14px; }
  .cp-card-ic svg{ width:23px; height:23px; }
  .cp-card h3{ font-size:17px; font-weight:700; margin:0 0 7px; color:var(--ink); letter-spacing:-.01em; }
  .cp-card p{ font-size:14px; color:var(--muted); line-height:1.6; margin:0; flex:1; }
  .cp-card-l{ display:inline-flex; align-items:center; gap:6px; margin-top:14px; font-size:13px; font-weight:700; color:var(--teal-700); }
  .cp-card-l svg{ width:14px; height:14px; }

  /* İstatistik şeridi (dürüst ürün nitelikleri) */
  .cp-stats{ display:grid; grid-template-columns:repeat(4,1fr); gap:18px; }
  .cp-stat{ text-align:center; padding:26px 18px; border:1px solid var(--line); border-radius:var(--radius-lg); background:var(--card); box-shadow:var(--shadow-xs); }
  .cp-stat-n{ font-size:clamp(19px,2.2vw,24px); font-weight:800; letter-spacing:-.02em; color:var(--teal-700); line-height:1.1; }
  .cp-stat-l{ font-size:13px; color:var(--muted); margin-top:8px; line-height:1.5; }

  /* Adımlar */
  .cp-steps{ display:grid; grid-template-columns:repeat(4,1fr); gap:18px; counter-reset:s; }
  .cp-step{ position:relative; padding:26px 22px 22px; border:1px solid var(--line); border-radius:var(--radius-lg); background:var(--card); box-shadow:var(--shadow-xs); }
  .cp-step-n{ display:grid; place-items:center; width:40px; height:40px; border-radius:11px; background:linear-gradient(135deg,var(--teal),var(--teal-800)); color:#fff; font-weight:800; font-size:17px; box-shadow:0 6px 16px rgba(37,99,235,.3); margin-bottom:14px; }
  .cp-step h3{ font-size:16px; font-weight:700; margin:0 0 6px; color:var(--ink); }
  .cp-step p{ font-size:13.8px; color:var(--muted); line-height:1.58; margin:0; }

  /* Split: metin + checklist */
  .cp-split{ display:grid; grid-template-columns:1.05fr .95fr; gap:44px; align-items:center; }
  .cp-split-txt h2{ font-size:clamp(22px,2.7vw,32px); font-weight:800; letter-spacing:-.02em; margin:12px 0 14px; }
  .cp-split-txt p{ font-size:16px; color:var(--ink-2); line-height:1.72; margin:0 0 12px; }
  .cp-checks{ list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:12px; }
  .cp-checks li{ display:flex; align-items:flex-start; gap:11px; font-size:15px; color:var(--ink-2); line-height:1.5; }
  .cp-checks li svg{ width:20px; height:20px; flex:none; color:#fff; background:var(--teal); border-radius:50%; padding:3px; margin-top:1px; }
  .cp-checks-grid{ display:grid; grid-template-columns:1fr 1fr; gap:14px 30px; max-width:900px; margin-inline:auto; }

  /* Callout */
  .cp-callout{ display:flex; gap:16px; align-items:flex-start; max-width:820px; margin:0 auto; padding:24px 26px; border:1px solid var(--teal-100); border-radius:var(--radius-lg); background:var(--teal-50); }
  .cp-callout-ic{ width:44px; height:44px; flex:none; border-radius:12px; background:#fff; border:1px solid var(--teal-100); color:var(--teal-700); display:grid; place-items:center; }
  .cp-callout-ic svg{ width:22px; height:22px; }
  .cp-callout b{ display:block; font-size:16px; color:var(--ink); margin-bottom:4px; }
  .cp-callout p{ font-size:15px; color:var(--ink-2); line-height:1.65; margin:0; }

  .cp-contact{ display:grid; grid-template-columns:repeat(4,1fr); gap:16px; }
  .cp-cc{ display:flex; flex-direction:column; gap:2px; padding:22px; border:1px solid var(--line); border-radius:var(--radius-lg); background:var(--card); box-shadow:var(--shadow-xs); transition:border-color .16s, box-shadow .2s, transform .18s var(--ease); }
  a.cp-cc:hover{ border-color:var(--teal-100); box-shadow:var(--shadow-sm); transform:translateY(-3px); }
  .cp-cc-ic{ width:44px; height:44px; border-radius:12px; background:var(--teal-50); border:1px solid var(--teal-100); color:var(--teal-700); display:grid; place-items:center; margin-bottom:12px; }
  .cp-cc-ic svg{ width:22px; height:22px; }
  .cp-cc b{ font-size:15px; color:var(--ink); }
  .cp-cc span:last-child{ font-size:13.5px; color:var(--muted); }

  @media(max-width:920px){ .cp-cards{ grid-template-columns:1fr 1fr; } .cp-stats{ grid-template-columns:1fr 1fr; } .cp-steps{ grid-template-columns:1fr 1fr; } .cp-split{ grid-template-columns:1fr; gap:28px; } }
  @media(max-width:820px){ .cp-contact{ grid-template-columns:1fr 1fr; } }
  @media(max-width:560px){ .cp-cards,.cp-stats,.cp-steps,.cp-contact{ grid-template-columns:1fr; } .cp-checks-grid{ grid-template-columns:1fr; } }
</style>
@endpush
