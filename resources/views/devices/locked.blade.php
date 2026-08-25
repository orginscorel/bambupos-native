<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Cihaz yetkili değil</title>
    <style>
        body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
            font-family: system-ui, -apple-system, "Segoe UI", sans-serif; background: #0f172a; color: #f1f5f9; }
        .card { max-width: 26rem; margin: 1.5rem; padding: 2rem; border-radius: 1rem; background: #1e293b;
            box-shadow: 0 10px 30px rgba(0,0,0,.35); text-align: center; }
        .icon { font-size: 2.5rem; margin-bottom: .75rem; }
        h1 { font-size: 1.15rem; margin: 0 0 .5rem; }
        p { margin: 0; color: #94a3b8; font-size: .9rem; line-height: 1.5; }
    </style>
</head>
<body>
    <main class="card">
        <div class="icon" aria-hidden="true">🔒</div>
        <h1>Bu cihaz yetkili değil</h1>
        <p>{{ $message }}</p>
        <p style="margin-top:.75rem">Gerekiyorsa yöneticinizden Panel &rarr; İzinli Cihazlar ekranından erişimi düzenlemesini isteyin.</p>
    </main>
</body>
</html>
