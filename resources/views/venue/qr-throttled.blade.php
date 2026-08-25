{{-- Rate limit aşımı → 429.
     Dil: PublicMenuController::show ?lang= parametresini bu view'lardan ÖNCE çözer. --}}
<!DOCTYPE html>
<html lang="{{ app()->getLocale() }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ __('menu.qr_throttled_title') }}</title>
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
        <div class="icon" aria-hidden="true">&#9203;</div>
        <h1>{{ __('menu.qr_throttled_title') }}</h1>
        <p>{{ __('menu.qr_throttled_body') }}</p>
    </div>
</body>
</html>
