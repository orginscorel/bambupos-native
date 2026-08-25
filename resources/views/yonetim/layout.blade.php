<!doctype html>
<html lang="tr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title', 'Yönetim') · BamBumPOS SaaS</title>
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🛠️</text></svg>">
    <style>
        :root{--bg:#0b1020;--bg2:#0f152b;--card:#141c38;--line:#243055;--ink:#eef2fb;--muted:#93a3c4;--soft:#6b7ba0;
            --brand:#6366f1;--brand2:#8b5cf6;--ok:#22c55e;--warn:#f59e0b;--rose:#fb7185;--cyan:#22d3ee;--radius:14px}
        *{box-sizing:border-box}html,body{margin:0}
        body{background:var(--bg);color:var(--ink);font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;-webkit-font-smoothing:antialiased}
        a{color:inherit;text-decoration:none}
        .app{display:grid;grid-template-columns:248px 1fr;min-height:100vh}
        aside{background:var(--bg2);border-right:1px solid var(--line);padding:16px 12px;position:sticky;top:0;height:100vh;overflow:auto}
        .brand{display:flex;align-items:center;gap:10px;padding:8px 10px 16px;font-weight:800;font-size:17px}
        .brand .m{width:32px;height:32px;border-radius:9px;background:linear-gradient(135deg,var(--brand),var(--brand2));display:grid;place-items:center;font-size:16px}
        .brand small{display:block;color:var(--soft);font-size:10.5px;font-weight:600;letter-spacing:.05em}
        nav a{display:flex;align-items:center;gap:11px;padding:10px 12px;border-radius:11px;color:var(--muted);font-weight:600;font-size:14.5px;margin-bottom:2px}
        nav a:hover{background:rgba(255,255,255,.05);color:var(--ink)}
        nav a.active{background:linear-gradient(135deg,rgba(99,102,241,.22),rgba(139,92,246,.18));color:#fff}
        nav a .ic{width:19px;text-align:center}
        nav a .badge{margin-left:auto;background:var(--rose);color:#fff;font-size:11px;font-weight:800;border-radius:999px;padding:1px 7px}
        aside .foot{margin-top:14px;border-top:1px solid var(--line);padding-top:12px}
        aside .foot a{font-size:13px;color:var(--soft);padding:7px 12px;display:block;border-radius:9px}
        aside .foot a:hover{color:var(--ink);background:rgba(255,255,255,.04)}
        main{padding:26px 30px;max-width:1240px}
        .topbar{display:flex;align-items:center;justify-content:space-between;gap:14px;margin-bottom:22px}
        .topbar h1{margin:0;font-size:22px;font-weight:800}
        .topbar .sub{color:var(--muted);font-size:13.5px;margin-top:3px}
        .who{display:flex;align-items:center;gap:9px;font-size:13.5px;color:var(--muted)}
        .who .av{width:34px;height:34px;border-radius:10px;background:linear-gradient(135deg,var(--brand),var(--brand2));display:grid;place-items:center;font-weight:800;color:#fff}
        .flash{background:rgba(34,197,94,.12);border:1px solid rgba(34,197,94,.35);color:#86efac;border-radius:12px;padding:11px 15px;margin-bottom:18px;font-weight:600;font-size:14px}
        .card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius)}
        .card.p{padding:18px}
        .kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:20px}
        .kpi{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:16px}
        .kpi .l{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.06em;color:var(--soft)}
        .kpi .v{font-size:26px;font-weight:800;margin-top:6px;letter-spacing:-.02em}
        .kpi .s{font-size:12.5px;color:var(--muted);margin-top:3px}
        .kpi .v.g{color:#4ade80}.kpi .v.b{color:#818cf8}.kpi .v.c{color:#22d3ee}.kpi .v.w{color:#fbbf24}
        .grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
        .sec-t{font-size:15px;font-weight:800;padding:14px 16px;border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between}
        table{width:100%;border-collapse:collapse;font-size:14px}
        th{text-align:left;color:var(--soft);font-size:11.5px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;padding:11px 14px;border-bottom:1px solid var(--line)}
        td{padding:12px 14px;border-bottom:1px solid var(--line)}
        tr:last-child td{border-bottom:0}
        tr:hover td{background:rgba(255,255,255,.02)}
        .b{display:inline-flex;align-items:center;gap:6px;padding:3px 9px;border-radius:999px;font-size:12px;font-weight:700}
        .b-green{background:rgba(34,197,94,.15);color:#4ade80}.b-amber{background:rgba(245,158,11,.15);color:#fbbf24}
        .b-rose{background:rgba(251,113,133,.15);color:#fb7185}.b-slate{background:rgba(148,163,184,.12);color:#94a3c4}
        .b-indigo{background:rgba(99,102,241,.18);color:#a5b4fc}.b-cyan{background:rgba(34,211,238,.15);color:#67e8f9}
        .num{font-variant-numeric:tabular-nums}
        .btn{display:inline-flex;align-items:center;gap:7px;height:38px;padding:0 15px;border-radius:10px;border:1px solid var(--line);background:var(--bg2);color:var(--ink);font:inherit;font-size:13.5px;font-weight:700;cursor:pointer}
        .btn:hover{border-color:var(--brand)}
        .btn-p{background:linear-gradient(135deg,var(--brand),var(--brand2));border:0;color:#fff}
        .btn-sm{height:32px;padding:0 11px;font-size:12.5px}
        input,select{height:38px;border:1px solid var(--line);border-radius:10px;background:var(--bg);color:var(--ink);padding:0 11px;font:inherit;font-size:14px}
        input:focus,select:focus{outline:2px solid var(--brand);outline-offset:1px}
        .bar{display:flex;align-items:flex-end;gap:5px;height:120px}
        .bar .col{flex:1;background:linear-gradient(180deg,var(--brand),var(--brand2));border-radius:5px 5px 0 0;min-height:2px;position:relative}
        .bar .col span{position:absolute;bottom:-20px;left:0;right:0;text-align:center;font-size:10px;color:var(--soft)}
        .filters{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px}
        dialog{border:1px solid var(--line);background:var(--card);color:var(--ink);border-radius:16px;padding:0;max-width:440px;width:92vw}
        dialog::backdrop{background:rgba(2,6,20,.6)}
        dialog .dh{padding:16px 18px;border-bottom:1px solid var(--line);font-weight:800}
        dialog form{padding:18px}
        dialog .field{margin-bottom:12px}
        dialog label{display:block;font-size:12px;font-weight:700;color:var(--muted);margin-bottom:5px}
        dialog input,dialog select{width:100%}
        dialog .df{display:flex;justify-content:flex-end;gap:10px;margin-top:6px}
        .empty{text-align:center;color:var(--soft);padding:40px 20px}
        @media(max-width:860px){.app{grid-template-columns:1fr}aside{position:static;height:auto}.kpis{grid-template-columns:1fr 1fr}.grid2{grid-template-columns:1fr}main{padding:18px}}
    </style>
</head>
<body>
<div class="app">
    <aside>
        <div class="brand"><span class="m">🛠️</span> <div>BamBumPOS <small>SaaS Yönetim</small></div></div>
        <nav>
            <a href="{{ route('superadmin.dashboard') }}" class="{{ request()->routeIs('superadmin.dashboard') ? 'active' : '' }}"><span class="ic">📊</span> Genel Bakış</a>
            <a href="{{ route('superadmin.tenants') }}" class="{{ request()->routeIs('superadmin.tenants') ? 'active' : '' }}"><span class="ic">🏢</span> İşletmeler</a>
            <a href="{{ route('superadmin.demos') }}" class="{{ request()->routeIs('superadmin.demos') ? 'active' : '' }}"><span class="ic">📨</span> Demo Talepleri @if(($pendingDemos ?? 0) > 0)<span class="badge">{{ $pendingDemos }}</span>@endif</a>
            <a href="{{ route('superadmin.billing') }}" class="{{ request()->routeIs('superadmin.billing') ? 'active' : '' }}"><span class="ic">💳</span> Faturalama</a>
        </nav>
        <div class="foot">
            <a href="/panel">← Uygulama paneli</a>
            <a href="/">← Tanıtım sitesi</a>
        </div>
    </aside>
    <main>
        <div class="topbar">
            <div>
                <h1>@yield('title')</h1>
                <div class="sub">@yield('sub')</div>
            </div>
            <div class="who">
                <span>{{ auth()->user()?->name }}</span>
                <span class="av">{{ mb_strtoupper(mb_substr(auth()->user()?->name ?? 'B', 0, 1)) }}</span>
            </div>
        </div>
        @if(session('ok'))<div class="flash">✓ {{ session('ok') }}</div>@endif
        @yield('content')
    </main>
</div>
@yield('scripts')
</body>
</html>
