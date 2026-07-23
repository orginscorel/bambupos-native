<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Rezervasyonum</title>
    <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
            background: #f4f4f5; color: #18181b; min-height: 100vh;
            display: flex; align-items: center; justify-content: center; padding: 1rem;
        }
        @media (prefers-color-scheme: dark) { body { background: #18181b; color: #fafafa; } .card { background: #27272a !important; } }
        .card { background: #fff; border-radius: 16px; box-shadow: 0 4px 24px rgb(0 0 0 / .08); max-width: 420px; width: 100%; padding: 2rem; }
        h1 { font-size: 1.25rem; margin-bottom: 1rem; }
        dl { display: grid; grid-template-columns: auto 1fr; gap: .5rem 1rem; margin-bottom: 1.25rem; font-size: .95rem; }
        dt { opacity: .65; }
        dd { font-weight: 600; text-align: right; }
        .badge { display: inline-block; padding: .3rem .75rem; border-radius: 999px; font-size: .85rem; font-weight: 600; }
        .b-ok { background: #dcfce7; color: #166534; }
        .b-warn { background: #fef9c3; color: #854d0e; }
        .b-bad { background: #fee2e2; color: #991b1b; }
        .b-muted { background: #e4e4e7; color: #3f3f46; }
        form { margin-top: 1rem; }
        button {
            width: 100%; padding: .8rem; border: 0; border-radius: 10px; cursor: pointer;
            background: #dc2626; color: #fff; font-size: 1rem; font-weight: 600;
        }
        button:hover { background: #b91c1c; }
        .note { margin-top: .75rem; font-size: .85rem; opacity: .65; text-align: center; }
        .flash { margin-bottom: 1rem; padding: .75rem 1rem; border-radius: 10px; background: #dcfce7; color: #166534; font-size: .9rem; }
    </style>
</head>
<body>
@php
    $status = $reservation->status;
    $badgeClass = match ($status->variant()) {
        'success', 'primary' => 'b-ok',
        'warning', 'info' => 'b-warn',
        'danger' => 'b-bad',
        default => 'b-muted',
    };
@endphp
<div class="card">
    @if (session('status') === 'cancelled')
        <div class="flash">Rezervasyonunuz iptal edildi.</div>
    @endif

    <h1>Rezervasyonum</h1>

    <dl>
        <dt>Ad Soyad</dt><dd>{{ $reservation->customer_name }}</dd>
        <dt>Tarih</dt><dd>{{ $reservation->reserved_at->format('d.m.Y') }}</dd>
        <dt>Saat</dt><dd>{{ $reservation->reserved_at->format('H:i') }}</dd>
        <dt>Kişi</dt><dd>{{ $reservation->party_size }} kişi</dd>
        <dt>Durum</dt><dd><span class="badge {{ $badgeClass }}">{{ $status->label() }}</span></dd>
    </dl>

    @if ($canCancel)
        <form method="POST" action="/r/{{ $reservation->confirmation_token }}/iptal"
              onsubmit="return confirm('Rezervasyonunuzu iptal etmek istediğinize emin misiniz?')">
            @csrf
            <button type="submit">Rezervasyonu İptal Et</button>
        </form>
        <p class="note">Değişiklik için lütfen işletmeyi arayın.</p>
    @endif
</div>
</body>
</html>
