@extends('yonetim.layout')
@section('title', 'Demo Talepleri')
@section('sub', ($counts['new'] ?? 0) . ' yeni · ' . $rows->count() . ' gösteriliyor')

@php
    $demoB = fn ($s) => ['new' => 'b-indigo', 'contacted' => 'b-amber', 'won' => 'b-green', 'lost' => 'b-rose'][$s] ?? 'b-slate';
    $demoT = fn ($s) => ['new' => 'Yeni', 'contacted' => 'Görüşüldü', 'won' => 'Kazanıldı', 'lost' => 'Kaybedildi'][$s] ?? $s;
    $tabs = ['' => 'Tümü', 'new' => 'Yeni', 'contacted' => 'Görüşüldü', 'won' => 'Kazanıldı', 'lost' => 'Kaybedildi'];
@endphp

@section('content')
    <div class="filters">
        @foreach($tabs as $k => $v)
            <a href="{{ route('superadmin.demos', array_filter(['status' => $k])) }}"
               class="btn {{ $status === $k ? 'btn-p' : '' }}">
                {{ $v }}@if($k !== '' && ($counts[$k] ?? 0) > 0) · {{ $counts[$k] }}@endif
            </a>
        @endforeach
    </div>

    <div class="card">
        <table>
            <thead><tr><th>İletişim</th><th>İşletme / Sektör</th><th>Mesaj</th><th>Tarih</th><th>Durum</th><th></th></tr></thead>
            <tbody>
            @forelse($rows as $d)
                <tr>
                    <td>
                        <b>{{ $d->name }}</b>
                        <div style="font-size:12.5px;color:var(--muted)"><a href="tel:{{ preg_replace('/[^+\d]/','',$d->phone) }}" style="color:#a5b4fc">{{ $d->phone }}</a>@if($d->email) · {{ $d->email }}@endif</div>
                    </td>
                    <td>{{ $d->business ?: '—' }}<div style="font-size:12px;color:var(--soft)">{{ $d->sector ?: '' }}</div></td>
                    <td style="max-width:280px;color:var(--muted);font-size:13px">{{ \Illuminate\Support\Str::limit($d->message, 90) ?: '—' }}</td>
                    <td class="num" style="font-size:13px;color:var(--muted)">{{ $d->created_at->format('d.m.Y H:i') }}</td>
                    <td><span class="b {{ $demoB($d->status) }}">{{ $demoT($d->status) }}</span></td>
                    <td style="text-align:right">
                        <form method="post" action="{{ route('superadmin.demos.update', $d->id) }}" style="display:inline-flex;gap:6px">
                            @csrf @method('PUT')
                            <select name="status" onchange="this.form.submit()" class="btn-sm" style="height:32px">
                                <option value="new" @selected($d->status==='new')>Yeni</option>
                                <option value="contacted" @selected($d->status==='contacted')>Görüşüldü</option>
                                <option value="won" @selected($d->status==='won')>Kazanıldı</option>
                                <option value="lost" @selected($d->status==='lost')>Kaybedildi</option>
                            </select>
                        </form>
                    </td>
                </tr>
            @empty
                <tr><td colspan="6" class="empty">Bu filtrede talep yok.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
@endsection
