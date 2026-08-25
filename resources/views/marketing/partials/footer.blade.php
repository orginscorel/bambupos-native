@php
    $site = config('site');
    $c = $site['contact'];
    $year = now()->year;
@endphp
<footer class="site-footer">
    <div class="wrap">
        <div class="foot-grid">
            <div class="foot-brand">
                <a href="/" class="brand-logo">@include('marketing.partials.logo', ['logoDark' => true])</a>
                <p>Restoran, kafe ve tesisiniz için satıştan mutfağa, personelden stoğa, ödemeden raporlamaya tüm operasyonu tek platformda yöneten bulut tabanlı işletme sistemi.</p>
                <div class="foot-contact">
                    <a href="mailto:{{ $c['email'] }}">
                        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></svg>
                        <span>{{ $c['email'] }}</span>
                    </a>
                    <a href="https://wa.me/{{ ltrim($c['whatsapp'],'+') }}" target="_blank" rel="noopener">
                        <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M12 2a10 10 0 0 0-8.6 15l-1.3 4.7 4.8-1.3A10 10 0 1 0 12 2Zm5.3 14.1c-.2.6-1.3 1.2-1.8 1.2-.5.1-1 .1-3.2-.8-2.7-1.1-4.4-3.9-4.5-4.1-.1-.2-1.1-1.5-1.1-2.8s.7-2 .9-2.2c.2-.3.5-.3.7-.3h.5c.2 0 .4 0 .6.5l.8 2c.1.2.1.4 0 .5l-.4.5c-.2.2-.3.4-.1.6.2.4.9 1.4 1.9 2.3 1.2 1 2.2 1.4 2.5 1.5.2.1.4.1.6-.1l.7-.9c.2-.2.4-.2.6-.1l2 .9c.2.1.4.2.4.3.1.2.1.9-.1 1.5Z"/></svg>
                        <span>WhatsApp destek hattı</span>
                    </a>
                    <span class="foot-hours">
                        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>
                        <span>{{ $c['hours'] }}</span>
                    </span>
                </div>
                <div class="foot-social" aria-label="Sosyal medya">
                    <a href="tel:{{ $c['phone_raw'] }}" aria-label="Telefon">
                        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2 4.2 2 2 0 0 1 4 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.2a2 2 0 0 1 2.1-.5c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2Z"/></svg>
                    </a>
                    <a href="https://wa.me/{{ ltrim($c['whatsapp'],'+') }}" target="_blank" rel="noopener" aria-label="WhatsApp">
                        <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M12 2a10 10 0 0 0-8.6 15l-1.3 4.7 4.8-1.3A10 10 0 1 0 12 2Zm5.3 14.1c-.2.6-1.3 1.2-1.8 1.2-.5.1-1 .1-3.2-.8-2.7-1.1-4.4-3.9-4.5-4.1-.1-.2-1.1-1.5-1.1-2.8s.7-2 .9-2.2c.2-.3.5-.3.7-.3h.5c.2 0 .4 0 .6.5l.8 2c.1.2.1.4 0 .5l-.4.5c-.2.2-.3.4-.1.6.2.4.9 1.4 1.9 2.3 1.2 1 2.2 1.4 2.5 1.5.2.1.4.1.6-.1l.7-.9c.2-.2.4-.2.6-.1l2 .9c.2.1.4.2.4.3.1.2.1.9-.1 1.5Z"/></svg>
                    </a>
                    <a href="mailto:{{ $c['email'] }}" aria-label="E-posta">
                        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></svg>
                    </a>
                </div>
            </div>
            @foreach($site['footer'] as $col)
                <div class="foot-col">
                    <h4>{{ $col['h'] }}</h4>
                    @foreach($col['items'] as $it)
                        <a href="{{ $it['u'] }}">{{ $it['t'] }}</a>
                    @endforeach
                </div>
            @endforeach
        </div>

        <div class="foot-bottom">
            <div>© {{ $year }} BamBumPOS · <span style="color:#9fbaad">{{ $site['brand']['infra'] }}</span></div>
            <div style="display:flex;gap:18px;flex-wrap:wrap">
                <a href="/gizlilik-politikasi">Gizlilik</a>
                <a href="/kvkk">KVKK</a>
                <a href="/cerez-politikasi">Çerez Tercihleri</a>
                <a href="/#demo">Demo Talep Et</a>
            </div>
        </div>
    </div>
</footer>
