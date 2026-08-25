<!doctype html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>Hesap askıda — BamBumPOS</title>
    <style>
        :root{ --bg:#f5f8fc; --ink:#0d1b30; --muted:#64748b; --line:#e2e8f0; --brand:#2563eb; --amber:#f59e0b; }
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:
            radial-gradient(800px 420px at 80% -10%, rgba(37,99,235,.10), transparent 60%), var(--bg);
            font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--ink);padding:24px}
        .card{max-width:520px;width:100%;background:#fff;border:1px solid var(--line);border-radius:20px;
            box-shadow:0 24px 60px -30px rgba(13,27,48,.35);padding:38px 34px;text-align:center}
        .badge{width:60px;height:60px;border-radius:16px;margin:0 auto 18px;display:grid;place-items:center;
            background:#fff7ea;border:1px solid #fde3b3;color:#b45309}
        .badge svg{width:30px;height:30px}
        h1{font-size:23px;letter-spacing:-.02em;margin:0 0 10px}
        p{color:var(--muted);line-height:1.65;margin:0 0 18px;font-size:15.5px}
        .biz{font-weight:700;color:var(--ink)}
        .actions{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-top:6px}
        .btn{display:inline-flex;align-items:center;gap:8px;padding:12px 20px;border-radius:11px;font-weight:650;
            font-size:14.5px;text-decoration:none;border:1px solid var(--line);color:var(--ink);background:#fff}
        .btn.p{background:var(--brand);border-color:var(--brand);color:#fff}
        .note{margin-top:20px;font-size:12.5px;color:#94a3b8}
        .flash-err{margin:0 0 16px;padding:10px 14px;border-radius:10px;background:#fef2f2;border:1px solid #fecaca;color:#b91c1c;font-size:13.5px;text-align:left}
        @media (prefers-color-scheme:dark){ .flash-err{background:#2a1414;border-color:#5a2020;color:#fca5a5} }
        .logout{margin-top:14px;font-size:13px}
        .logout a{color:var(--muted)}
        @media (prefers-color-scheme:dark){
            :root{--bg:#0a1220;--ink:#e9eff8;--muted:#8496b0;--line:#20314c}
            .card{background:#0f1c30}
            .badge{background:#2a2110;border-color:#5a4a1e}
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="badge">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="10" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
        </div>
        <h1>Hesabınız şu an askıda</h1>
        @if(session('error'))<div class="flash-err">{{ session('error') }}</div>@endif
        <p>
            @if(!empty($tenantName))<span class="biz">{{ $tenantName }}</span> işletmesinin @endif
            panel erişimi geçici olarak durduruldu. Verileriniz güvende ve eksiksiz duruyor —
            hesap yeniden açıldığında kaldığınız yerden devam edersiniz.
        </p>
        @if(!empty($unpaidInvoice) && empty($paymentProviderManual))
            <p style="margin-top:-4px">
                Ödenmemiş fatura: <b>{{ number_format(((int) $unpaidInvoice->amount_minor) / 100, 2, ',', '.') }} ₺</b>
                — ödemeniz onaylanır onaylanmaz hesabınız otomatik yeniden açılır.
            </p>
        @endif
        <div class="actions">
            @if(!empty($unpaidInvoice) && empty($paymentProviderManual))
                <a class="btn p" href="{{ route('saas.pay', $unpaidInvoice->id) }}">Şimdi Öde</a>
                <a class="btn" href="https://wa.me/{{ ltrim(config('site.contact.whatsapp','+908500000000'),'+') }}" target="_blank" rel="noopener">WhatsApp ile iletişime geç</a>
            @else
                <a class="btn p" href="https://wa.me/{{ ltrim(config('site.contact.whatsapp','+908500000000'),'+') }}" target="_blank" rel="noopener">WhatsApp ile iletişime geç</a>
            @endif
            <a class="btn" href="mailto:{{ config('site.contact.email','satis@bambumpos.com') }}">E-posta gönder</a>
        </div>
        <div class="note">Ödeme / abonelik durumunuzu netleştirmek için bize ulaşın. Hesap yeniden açılınca bu sayfa kaybolur.</div>
        <div class="logout">
            <form method="post" action="{{ route('auth.logout') }}" style="display:inline">@csrf<a href="#" onclick="this.closest('form').submit();return false">Çıkış yap</a></form>
        </div>
    </div>
</body>
</html>
