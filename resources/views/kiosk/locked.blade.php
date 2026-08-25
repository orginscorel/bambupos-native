{{-- Dil: KioskScreenController::show ?lang= parametresini bu view'dan ÖNCE çözer
     (venue/qr-*.blade.php'deki desenle aynı). --}}
@extends('kiosk.layout')

@section('title', $tenantName.' — '.__('kiosk.locked_title_suffix'))

@section('content')
    {{-- Kilit ekranı kendini yoklar: panelden kilit açılınca kiosk canlanır. --}}
    <meta http-equiv="refresh" content="15">

    <main class="k-center">
        <div class="k-center__card">
            <div class="k-center__icon" aria-hidden="true">🔒</div>
            <h1>{{ __('kiosk.locked_heading', ['device' => $deviceName]) }}</h1>
            <p>{{ __('kiosk.locked_body') }}</p>
            <p class="k-center__muted">{{ $tenantName }}</p>
        </div>
    </main>
@endsection
