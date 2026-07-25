@extends('kiosk.layout')

@section('title', $tenantName.' — Kiosk')

@section('content')
    {{-- Kilit ekranı kendini yoklar: panelden kilit açılınca kiosk canlanır. --}}
    <meta http-equiv="refresh" content="15">

    <main class="k-center">
        <div class="k-center__card">
            <div class="k-center__icon" aria-hidden="true">🔒</div>
            <h1>{{ $deviceName }} geçici olarak kapalı</h1>
            <p>Bu kiosk yönetici tarafından kilitlendi. Lütfen personele başvurun.</p>
            <p class="k-center__muted">{{ $tenantName }}</p>
        </div>
    </main>
@endsection
