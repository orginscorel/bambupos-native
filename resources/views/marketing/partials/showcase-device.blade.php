{{-- Premium cihaz görseli: masaüstü ekranlar için macOS tarayıcı çerçevesi (16:10, net, zarif ken-burns),
     mobil (qr) için telefon çerçevesi (dikey pan = menüde gezinme hissi).
     Parametreler: $scScreen, $scUrl, $scAlt, $scDelay, $scMode ('phone' zorlar) --}}
@php
    $ic = $ic ?? \App\Modules\Marketing\Support\Icons::all();
    // Eski isimler → yeni net ekranlar
    $alias = ['adisyon' => 'siparisler', 'manager' => 'dashboard'];
    $screen = $scScreen ?? 'siparisler';
    $screen = $alias[$screen] ?? $screen;
    $isPhone = ($screen === 'qr') || (($scMode ?? '') === 'phone');
    $v = 'v=3';
@endphp
@if($isPhone)
    <div class="sc-phone reveal">
        <span class="sc-phone-cam"></span>
        <div class="sc-phone-scr">
            <img class="sc-plive" src="/assets/site/screens/qr.jpg?{{ $v }}"
                 alt="{{ $scAlt ?? 'BamBumPOS QR menü' }}" loading="lazy" decoding="async"
                 style="animation-delay:{{ $scDelay ?? '0s' }}">
        </div>
    </div>
@else
    <div class="sc-shot reveal">
        <div class="frame-bar"><i></i><i></i><i></i><span class="fb-url">{{ $scUrl ?? 'panel.bambumpos.com' }}</span></div>
        <div class="sc-view">
            <img class="sc-live" src="/assets/site/screens/{{ $screen }}.jpg?{{ $v }}"
                 alt="{{ $scAlt ?? 'BamBumPOS ekran görüntüsü' }}" loading="lazy" decoding="async"
                 style="animation-delay:{{ $scDelay ?? '0s' }}">
        </div>
        <span class="sc-badge">{!! $ic['zap'] !!} Canlı ekran</span>
    </div>
@endif
