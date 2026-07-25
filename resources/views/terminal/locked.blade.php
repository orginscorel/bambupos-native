@extends('terminal.layout')

@section('title', $tenantName.' — Terminal')

@section('content')
    {{-- Kilit ekranı kendini yoklar: panelden kilit açılınca terminal canlanır. --}}
    <meta http-equiv="refresh" content="15">

    <main class="t-card">
        <div class="t-icon" aria-hidden="true">🔒</div>
        <h1>{{ $deviceName }} geçici olarak kapalı</h1>
        <p>Bu terminal yönetici tarafından kilitlendi. Lütfen personele başvurun.</p>
        <p class="t-muted">{{ $tenantName }}</p>
    </main>
@endsection
