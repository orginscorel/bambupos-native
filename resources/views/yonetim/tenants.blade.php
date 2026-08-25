@extends('yonetim.layout')
@section('title', 'İşletmeler')
@section('sub', $rows->count() . ' işletme')

@php
    $fmt = fn ($m) => number_format(((int) ($m ?? 0)) / 100, 2, ',', '.') . ' ₺';
    $statusB = fn ($s) => ['active' => 'b-green', 'suspended' => 'b-rose', 'trial' => 'b-amber'][$s] ?? 'b-slate';
    $statusT = fn ($s) => ['active' => 'Aktif', 'suspended' => 'Askıda', 'trial' => 'Deneme'][$s] ?? $s;
    $planLabel = fn ($p) => $plans[$p] ?? ($p ?: '—');
@endphp

@section('content')
    @if($p = session('provisioned'))
        <div class="card" style="border-color:#16a34a;background:rgba(22,163,74,.06);margin-bottom:16px">
            <div style="font-weight:700;color:#16a34a;margin-bottom:6px">✓ {{ $p['name'] }} oluşturuldu — sahip giriş bilgileri (bu ekran bir kez görünür)</div>
            <div style="display:flex;flex-wrap:wrap;gap:20px;font-size:14px">
                <span>İşletme: <b>{{ $p['name'] }}</b> <span style="color:var(--soft)">/{{ $p['slug'] }}</span></span>
                <span>Sahip e-posta: <b>{{ $p['email'] }}</b></span>
                <span>Geçici parola: <code style="background:var(--bg-2,#0002);padding:2px 8px;border-radius:6px;font-weight:700">{{ $p['password'] }}</code></span>
            </div>
            <div style="font-size:12.5px;color:var(--muted);margin-top:8px">Sahibe iletin; ilk girişte değiştirebilir. Parola hiçbir yerde saklanmaz.</div>
        </div>
    @endif

    <div style="display:flex;flex-wrap:wrap;gap:12px;align-items:center;justify-content:space-between;margin-bottom:14px">
        <form method="get" class="filters" style="margin:0">
            <input type="text" name="q" value="{{ $q }}" placeholder="İşletme adı / slug ara…" style="min-width:240px">
            <select name="status" onchange="this.form.submit()">
                <option value="">Tüm durumlar</option>
                <option value="active" @selected($status==='active')>Aktif</option>
                <option value="trial" @selected($status==='trial')>Deneme</option>
                <option value="suspended" @selected($status==='suspended')>Askıda</option>
            </select>
            <button class="btn">Ara</button>
        </form>
        <button class="btn btn-p" onclick="document.getElementById('newDlg').showModal()">+ Yeni POS mağazası aç</button>
    </div>

    <div class="card">
        <table>
            <thead><tr><th>İşletme</th><th>Durum</th><th>Plan</th><th>Personel</th><th style="text-align:right">Bu ay ciro</th><th>Abonelik</th><th>Oluşturma</th><th></th></tr></thead>
            <tbody>
            @forelse($rows as $t)
                <tr>
                    <td>
                        <b>{{ $t->name }}</b>
                        <div style="font-size:12px;color:var(--soft)">{{ $t->slug }}{{ $t->domain ? ' · '.$t->domain : '' }}</div>
                    </td>
                    <td><span class="b {{ $statusB($t->status) }}">{{ $statusT($t->status) }}</span></td>
                    <td><span class="b b-indigo">{{ $planLabel($t->plan) }}</span></td>
                    <td class="num">{{ (int) ($userCounts[$t->id] ?? 0) }}</td>
                    <td style="text-align:right" class="num">{{ $fmt($revMonth[$t->id] ?? 0) }}</td>
                    <td class="num" style="font-size:13px;color:var(--muted)">{{ $t->subscribed_until ? \Illuminate\Support\Carbon::parse($t->subscribed_until)->format('d.m.Y') : '—' }}</td>
                    <td class="num" style="font-size:13px;color:var(--muted)">{{ \Illuminate\Support\Carbon::parse($t->created_at)->format('d.m.Y') }}</td>
                    <td style="text-align:right">
                        @php($edit = json_encode([
                            'id' => $t->id, 'name' => $t->name, 'status' => $t->status, 'plan' => $t->plan,
                            'subscribed_until' => $t->subscribed_until ? \Illuminate\Support\Carbon::parse($t->subscribed_until)->format('Y-m-d') : '',
                            'billing_note' => $t->billing_note,
                        ], JSON_UNESCAPED_UNICODE))
                        <div style="display:inline-flex;gap:6px;align-items:center">
                            @if($t->status === 'suspended')
                                <form method="post" action="{{ route('superadmin.tenants.status', $t->id) }}" onsubmit="return confirm('{{ $t->name }} yeniden açılsın mı?')" style="display:inline">
                                    @csrf<input type="hidden" name="action" value="activate">
                                    <button class="btn btn-sm" style="color:#16a34a">Yeniden aç</button>
                                </form>
                            @else
                                <form method="post" action="{{ route('superadmin.tenants.status', $t->id) }}" onsubmit="return confirm('{{ $t->name }} askıya alınsın mı? Panel erişimi durur, veri korunur.')" style="display:inline">
                                    @csrf<input type="hidden" name="action" value="suspend">
                                    <button class="btn btn-sm" style="color:#e11d48">Askıya al</button>
                                </form>
                            @endif
                            <button class="btn btn-sm" data-edit="{{ $edit }}" onclick="openEdit(JSON.parse(this.dataset.edit))">Düzenle</button>
                        </div>
                    </td>
                </tr>
            @empty
                <tr><td colspan="8" class="empty">Kayıt bulunamadı.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>

    <dialog id="newDlg">
        <div class="dh">Yeni POS mağazası aç</div>
        <form method="post" action="{{ route('superadmin.tenants.store') }}">
            @csrf
            <div class="field"><label>İşletme adı *</label><input type="text" name="name" required maxlength="120" placeholder="ör. Köşe Kafe"></div>
            <div class="field"><label>Sahip adı soyadı</label><input type="text" name="owner_name" maxlength="120" placeholder="ör. Ahmet Yılmaz"></div>
            <div class="field"><label>Sahip e-posta * <span style="color:var(--soft);font-weight:400">(giriş için)</span></label><input type="email" name="owner_email" required maxlength="190" placeholder="sahip@ornek.com"></div>
            <div class="field"><label>Plan</label>
                <select name="plan">
                    <option value="trial">Deneme</option>
                    @foreach($plans as $k => $v)@if($k!=='trial')<option value="{{ $k }}">{{ $v }}</option>@endif @endforeach
                </select>
            </div>
            <div class="field"><label>Deneme süresi (gün)</label><input type="number" name="trial_days" value="14" min="0" max="365"></div>
            <div style="font-size:12.5px;color:var(--muted);margin:2px 0 4px">Merkez şube, roller ve sahip kullanıcı otomatik oluşur. Sahip parolası bir kez gösterilir.</div>
            <div class="df">
                <button type="button" class="btn" onclick="document.getElementById('newDlg').close()">Vazgeç</button>
                <button type="submit" class="btn btn-p">Mağazayı oluştur</button>
            </div>
        </form>
    </dialog>

    <dialog id="editDlg">
        <div class="dh">İşletme düzenle — <span id="edName"></span></div>
        <form id="editForm" method="post">
            @csrf
            @method('PUT')
            <div class="field"><label>Durum</label>
                <select name="status" id="edStatus">
                    <option value="active">Aktif</option>
                    <option value="trial">Deneme</option>
                    <option value="suspended">Askıda</option>
                </select>
            </div>
            <div class="field"><label>Plan</label>
                <select name="plan" id="edPlan">
                    <option value="">— Belirsiz —</option>
                    @foreach($plans as $k => $v)<option value="{{ $k }}">{{ $v }}</option>@endforeach
                </select>
            </div>
            <div class="field"><label>Abonelik bitiş (opsiyonel)</label><input type="date" name="subscribed_until" id="edSub"></div>
            <div class="field"><label>Fatura notu (opsiyonel)</label><input type="text" name="billing_note" id="edNote" maxlength="255" placeholder="ör. yıllık ödeme, indirimli…"></div>
            <div class="df">
                <button type="button" class="btn" onclick="document.getElementById('editDlg').close()">Vazgeç</button>
                <button type="submit" class="btn btn-p">Kaydet</button>
            </div>
        </form>
    </dialog>
@endsection

@section('scripts')
<script>
    function openEdit(t){
        var dlg = document.getElementById('editDlg');
        document.getElementById('edName').textContent = t.name;
        document.getElementById('editForm').action = '/yonetim/isletmeler/' + t.id;
        document.getElementById('edStatus').value = t.status || 'active';
        document.getElementById('edPlan').value = t.plan || '';
        document.getElementById('edSub').value = t.subscribed_until || '';
        document.getElementById('edNote').value = t.billing_note || '';
        dlg.showModal();
    }
</script>
@endsection
