@extends('marketing.layout')

@section('title', 'Fiyatlandırma — İşletmenize Özel POS Teklifi')
@section('description', 'BamBumPOS paketleri: Başlangıç, Profesyonel ve Kurumsal. Şube, terminal ve modül ihtiyacınıza göre şeffaf, size özel fiyat. Kurulum ücreti yok.')

@php($ic = \App\Modules\Marketing\Support\Icons::all())
@php($plans = config('pricing.plans'))
@php($compare = config('pricing.compare'))
@php($addons = config('pricing.addons'))
@php($faq = config('pricing.faq'))

@push('head')
<style>
  .pr-hero{padding:56px 0 28px;text-align:center}
  .pr-hero .eyebrow{justify-content:center}
  .pr-hero h1{max-width:14ch;margin:14px auto 0}
  .pr-hero .lead{max-width:56ch;margin:16px auto 0}
  .pr-note{display:inline-flex;align-items:center;gap:8px;margin-top:18px;padding:8px 14px;border:1px solid var(--line);
    border-radius:999px;background:var(--card);font-size:13.5px;font-weight:600;color:var(--muted)}
  .pr-note svg{width:16px;height:16px;color:var(--teal)}
  .pr-trust{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-top:26px}
  .pr-trust-i{display:flex;align-items:center;gap:11px;padding:15px 16px;border:1px solid var(--line);border-radius:var(--radius);background:var(--card);font-size:13.5px;font-weight:600;color:var(--ink-2);box-shadow:var(--shadow-xs)}
  .pr-trust-i svg{width:20px;height:20px;color:var(--teal);flex:none}
  @media(max-width:820px){.pr-trust{grid-template-columns:1fr 1fr}}
  @media(max-width:480px){.pr-trust{grid-template-columns:1fr}}
  .pr-hero .sr-only,.cmp .sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}

  /* Paket kartları */
  .plans{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;align-items:stretch;margin-top:36px}
  .plan{position:relative;display:flex;flex-direction:column;background:var(--card);border:1px solid var(--line);
    border-radius:var(--radius-lg);padding:26px 24px;box-shadow:var(--shadow-sm);transition:transform .25s var(--ease),box-shadow .25s var(--ease)}
  .plan:hover{transform:translateY(-4px);box-shadow:var(--shadow)}
  .plan.pop{border-color:var(--teal);box-shadow:0 20px 46px -22px rgba(37,99,235,.5)}
  .plan-badge{position:absolute;top:-13px;left:50%;transform:translateX(-50%);background:var(--teal);color:#fff;
    font-size:12px;font-weight:700;letter-spacing:.02em;padding:6px 14px;border-radius:999px;white-space:nowrap;
    box-shadow:0 8px 20px -8px rgba(37,99,235,.7)}
  .plan-name{font-size:20px;font-weight:700;color:var(--ink)}
  .plan-for{margin-top:6px;font-size:13.5px;color:var(--muted);min-height:38px}
  .plan-price{margin:18px 0 4px;font-size:30px;font-weight:800;color:var(--ink);letter-spacing:-.02em}
  .plan-price small{display:block;font-size:13px;font-weight:600;color:var(--soft);letter-spacing:0;margin-top:2px}
  .plan-feats{list-style:none;margin:20px 0 24px;padding:20px 0 0;border-top:1px solid var(--line-2);display:flex;flex-direction:column;gap:12px;flex:1}
  .plan-feats li{display:flex;gap:10px;align-items:flex-start;font-size:14.5px;color:var(--ink-2);line-height:1.45}
  .plan-feats li svg{width:18px;height:18px;color:var(--ok);flex:0 0 18px;margin-top:1px}
  .plan .btn{width:100%;justify-content:center}

  /* Karşılaştırma tablosu */
  .cmp-wrap{margin-top:30px;overflow-x:auto;border:1px solid var(--line);border-radius:var(--radius-lg);background:var(--card)}
  table.cmp{width:100%;border-collapse:collapse;min-width:680px}
  table.cmp th,table.cmp td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--line-2)}
  table.cmp thead th{position:sticky;top:0;background:var(--bg-2);font-size:14px;font-weight:700;color:var(--ink);z-index:1}
  table.cmp thead th.col{text-align:center;width:150px}
  table.cmp thead th.col.pop{color:var(--teal)}
  table.cmp .grp td{background:var(--teal-50);font-size:12.5px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:var(--teal-800)}
  table.cmp td.feat{font-size:14.5px;color:var(--ink-2)}
  table.cmp td.val{text-align:center;font-size:14px;color:var(--muted)}
  table.cmp td.val svg{width:19px;height:19px;color:var(--ok)}
  table.cmp .dash{color:var(--soft)}
  table.cmp .txt{font-size:12.5px;font-weight:600;color:var(--teal-700);background:var(--teal-50);padding:3px 9px;border-radius:999px;display:inline-block}
  table.cmp tbody tr:hover td{background:rgba(37,99,235,.03)}
  table.cmp tbody tr.grp:hover td{background:var(--teal-50)}

  /* Eklentiler */
  .addons{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:34px}
  .addon{display:flex;gap:14px;align-items:flex-start;padding:18px;border:1px solid var(--line);border-radius:var(--radius);background:var(--card);transition:border-color .2s}
  .addon:hover{border-color:var(--teal)}
  .addon .a-ic{flex:0 0 42px;height:42px;border-radius:11px;display:grid;place-items:center;background:var(--teal-50);color:var(--teal)}
  .addon .a-ic svg{width:22px;height:22px}
  .addon h4{font-size:15.5px;font-weight:700;color:var(--ink);margin:0}
  .addon p{margin:4px 0 0;font-size:13.5px;color:var(--muted);line-height:1.45}

  @media(max-width:900px){
    .plans{grid-template-columns:1fr;max-width:440px;margin-inline:auto}
    .addons{grid-template-columns:1fr}
    .plan.pop{order:-1}
  }
</style>
@endpush

@section('content')

@include('marketing.partials.breadcrumb', ['crumbs' => [
    ['t' => 'Ana Sayfa', 'u' => '/'],
    ['t' => 'Fiyatlandırma'],
]])

{{-- HERO --}}
<section class="pr-hero">
    <div class="wrap">
        <span class="eyebrow">{!! $ic['tag'] !!} Fiyatlandırma</span>
        <h1>İşletmenize göre şeffaf fiyat</h1>
        <p class="lead">Şube, terminal ve ihtiyaç duyduğunuz modüllere göre size özel teklif hazırlıyoruz. Yalnız kullandığınız modülleri ödersiniz; kurulum ücreti yoktur.</p>
        <div class="pr-note">{!! $ic['check'] !!} Aylık veya yıllık ödeme — yıllıkta indirim</div>
    </div>
</section>

{{-- GÜVEN AVANTAJLARI --}}
<section class="wrap" style="padding-top:4px">
    <div class="pr-trust">
        @foreach([
            ['check','Kurulum ücreti yok'],
            ['shield','Taahhüt yok — istediğiniz zaman ölçekleyin'],
            ['layers','Yalnız kullandığınız modülü ödersiniz'],
            ['headset','Kurulum & menü aktarım desteği'],
        ] as $t)
            <div class="pr-trust-i reveal">{!! $ic[$t[0]] !!}<span>{{ $t[1] }}</span></div>
        @endforeach
    </div>
</section>

{{-- PAKETLER --}}
<section class="sec" style="padding-top:22px">
    <div class="wrap">
        <div class="plans">
            @foreach($plans as $p)
                <div class="plan @if($p['popular']) pop @endif reveal">
                    @if($p['popular'])<span class="plan-badge">En Popüler</span>@endif
                    <div class="plan-name">{{ $p['name'] }}</div>
                    <div class="plan-for">{{ $p['for'] }}</div>
                    <div class="plan-price">{{ $p['price'] }}<small>işletmenize özel teklif</small></div>
                    <ul class="plan-feats">
                        @foreach($p['features'] as $f)
                            <li>{!! $ic['check'] !!} <span>{{ $f }}</span></li>
                        @endforeach
                    </ul>
                    <a href="/#demo" class="btn {{ $p['popular'] ? 'btn-primary' : 'btn-line' }} btn-lg">{{ $p['cta'] }} {!! $ic['arrow'] !!}</a>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- KARŞILAŞTIRMA --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['grid'] !!} Karşılaştırma</span><h2>Paketler ne içeriyor?</h2></div>
        <div class="cmp-wrap reveal">
            <table class="cmp">
                <thead>
                    <tr>
                        <th>Özellik</th>
                        @foreach($plans as $p)
                            <th class="col @if($p['popular']) pop @endif">{{ $p['name'] }}</th>
                        @endforeach
                    </tr>
                </thead>
                <tbody>
                    @foreach($compare as $group)
                        <tr class="grp"><td colspan="4">{{ $group['g'] }}</td></tr>
                        @foreach($group['rows'] as $row)
                            <tr>
                                <td class="feat">{{ $row[0] }}</td>
                                @for($i = 1; $i <= 3; $i++)
                                    <td class="val">
                                        @if($row[$i] === true)
                                            {!! $ic['check'] !!}<span class="sr-only">Var</span>
                                        @elseif($row[$i] === false)
                                            <span class="dash" aria-label="Yok">—</span>
                                        @else
                                            <span class="txt">{{ $row[$i] }}</span>
                                        @endif
                                    </td>
                                @endfor
                            </tr>
                        @endforeach
                    @endforeach
                </tbody>
            </table>
        </div>
    </div>
</section>

{{-- EKLENTİLER --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['layers'] !!} Eklenti modüller</span><h2>İhtiyacınıza göre ekleyin</h2>
            <p class="lead" style="margin:14px auto 0;max-width:52ch">Bu modüller isteğe bağlıdır; yalnız kullanacağınız modüller teklifinize eklenir.</p>
        </div>
        <div class="addons">
            @foreach($addons as $a)
                <div class="addon reveal">
                    <span class="a-ic">{!! $ic[$a[0]] ?? $ic['grid'] !!}</span>
                    <div><h4>{{ $a[1] }}</h4><p>{{ $a[2] }}</p></div>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- SSS --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['shield'] !!} SSS</span><h2>Fiyatlandırma hakkında sık sorulanlar</h2></div>
        <div class="faq">
            @foreach($faq as $qa)
                <details class="qa"><summary>{{ $qa[0] }} <span class="x">+</span></summary><p>{{ $qa[1] }}</p></details>
            @endforeach
        </div>
    </div>
</section>

@include('marketing.partials.cta-band', ['ctaTitle' => 'Size özel fiyatınızı birkaç dakikada alın'])
@endsection

@push('schema')
<script type="application/ld+json">
{!! json_encode([
    '@'.'context' => 'https://schema.org',
    '@type' => 'FAQPage',
    'mainEntity' => collect($faq)->map(fn ($qa) => [
        '@type' => 'Question', 'name' => $qa[0],
        'acceptedAnswer' => ['@type' => 'Answer', 'text' => $qa[1]],
    ])->all(),
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) !!}
</script>
@endpush
