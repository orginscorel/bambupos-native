@extends('kiosk.layout')

@section('title', 'Kiosk')

@section('content')
    <main class="k-center">
        <div class="k-center__card">
            @if ($kind === 'revoked' || $kind === 'inactive')
                <div class="k-center__icon" aria-hidden="true">⟳</div>
                <h1>Bu kiosk kaydı artık geçerli değil</h1>
                <p>
                    Cihaz adresi yenilendi veya kayıt pasife alındı.
                    Lütfen işletme yöneticisinden yeni kiosk adresini isteyin.
                </p>
            @elseif ($kind === 'throttled')
                <div class="k-center__icon" aria-hidden="true">⏳</div>
                <h1>Çok sık istek</h1>
                <p>Lütfen kısa bir süre sonra tekrar deneyin.</p>
            @else
                <div class="k-center__icon" aria-hidden="true">?</div>
                <h1>Kiosk bulunamadı</h1>
                <p>Bu adres geçerli bir kiosk cihazına ait değil.</p>
            @endif
        </div>
    </main>
@endsection
