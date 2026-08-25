@extends('yonetim.layout')
@section('title', 'Genel Bakış')
@section('sub', 'BamBumPOS SaaS — tüm işletmelerin özeti')

@php
    $fmt = fn ($m) => number_format(((int) $m) / 100, 2, ',', '.') . ' ₺';
    $maxTrend = max(1, collect($trend)->max('value'));
    $planLabel = fn ($p) => $plans[$p] ?? ($p ?: '—');
    $statusB = fn ($s) => ['active' => 'b-green', 'suspended' => 'b-rose', 'trial' => 'b-amber'][$s] ?? 'b-slate';
    $statusT = fn ($s) => ['active' => 'Aktif', 'suspended' => 'Askıda', 'trial' => 'Deneme'][$s] ?? $s;
    $demoB = fn ($s) => ['new' => 'b-indigo', 'contacted' => 'b-amber', 'won' => 'b-green', 'lost' => 'b-rose'][$s] ?? 'b-slate';
    $demoT = fn ($s) => ['new' => 'Yeni', 'contacted' => 'Görüşüldü', 'won' => 'Kazanıldı', 'lost' => 'Kaybedildi'][$s] ?? $s;
@endphp

@section('content')
    <div class="kpis">
        <div class="kpi"><div class="l">Toplam İşletme</div><div class="v b">{{ $tenants }}</div><div class="s">{{ $active }} aktif · {{ $newThisMonth }} bu ay yeni</div></div>
        <div class="kpi"><div class="l">Bu Ay Ciro (tüm)</div><div class="v g">{{ $fmt($revMonth) }}</div><div class="s">Bugün {{ $fmt($revToday) }}</div></div>
        <div class="kpi"><div class="l">Toplam Ciro</div><div class="v c">{{ $fmt($revAll) }}</div><div class="s">{{ number_format($orders) }} sipariş</div></div>
        <div class="kpi"><div class="l">Bekleyen Demo</div><div class="v w">{{ $pendingDemos }}</div><div class="s">{{ $users }} kayıtlı personel</div></div>
    </div>

    <div class="grid2" style="margin-bottom:16px">
        <div class="card">
            <div class="sec-t">Ciro trendi · son 14 gün</div>
            <div class="p">
                <div class="bar">
                    @foreach($trend as $t)
                        <div class="col" style="height:{{ max(2, round($t['value'] / $maxTrend * 116)) }}px" title="{{ $t['label'] }}: {{ $fmt($t['value']) }}">
                            @if($loop->index % 2 === 0)<span>{{ $t['label'] }}</span>@endif
                        </div>
                    @endforeach
                </div>
                <div style="margin-top:26px;color:var(--muted);font-size:12.5px">Tüm işletmelerin toplam günlük tahsilatı.</div>
            </div>
        </div>
        <div class="card">
            <div class="sec-t">Bu ay en çok ciro · işletme</div>
            <table>
                <tbody>
                @php($top = $revByTenant->sortDesc()->take(6))
                @forelse($top as $tid => $m)
                    @php($t = $recentTenants->firstWhere('id', $tid))
                    <tr>
                        <td>{{ optional(\Illuminate\Support\Facades\DB::table('tenants')->where('id',$tid)->first())->name ?? ('#'.$tid) }}</td>
                        <td style="text-align:right" class="num"><b>{{ $fmt($m) }}</b></td>
                    </tr>
                @empty
                    <tr><td class="empty">Bu ay tahsilat yok.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <div class="grid2">
        <div class="card">
            <div class="sec-t">Son işletmeler <a href="{{ route('superadmin.tenants') }}" style="font-size:12.5px;color:#a5b4fc;font-weight:700">Tümü →</a></div>
            <table>
                <thead><tr><th>İşletme</th><th>Durum</th><th>Plan</th></tr></thead>
                <tbody>
                @forelse($recentTenants as $t)
                    <tr>
                        <td><b>{{ $t->name }}</b><div style="font-size:12px;color:var(--soft)">{{ $t->slug }}</div></td>
                        <td><span class="b {{ $statusB($t->status) }}">{{ $statusT($t->status) }}</span></td>
                        <td><span class="b b-slate">{{ $planLabel($t->plan) }}</span></td>
                    </tr>
                @empty
                    <tr><td colspan="3" class="empty">Henüz işletme yok.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
        <div class="card">
            <div class="sec-t">Son demo talepleri <a href="{{ route('superadmin.demos') }}" style="font-size:12.5px;color:#a5b4fc;font-weight:700">Tümü →</a></div>
            <table>
                <thead><tr><th>İsim / İşletme</th><th>Telefon</th><th>Durum</th></tr></thead>
                <tbody>
                @forelse($recentDemos as $d)
                    <tr>
                        <td><b>{{ $d->name }}</b><div style="font-size:12px;color:var(--soft)">{{ $d->business ?: '—' }}{{ $d->sector ? ' · '.$d->sector : '' }}</div></td>
                        <td class="num">{{ $d->phone }}</td>
                        <td><span class="b {{ $demoB($d->status) }}">{{ $demoT($d->status) }}</span></td>
                    </tr>
                @empty
                    <tr><td colspan="3" class="empty">Henüz demo talebi yok.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
    </div>
@endsection
