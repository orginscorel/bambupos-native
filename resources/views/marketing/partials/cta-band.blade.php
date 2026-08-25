@php($ic = \App\Modules\Marketing\Support\Icons::all())
<section class="sec dark center">
    <div class="wrap">
        <h2 style="color:#fff;font-size:clamp(24px,3.2vw,36px);font-weight:800;letter-spacing:-.025em">{{ $ctaTitle ?? 'İşletmenizi BamBumPOS ile yönetmeye başlayın' }}</h2>
        <p style="color:#9db8b5;font-size:16.5px;margin:14px auto 26px;max-width:560px">{{ $ctaText ?? 'Kurulum ve menü aktarımıyla dakikalar içinde hazır olun. Taahhüt gerekmez.' }}</p>
        <div style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap">
            <a href="/#demo" class="btn btn-primary btn-lg">Ücretsiz Demo Talep Et {!! $ic['arrow'] !!}</a>
            <a href="https://wa.me/{{ ltrim(config('site.contact.whatsapp'),'+') }}" target="_blank" rel="noopener" class="btn btn-ghost btn-lg">WhatsApp’tan Yaz</a>
        </div>
    </div>
</section>
