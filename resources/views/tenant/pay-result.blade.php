<!doctype html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>Ödeme durumu — BamBumPOS</title>
    <style>
        :root{ --bg:#f5f8fc; --ink:#0d1b30; --muted:#64748b; --line:#e2e8f0; --brand:#2563eb; }
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:
            radial-gradient(800px 420px at 80% -10%, rgba(37,99,235,.10), transparent 60%), var(--bg);
            font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--ink);padding:24px}
        .card{max-width:480px;width:100%;background:#fff;border:1px solid var(--line);border-radius:20px;
            box-shadow:0 24px 60px -30px rgba(13,27,48,.35);padding:38px 34px;text-align:center}
        .badge{width:60px;height:60px;border-radius:16px;margin:0 auto 18px;display:grid;place-items:center}
        .badge svg{width:30px;height:30px}
        h1{font-size:22px;letter-spacing:-.02em;margin:0 0 10px}
        p{color:var(--muted);line-height:1.65;margin:0 0 18px;font-size:15px}
        .btn{display:inline-flex;align-items:center;gap:8px;padding:12px 20px;border-radius:11px;font-weight:650;
            font-size:14.5px;text-decoration:none;border:1px solid var(--brand);background:var(--brand);color:#fff}
        @media (prefers-color-scheme:dark){ :root{--bg:#0a1220;--ink:#e9eff8;--muted:#8496b0;--line:#20314c} .card{background:#0f1c30} }
    </style>
</head>
<body>
    <div class="card">
        @if($status === 'ok')
            <div class="badge" style="background:#ecfdf5;border:1px solid #a7f3d0;color:#059669">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>
            </div>
            <h1>Ödemeniz alınıyor</h1>
            <p>Sağlayıcı ödemenizi onayladı. Hesabınız, tahsilatın sistemimize DOĞRULANMASININ (birkaç dakika sürebilir)
                ardından otomatik olarak yeniden açılacaktır — sayfayı yenileyerek kontrol edebilirsiniz.</p>
        @elseif($status === 'already_paid')
            <div class="badge" style="background:#ecfdf5;border:1px solid #a7f3d0;color:#059669">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>
            </div>
            <h1>Bu fatura zaten ödenmiş</h1>
            <p>Ek bir işlem yapmanıza gerek yok.</p>
        @elseif($status === 'fail')
            <div class="badge" style="background:#fef2f2;border:1px solid #fecaca;color:#b91c1c">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </div>
            <h1>Ödeme tamamlanamadı</h1>
            <p>Kart/ödeme sağlayıcı işlemi reddetti veya yarıda kesildi. Tekrar deneyebilir ya da bizimle iletişime geçebilirsiniz.</p>
        @else
            <div class="badge" style="background:#fff7ea;border:1px solid #fde3b3;color:#b45309">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>
            </div>
            <h1>Ödeme işleniyor</h1>
            <p>Durumu netleştirmek için birkaç dakika bekleyip sayfayı yenileyin.</p>
        @endif
        <a class="btn" href="{{ route('tenant.suspended') }}">Hesap durumuma dön</a>
    </div>
</body>
</html>
