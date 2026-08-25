@extends('yonetim.layout')
@section('title', 'Faturalama')
@section('sub', 'SaaS abonelik & faturalama genel bakışı — salt okunur')

@php
    $fmt = fn ($m) => number_format(((int) ($m ?? 0)) / 100, 2, ',', '.') . ' ₺';
    $planLabel = fn ($k) => optional($plans->firstWhere('key', $k))->name ?? ($k ?: '—');
    $statusB = fn ($s) => ['active' => 'b-green', 'trial' => 'b-amber', 'past_due' => 'b-rose', 'cancelled' => 'b-slate'][$s] ?? 'b-slate';
    $statusT = fn ($s) => ['active' => 'Aktif', 'trial' => 'Deneme', 'past_due' => 'Gecikmiş', 'cancelled' => 'İptal'][$s] ?? $s;
    $invB = fn ($s) => ['paid' => 'b-green', 'unpaid' => 'b-amber', 'void' => 'b-slate', 'draft' => 'b-indigo'][$s] ?? 'b-slate';
    $invT = fn ($s) => ['paid' => 'Ödendi', 'unpaid' => 'Ödenmedi', 'void' => 'İptal', 'draft' => 'Taslak'][$s] ?? $s;
    // Ödeme geçidi modu — config/saas_payment.php (env SAAS_PAYMENT_PROVIDER). 'manual' ise
    // hiçbir canlı sağlayıcı yapılandırılmamış demektir (bkz. SaasPaymentRegistry).
    $payProvider = (string) config('saas_payment.provider', 'manual');
@endphp

@section('content')
    <div class="kpis">
        <div class="kpi"><div class="l">MRR (aylık yinelenen gelir)</div><div class="v g">{{ $fmt($mrrMinor) }}</div><div class="s">{{ $activeCount }} aktif abonelik</div></div>
        <div class="kpi"><div class="l">Denemede</div><div class="v w">{{ $trialCount }}</div><div class="s">{{ $pastDueCount }} gecikmiş · {{ $cancelledCount }} iptal</div></div>
        <div class="kpi"><div class="l">7 gün içinde yenileme</div><div class="v b">{{ $upcoming7->count() }}</div><div class="s">30 günde {{ $upcoming30->count() }}</div></div>
        <div class="kpi"><div class="l">Ödenmemiş fatura</div><div class="v c">{{ $unpaidCount }}</div><div class="s">{{ $fmt($unpaidMinor) }} toplam</div></div>
    </div>

    <div class="card" style="margin-bottom:16px">
        <div class="sec-t">
            Ödeme geçidi modu
            <span class="b {{ $payProvider === 'manual' ? 'b-amber' : 'b-green' }}" style="margin-left:8px">
                {{ ['manual' => 'Manuel (elle tahsilat)', 'iyzico' => 'iyzico (canlı)', 'paytr' => 'PayTR (canlı)'][$payProvider] ?? $payProvider }}
            </span>
        </div>
        <div style="font-size:13px;color:var(--soft)">
            @if($payProvider === 'manual')
                Hiçbir ödeme sağlayıcısı yapılandırılmadı — canlı/otomatik tahsilat YOK. Aşağıdaki tabloda ödenmemiş
                bir fatura tahsil edildiğinde <b>"Elle ödendi işaretle"</b> ile kaydedin (dönem otomatik uzatılır, askıdaki işletme varsa yeniden açılır).
            @else
                Aktif sağlayıcı üzerinden ödenmemiş faturalar için tenant'a gönderilecek ödeme bağlantısı üretilebilir
                (<b>"Ödeme bağlantısı"</b>). Gerçek tahsilat onayı normalde YALNIZ sağlayıcı webhook'u geldiğinde işlenir;
                <b>"Elle ödendi işaretle"</b> acil/istisnai durumlar (ör. havale) için hâlâ kullanılabilir.
            @endif
        </div>
    </div>

    <div class="grid2" style="margin-bottom:16px">
        <div class="card">
            <div class="sec-t">Plan dağılımı <span style="font-size:12px;color:var(--soft);font-weight:600">deneme + aktif + gecikmiş</span></div>
            <table>
                <thead><tr><th>Plan</th><th>Aylık fiyat</th><th style="text-align:right">İşletme sayısı</th></tr></thead>
                <tbody>
                @forelse($plans as $p)
                    <tr>
                        <td><b>{{ $p->name }}</b><div style="font-size:12px;color:var(--soft)">{{ $p->key }}</div></td>
                        <td class="num">{{ $p->price_minor > 0 ? $fmt($p->price_minor) . '/' . ($p->interval === 'yearly' ? 'yıl' : 'ay') : 'Ücretsiz' }}</td>
                        <td style="text-align:right" class="num"><b>{{ (int) ($planDistribution[$p->key] ?? 0) }}</b></td>
                    </tr>
                @empty
                    <tr><td colspan="3" class="empty">Henüz plan tanımlı değil.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
        <div class="card">
            <div class="sec-t">Yaklaşan yenilemeler · 30 gün</div>
            <table>
                <thead><tr><th>İşletme</th><th>Plan</th><th>Durum</th><th style="text-align:right">Tarih</th></tr></thead>
                <tbody>
                @forelse($upcoming30 as $r)
                    <tr>
                        <td><b>{{ $r->tenant_name }}</b></td>
                        <td><span class="b b-indigo">{{ $r->plan_name }}</span></td>
                        <td><span class="b {{ $statusB($r->status) }}">{{ $statusT($r->status) }}</span></td>
                        <td style="text-align:right" class="num">{{ \Illuminate\Support\Carbon::parse($r->current_period_end)->format('d.m.Y') }}</td>
                    </tr>
                @empty
                    <tr><td colspan="4" class="empty">Önümüzdeki 30 günde yenileme yok.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <div class="card">
        <div class="sec-t">Son faturalar</div>
        <table>
            <thead><tr><th>No</th><th>İşletme</th><th style="text-align:right">Tutar</th><th>Durum</th><th>Kesim</th><th>Vade</th><th>Ödeme</th><th>İşlem</th></tr></thead>
            <tbody>
            @forelse($recentInvoices as $i)
                <tr>
                    <td class="num">{{ $i->number }}</td>
                    <td><b>{{ $i->tenant_name }}</b></td>
                    <td style="text-align:right" class="num">{{ $fmt($i->amount_minor) }}</td>
                    <td><span class="b {{ $invB($i->status) }}">{{ $invT($i->status) }}</span></td>
                    <td class="num" style="font-size:13px;color:var(--muted)">{{ $i->issued_at ? \Illuminate\Support\Carbon::parse($i->issued_at)->format('d.m.Y') : '—' }}</td>
                    <td class="num" style="font-size:13px;color:var(--muted)">{{ $i->due_at ? \Illuminate\Support\Carbon::parse($i->due_at)->format('d.m.Y') : '—' }}</td>
                    <td class="num" style="font-size:13px;color:var(--muted)">{{ $i->paid_at ? \Illuminate\Support\Carbon::parse($i->paid_at)->format('d.m.Y') : '—' }}</td>
                    <td>
                        @if($i->status === 'unpaid')
                            <div style="display:flex;gap:6px;flex-wrap:wrap">
                                @if($payProvider !== 'manual')
                                    <button type="button" class="btn btn-sm" onclick="bbPayLink('{{ route('superadmin.billing.pay-link', $i->id) }}', this)">Ödeme bağlantısı</button>
                                @endif
                                <form method="post" action="{{ route('superadmin.billing.mark-paid', $i->id) }}" onsubmit="return confirm('{{ $i->number }} elle ödendi işaretlensin mi? Dönem otomatik uzatılır, askıdaki işletme varsa yeniden açılır.')" style="display:inline">
                                    @csrf
                                    <button class="btn btn-sm" style="color:#16a34a">Elle ödendi işaretle</button>
                                </form>
                            </div>
                        @else
                            <span style="font-size:12px;color:var(--soft)">—</span>
                        @endif
                    </td>
                </tr>
            @empty
                <tr><td colspan="8" class="empty">Henüz SaaS faturası yok. (BillingService::recordInvoice ile oluşturulur.)</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
@endsection

@section('scripts')
    <script>
        // Süper-admin "Ödeme bağlantısı" butonu: aktif sağlayıcıdan (iyzico/PayTR)
        // hosted checkout URL'i üretir (SaasBillingActionController::payLink),
        // panoya kopyalar + görüntüler. Sağlayıcı yapılandırılmamışsa/hata
        // verirse mesajı gösterir. Hiçbir "ödendi" DURUMU DEĞİŞTİRMEZ.
        async function bbPayLink(url, btn) {
            btn.disabled = true;
            const original = btn.textContent;
            btn.textContent = 'Üretiliyor…';
            try {
                const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
                const data = await res.json();
                if (!data.ok) {
                    alert(data.message || 'Ödeme bağlantısı üretilemedi.');
                    return;
                }
                try { await navigator.clipboard.writeText(data.url); } catch (e) {}
                window.prompt('Ödeme bağlantısı (panoya kopyalandı):', data.url);
            } catch (e) {
                alert('Ödeme bağlantısı üretilemedi (ağ hatası).');
            } finally {
                btn.disabled = false;
                btn.textContent = original;
            }
        }
    </script>
@endsection
