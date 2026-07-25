{{--
    Terminal kabuğu (§13, Faz A) — yalnız hata/kilit ekranları için hafif,
    KENDİNE YETER (asset bağımlılığı yok) sayfa. Geçerli token durumunda bu
    kabuk KULLANILMAZ: oto-giriş yapılır ve istasyon ekranına yönlenir.
--}}
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="robots" content="noindex, nofollow">
    <title>@yield('title', 'Terminal')</title>
    <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        html, body { height: 100%; margin: 0; }
        body {
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            display: grid;
            place-items: center;
            padding: 24px;
            -webkit-text-size-adjust: 100%;
        }
        .t-card {
            width: 100%;
            max-width: 30rem;
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: 16px;
            padding: 40px 32px;
            text-align: center;
            box-shadow: 0 20px 60px rgba(0,0,0,.35);
        }
        .t-icon { font-size: 44px; line-height: 1; margin-bottom: 16px; }
        h1 { font-size: 1.25rem; margin: 0 0 12px; color: #f8fafc; }
        p { margin: 0 0 8px; color: #cbd5e1; line-height: 1.5; }
        .t-muted { color: #94a3b8; font-size: .875rem; margin-top: 16px; }
    </style>
</head>
<body>
    @yield('content')
</body>
</html>
