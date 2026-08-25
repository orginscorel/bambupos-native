@php
    $site = config('site');
    $mega = $site['mega'];
    $c = $site['contact'];
    $ic = \App\Modules\Marketing\Support\Icons::all();
    $caret = '<svg class="caret" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>';
    // Slug → özgün ikon (her mega öğesi farklı)
    $mi = [
        '/kafe-pos-sistemi' => 'coffee', '/restoran-pos-sistemi' => 'utensils', '/nargile-salonu-pos-sistemi' => 'flame',
        '/bar-pub-pos-sistemi' => 'glass', '/fast-food-pos-sistemi' => 'burger', '/otel-pos-sistemi' => 'bed',
        '/paket-servis-pos-sistemi' => 'truck', '/cok-subeli-restoran-yonetimi' => 'branch',
        '/mobil-pos' => 'phone', '/qr-menu' => 'qr', '/online-siparis' => 'globe', '/self-servis-kiosk' => 'kiosk',
        '/garson-uygulamasi' => 'users', '/mutfak-ekran-sistemi' => 'chef', '/barista-ekrani' => 'coffee',
        '/nargile-hazirlik-ekrani' => 'flame', '/paket-siparis-yonetimi' => 'box', '/kurye-yonetimi' => 'truck',
        '/personel-yonetimi' => 'users', '/stok-yonetimi' => 'box', '/uretim-recete' => 'layers', '/on-muhasebe' => 'receipt',
        '/tedarikci-yonetimi' => 'truck', '/satis-raporlari' => 'chart', '/coklu-sube-yonetimi' => 'branch',
        '/rezervasyon-yonetimi' => 'calendar', '/musteri-sadakat' => 'tag', '/kampanya-yonetimi' => 'megaphone',
        '/entegrasyonlar?k=odeme' => 'card', '/entegrasyonlar?k=okc' => 'receipt', '/entegrasyonlar?k=donanim' => 'box',
        '/entegrasyonlar?k=paket' => 'truck', '/entegrasyonlar?k=muhasebe' => 'chart', '/entegrasyonlar?k=api' => 'plug',
        '/entegrasyonlar' => 'grid',
        '/hakkimizda' => 'store', '/neden-bambumpos' => 'target', '/guvenlik-altyapi' => 'shield', '/referanslar' => 'tag',
        '/is-ortakligi' => 'branch', '/kariyer' => 'users', '/blog' => 'receipt', '/iletisim' => 'headset', '/destek' => 'headset',
    ];
@endphp
<header class="site-header">
    <div class="wrap">
        <div class="header-inner">
            <a href="/" class="brand-logo" aria-label="BamBumPOS ana sayfa">@include('marketing.partials.logo')</a>

            <nav class="header-nav" aria-label="Ana menü">
                @foreach($mega as $m)
                    @if(!empty($m['link']))
                        <div class="nav-root"><a href="{{ $m['link'] }}">{{ $m['label'] }}</a></div>
                    @else
                        <div class="nav-root">
                            <button type="button" aria-haspopup="true">{{ $m['label'] }} {!! $caret !!}</button>
                            <div class="mega {{ empty($m['feature']) ? 'two-col' : '' }} {{ in_array($m['label'], ['Entegrasyonlar', 'Kurumsal']) ? 'mega-right' : '' }}">
                                @foreach($m['columns'] as $col)
                                    <div class="mega-col">
                                        <div class="mega-h">{{ $col['heading'] }}</div>
                                        @foreach($col['items'] as $it)
                                            <a class="mega-item" href="{{ $it['u'] }}">
                                                <span class="mi-ic">{!! $ic[$mi[$it['u']] ?? 'grid'] !!}</span>
                                                <span>
                                                    <span class="mi-t">{{ $it['t'] }}</span>
                                                    @if(!empty($it['d']))<span class="mi-d">{{ $it['d'] }}</span>@endif
                                                </span>
                                            </a>
                                        @endforeach
                                    </div>
                                @endforeach
                                @if(!empty($m['feature']))
                                    <a class="mega-feature" href="{{ $m['feature']['u'] }}">
                                        <div>
                                            <div class="mf-t">{{ $m['feature']['t'] }}</div>
                                            <div class="mf-d">{{ $m['feature']['d'] }}</div>
                                        </div>
                                        <span class="btn btn-primary btn-sm" style="align-self:flex-start">{{ $m['feature']['cta'] }}</span>
                                    </a>
                                @endif
                            </div>
                        </div>
                    @endif
                @endforeach
            </nav>

            <div class="header-actions">
                {{-- Dil seçici — globe + kod, zengin dropdown --}}
                <div class="lang-switch" tabindex="0" aria-label="Dil seçimi" aria-haspopup="true">
                    <button class="lang-btn" type="button">
                        <span class="lang-flag">@include('marketing.partials.flag',['f'=>'tr'])</span>
                        <b>TR</b>{!! $caret !!}
                    </button>
                    <div class="lang-pop">
                        <div class="pop-h">Dil / Language</div>
                        <a class="lang-opt on" href="/"><span class="fc">@include('marketing.partials.flag',['f'=>'tr'])</span><span class="lo-t"><b>Türkçe</b><small>Türkiye</small></span><i class="ck">✓</i></a>
                        <span class="lang-opt off"><span class="fc">@include('marketing.partials.flag',['f'=>'en'])</span><span class="lo-t"><b>English</b><small>Yakında</small></span></span>
                        <span class="lang-opt off"><span class="fc">@include('marketing.partials.flag',['f'=>'de'])</span><span class="lo-t"><b>Deutsch</b><small>Yakında</small></span></span>
                    </div>
                </div>

                {{-- Giriş Yap — zengin dropdown (yönetim + personel) --}}
                <div class="login-menu" tabindex="0" aria-haspopup="true">
                    <button class="btn btn-primary btn-sm login-trigger" type="button">
                        <svg class="li-ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><path d="M10 17l5-5-5-5M15 12H3"/></svg>
                        Giriş Yap {!! $caret !!}
                    </button>
                    <div class="login-pop">
                        <div class="pop-h">Hesabınıza girin</div>
                        <a class="login-opt" href="/giris">
                            <span class="lo-ic">{!! $ic['store'] !!}</span>
                            <span class="lo-t"><b>Yönetim Paneli</b><small>İşletme sahibi &amp; yönetici girişi</small></span>
                            {!! $ic['arrow'] !!}
                        </a>
                        <a class="login-opt" href="/giris/pin">
                            <span class="lo-ic">{!! $ic['users'] !!}</span>
                            <span class="lo-t"><b>Personel Girişi</b><small>PIN ile hızlı personel girişi</small></span>
                            {!! $ic['arrow'] !!}
                        </a>
                    </div>
                </div>

                <button class="hamb" aria-label="Menüyü aç" aria-controls="mobileMenu">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
                </button>
            </div>
        </div>
    </div>
</header>

{{-- Mobil tam ekran menü --}}
<div class="mobile-menu" id="mobileMenu" aria-hidden="true">
    <div class="mm-top">
        <a href="/" class="brand-logo">@include('marketing.partials.logo')</a>
        <button class="mm-close" aria-label="Menüyü kapat">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
        </button>
    </div>
    <div class="mm-body">
        @foreach($mega as $m)
            @if(!empty($m['link']))
                <div class="mm-acc"><button type="button" onclick="location.href='{{ $m['link'] }}'">{{ $m['label'] }}</button></div>
            @else
                <div class="mm-acc">
                    <button type="button">{{ $m['label'] }} {!! $caret !!}</button>
                    <div class="mm-panel">
                        @foreach($m['columns'] as $col)
                            @foreach($col['items'] as $it)
                                <a href="{{ $it['u'] }}">{{ $it['t'] }}</a>
                            @endforeach
                        @endforeach
                    </div>
                </div>
            @endif
        @endforeach
        <div style="margin-top:16px"><a href="/giris" style="display:block;padding:12px;font-weight:700;color:var(--teal-700)">Giriş →</a></div>
    </div>
    <div class="mm-cta">
        <div class="mm-contact">
            <a href="tel:{{ $c['phone_raw'] }}">Telefon</a>
            <a href="https://wa.me/{{ ltrim($c['whatsapp'],'+') }}" target="_blank" rel="noopener">WhatsApp</a>
        </div>
        <a href="/#demo" class="btn btn-primary" style="width:100%">Ücretsiz Demo Talep Et</a>
    </div>
</div>
