{{-- Dil: KioskScreenController::show ?lang= parametresini bu view'dan ÖNCE çözer
     (venue/qr-*.blade.php'deki desenle aynı — token/kayıt daha çözülmeden dönen
     bu sayfa aksi halde hep TR kalırdı). --}}
@extends('kiosk.layout')

@section('title', __('kiosk.error_title'))

@section('content')
    <main class="k-center">
        <div class="k-center__card">
            @if ($kind === 'revoked' || $kind === 'inactive')
                <div class="k-center__icon" aria-hidden="true">⟳</div>
                <h1>{{ __('kiosk.error_gone_heading') }}</h1>
                <p>{{ __('kiosk.error_gone_body') }}</p>
            @elseif ($kind === 'throttled')
                <div class="k-center__icon" aria-hidden="true">⏳</div>
                <h1>{{ __('kiosk.error_throttled_heading') }}</h1>
                <p>{{ __('kiosk.error_throttled_body') }}</p>
            @else
                <div class="k-center__icon" aria-hidden="true">?</div>
                <h1>{{ __('kiosk.error_invalid_heading') }}</h1>
                <p>{{ __('kiosk.error_invalid_body') }}</p>
            @endif
        </div>
    </main>
@endsection
