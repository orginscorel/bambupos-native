{{-- Geçersiz/bilinmeyen QR token → 404 (bilgi sızdırmayan tek tip yanıt). --}}
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Menü bulunamadı</title>
    <style>
        body { font-family: system-ui, -apple-system, sans-serif; background: #f7f5f2; color: #1f2937; display: grid; place-items: center; min-height: 100dvh; margin: 0; padding: 24px; }
        .card { background: #fff; border-radius: 16px; padding: 32px 28px; max-width: 420px; text-align: center; box-shadow: 0 4px 24px rgba(0,0,0,.06); }
        .icon { font-size: 40px; }
        h1 { font-size: 19px; margin: 12px 0 8px; }
        p { font-size: 15px; color: #4b5563; line-height: 1.55; margin: 0; }
    </style>
</head>
<body>
    <div class="card" role="alert">
        <div class="icon" aria-hidden="true">&#128269;</div>
        <h1>Menü bulunamadı</h1>
        <p>Okuttuğunuz QR kod tanınmadı. Lütfen masadaki QR kodu yeniden okutun veya personelden yardım isteyin.</p>
    </div>
</body>
</html>
