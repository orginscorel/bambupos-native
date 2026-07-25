@extends('terminal.layout')

@section('title', 'Terminal')

@section('content')
    <main class="t-card">
        @if ($kind === 'revoked' || $kind === 'inactive')
            <div class="t-icon" aria-hidden="true">⟳</div>
            <h1>Bu terminal kaydı artık geçerli değil</h1>
            <p>
                Cihaz adresi yenilendi veya kayıt pasife alındı.
                Lütfen işletme yöneticisinden yeni terminal adresini isteyin.
            </p>
        @elseif ($kind === 'throttled')
            <div class="t-icon" aria-hidden="true">⏳</div>
            <h1>Çok sık istek</h1>
            <p>Lütfen kısa bir süre sonra tekrar deneyin.</p>
        @else
            <div class="t-icon" aria-hidden="true">?</div>
            <h1>Terminal bulunamadı</h1>
            <p>Bu adres geçerli bir istasyon terminaline ait değil.</p>
        @endif
    </main>
@endsection
