<div style="width:280px;max-width:100%;margin:0 auto;border:8px solid #10233f;border-radius:34px;background:#10233f;overflow:hidden;box-shadow:var(--shadow)">
    <div style="border-radius:26px;overflow:hidden;background:#fff">
        <div style="background:var(--dark);color:#fff;padding:18px 16px"><b style="font-size:15px">Demo Restoran</b><br><span style="font-size:12px;color:#9db8b5">Masa 12 · Hoş geldiniz</span></div>
        <div style="display:flex;gap:6px;padding:12px;overflow:hidden">
            <i style="font-style:normal;font-size:11.5px;font-weight:600;padding:6px 11px;border-radius:999px;background:var(--teal-50);color:var(--teal-700);border:1px solid var(--teal-100)">Kahveler</i>
            <i style="font-style:normal;font-size:11.5px;font-weight:600;padding:6px 11px;border-radius:999px;background:var(--bg-2);color:var(--muted)">Soğuk</i>
            <i style="font-style:normal;font-size:11.5px;font-weight:600;padding:6px 11px;border-radius:999px;background:var(--bg-2);color:var(--muted)">Tatlılar</i>
            <i style="font-style:normal;font-size:11.5px;font-weight:600;padding:6px 11px;border-radius:999px;background:var(--bg-2);color:var(--muted)">Nargile</i>
        </div>
        @foreach([['Filtre Kahve','Günün çekirdeği','₺75'],['Latte','Sıcak · orta','₺90'],['Cheesecake','Frambuazlı','₺140']] as $p)
            <div style="display:flex;gap:12px;padding:9px 14px;align-items:center;border-top:1px solid var(--line-2)">
                <div style="width:42px;height:42px;border-radius:9px;background:var(--bg-2);flex:none"></div>
                <div><div style="font-size:13.5px;font-weight:650">{{ $p[0] }}</div><div style="font-size:11px;color:var(--muted)">{{ $p[1] }}</div></div>
                <div style="margin-left:auto;font-weight:700;color:var(--ink);font-size:13.5px">{{ $p[2] }}</div>
            </div>
        @endforeach
        <div style="margin:12px 14px 16px;height:46px;border-radius:11px;background:var(--teal);color:#fff;display:flex;align-items:center;justify-content:center;gap:8px;font-weight:650;font-size:14px">Sepete Ekle · 3 ürün · ₺305</div>
    </div>
</div>
