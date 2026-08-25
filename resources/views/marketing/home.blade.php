@extends('marketing.layout')

@section('title', 'BamBumPOS — Restoran & Kafe için Hepsi Bir Arada POS ve İşletme Yönetim Sistemi')
@section('description', 'Siparişten mutfağa, kasadan stoğa, personelden raporlamaya kadar tüm işletmenizi tek platformdan yönetin. Bulut tabanlı POS, QR menü, adisyon ve işletme yönetim sistemi. 14 gün ücretsiz deneyin.')

@php
    $ic = \App\Modules\Marketing\Support\Icons::all();
    $tick = '<span class="ck">'.$ic['check'].'</span>';
@endphp

@push('head')
<style>
    /* =========================================================
       Ana sayfa — premium cila (v3)
       ========================================================= */
    /* HERO */
    .hero { background:
        radial-gradient(900px 460px at 88% -8%, rgba(37,99,235,.10), transparent 60%),
        linear-gradient(180deg, #f6f8fb 0%, #fff 70%);
        border-bottom: 1px solid var(--line); padding: 40px 0 64px; }
    .hero-grid { display: grid; grid-template-columns: 1fr 1.06fr; gap: 56px; align-items: center; }
    .hero h1 { font-size: clamp(32px, 4.7vw, 54px); font-weight: 800; line-height: 1.07; letter-spacing: -.035em; margin: 20px 0 0; color: var(--ink); }
    .hero h1 .ac { color: var(--teal); }
    .hero .sub { font-size: clamp(16px, 1.6vw, 18.5px); color: var(--muted); margin: 18px 0 0; max-width: 500px; line-height: 1.6; }
    .hero-cta { display: flex; gap: 12px; margin-top: 26px; flex-wrap: wrap; }
    .hero-note { margin-top: 18px; display: flex; gap: 18px; flex-wrap: wrap; font-size: 13.5px; color: var(--muted); }
    .hero-note span { display: inline-flex; align-items: center; gap: 7px; }
    .hero-note .ck { width: 17px; height: 17px; color: var(--teal); }
    /* Hero ürün görseli — tilt yok, üst hizalı, yüzen mini kart */
    .hero-vis { position: relative; }
    .hero-vis::before { content: ""; position: absolute; z-index: 0; inset: -12% -9% -16% -9%; background: radial-gradient(56% 52% at 62% 42%, rgba(37,99,235,.18), rgba(37,99,235,.05) 45%, transparent 72%); pointer-events: none; }
    .hero-vis .shot { position: relative; z-index: 2; }
    .hero-vis .float { position: absolute; z-index: 3; background: rgba(255,255,255,.92); backdrop-filter: saturate(160%) blur(8px); border: 1px solid rgba(15,23,42,.07); border-radius: 16px; box-shadow: 0 20px 44px -18px rgba(15,23,42,.32); padding: 12px 15px; display: flex; align-items: center; gap: 11px; }
    .hero-vis .float .fi { width: 36px; height: 36px; border-radius: 9px; display: grid; place-items: center; flex: none; }
    .hero-vis .float .ft { font-size: 12.5px; font-weight: 700; color: var(--ink); line-height: 1.2; }
    .hero-vis .float .fd { font-size: 11.5px; color: var(--muted); }
    .hero-vis .f-a { top: -18px; left: -22px; animation: fl-a 4.6s ease-in-out infinite; }
    .hero-vis .f-b { bottom: -20px; right: 8px; animation: fl-b 5.4s ease-in-out infinite; }
    .hero-vis .shot { animation: fl-shot 6.5s ease-in-out infinite; }
    @keyframes fl-a { 0%,100%{ transform: translateY(0) } 50%{ transform: translateY(-10px) } }
    @keyframes fl-b { 0%,100%{ transform: translateY(0) } 50%{ transform: translateY(8px) } }
    @keyframes fl-shot { 0%,100%{ transform: translateY(0) } 50%{ transform: translateY(-6px) } }
    @media (prefers-reduced-motion: reduce) { .hero-vis .f-a, .hero-vis .f-b, .hero-vis .shot { animation: none; } }
    .hero-metrics { display: flex; gap: 26px; flex-wrap: wrap; margin-top: 30px; padding-top: 24px; border-top: 1px solid var(--line); }
    .hm { display: flex; align-items: center; gap: 11px; }
    .hm .si { width: 40px; height: 40px; border-radius: 10px; background: var(--teal-50); border: 1px solid var(--teal-100); color: var(--teal-700); display: grid; place-items: center; flex: none; }
    .hm .si svg { width: 19px; height: 19px; }
    .hm b { display: block; font-size: 14.5px; font-weight: 700; color: var(--ink); line-height: 1.2; }
    .hm span { display: block; font-size: 12.5px; color: var(--muted); margin-top: 2px; }

    /* SEKTÖR kartları — zengin */
    .sectors { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; }
    .scard { position: relative; display: block; aspect-ratio: 4/5; border-radius: var(--radius-xl); overflow: hidden; box-shadow: var(--shadow-sm); transition: transform .3s var(--ease), box-shadow .3s; isolation: isolate; }
    .scard-img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; z-index: 0; transition: transform .55s var(--ease); }
    .scard::after { content: ""; position: absolute; inset: 0; z-index: 1; background: linear-gradient(180deg, rgba(15,23,42,0) 28%, rgba(15,23,42,.5) 60%, rgba(15,23,42,.92) 100%); transition: background .3s; }
    .scard:hover { transform: translateY(-5px); box-shadow: var(--shadow); }
    .scard:hover .scard-img { transform: scale(1.06); }
    .scard:hover::after { background: linear-gradient(180deg, rgba(15,23,42,.08) 18%, rgba(15,23,42,.58) 54%, rgba(15,23,42,.95) 100%); }
    .scard-ic { position: absolute; top: 15px; left: 15px; z-index: 2; width: 44px; height: 44px; border-radius: 12px; background: rgba(255,255,255,.94); backdrop-filter: blur(6px); display: grid; place-items: center; color: var(--teal-700); box-shadow: 0 6px 18px rgba(15,23,42,.28); }
    .scard-ic svg { width: 22px; height: 22px; }
    .scard-body { position: absolute; left: 0; right: 0; bottom: 0; z-index: 2; padding: 20px 20px 22px; color: #fff; }
    .scard-body h3 { font-size: 20px; font-weight: 800; letter-spacing: -.02em; margin: 0; line-height: 1.15; }
    .scard-body p { font-size: 12.8px; color: rgba(255,255,255,.85); margin: 6px 0 0; line-height: 1.45; }
    .scard-l { display: inline-flex; align-items: center; gap: 6px; margin-top: 13px; font-size: 12.5px; font-weight: 700; color: #fff; opacity: .92; transition: gap .16s, opacity .16s; }
    .scard:hover .scard-l { gap: 9px; opacity: 1; }
    .scard-l svg { width: 15px; height: 15px; }
    @media (max-width: 1024px) { .sectors { grid-template-columns: repeat(2, 1fr); } }

    /* OPERASYON AKIŞI — solda görsel, sağda dikey adımlar */
    .flowsplit { display: grid; grid-template-columns: 1fr 1.05fr; gap: 52px; align-items: center; }
    .steps { display: grid; gap: 6px; }
    .stp { display: grid; grid-template-columns: auto 1fr; gap: 16px; padding: 14px 0; position: relative; }
    .stp:not(:last-child)::before { content: ""; position: absolute; left: 17px; top: 44px; bottom: -6px; width: 2px; background: var(--line); }
    .stp .n { width: 36px; height: 36px; border-radius: 50%; background: var(--teal); color: #fff; display: grid; place-items: center; font-weight: 700; font-size: 15px; flex: none; box-shadow: 0 0 0 5px var(--teal-50); z-index: 1; }
    .stp h4 { margin: 6px 0 4px; font-size: 16px; font-weight: 700; }
    .stp p { margin: 0; font-size: 14px; color: var(--muted); line-height: 1.55; }

    /* EKOSİSTEM — premium, ikon başlıklı büyük kartlar */
    .eco3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
    .ec { border: 1px solid var(--line); border-radius: 18px; background: #fff; padding: 24px; transition: border-color .18s, box-shadow .25s, transform .2s var(--ease); }
    .ec:hover { border-color: var(--teal-100); box-shadow: var(--shadow); transform: translateY(-3px); }
    .ec .ec-h { display: flex; align-items: center; gap: 13px; margin-bottom: 16px; }
    .ec .ec-ic { width: 46px; height: 46px; border-radius: 12px; background: var(--teal-50); border: 1px solid var(--teal-100); color: var(--teal); display: grid; place-items: center; flex: none; }
    .ec .ec-ic svg { width: 23px; height: 23px; }
    .ec .ec-h b { font-size: 12px; color: var(--soft); font-weight: 700; text-transform: uppercase; letter-spacing: .06em; display: block; }
    .ec .ec-h h3 { font-size: 18px; font-weight: 800; margin: 1px 0 0; letter-spacing: -.02em; }
    .ec ul { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 9px 14px; }
    .ec li { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--ink-2); }
    .ec li .d { width: 15px; height: 15px; border-radius: 4px; background: var(--teal-50); color: var(--teal-700); display: grid; place-items: center; flex: none; }
    .ec li .d svg { width: 10px; height: 10px; }
    /* Koyu ekosistem bölümü (KardoPOS ritmi: beyaz→açık→KOYU→gradient) */
    .eco-dark { background: linear-gradient(180deg, #0b1220 0%, #0f172a 46%, #0b1220 100%); position: relative; overflow: hidden; }
    .eco-dark::before { content: ""; position: absolute; top: -34%; left: 50%; width: 980px; height: 620px; transform: translateX(-50%); background: radial-gradient(closest-side, rgba(37,99,235,.20), transparent 72%); pointer-events: none; }
    .eco-dark .wrap { position: relative; z-index: 1; }
    .eco-dark .sec-head h2 { color: #fff; }
    .eco-dark .sec-head p { color: #94a3b8; }
    .eco-dark .eyebrow { color: #93c5fd; background: rgba(37,99,235,.16); border-color: rgba(37,99,235,.34); }
    .eco-dark .ec { background: rgba(255,255,255,.04); border-color: rgba(255,255,255,.09); }
    .eco-dark .ec:hover { border-color: rgba(37,99,235,.55); box-shadow: 0 26px 54px -28px rgba(0,0,0,.7); transform: translateY(-4px); }
    .eco-dark .ec .ec-ic { background: rgba(37,99,235,.16); border-color: rgba(37,99,235,.34); color: #93c5fd; }
    .eco-dark .ec .ec-h b { color: #64748b; }
    .eco-dark .ec .ec-h h3 { color: #fff; }
    .eco-dark .ec li { color: #cbd5e1; }
    .eco-dark .ec li .d { background: rgba(37,99,235,.2); color: #93c5fd; }
    /* Tek Platform, Dört Akıllı Çözüm — telefon mockup'ları */
    .four { display: grid; grid-template-columns: repeat(4,1fr); gap: 24px; align-items: start; }
    .fsol { display:flex; flex-direction:column; align-items:center; text-align:center; }
    .tp-phone { width:100%; max-width:224px; aspect-ratio:224/460; border:9px solid #0b1220; border-radius:34px; background:#0b1220; box-shadow:0 30px 60px -26px rgba(15,23,42,.55); position:relative; overflow:hidden; transition:transform .3s var(--ease); }
    .fsol:hover .tp-phone { transform:translateY(-6px); }
    .tp-phone::before { content:""; position:absolute; top:0; left:50%; transform:translateX(-50%); width:80px; height:19px; background:#0b1220; border-radius:0 0 13px 13px; z-index:4; }
    /* Gerçek ekran görüntüsü — gif gibi yavaş dikey pan (kaydırma) */
    .tp-live { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; object-position:center 0%; border-radius:25px; display:block; animation: tpPan 18s ease-in-out infinite; }
    @keyframes tpPan { 0%,7%{ object-position:center 0%; } 50%,57%{ object-position:center 100%; } 93%,100%{ object-position:center 0%; } }
    @media (prefers-reduced-motion: reduce){ .tp-live{ animation:none; } }
    /* Clickthrough (gerçek demo temposu): ekranı GÖR → yavaşça aşağı kaydır →
       altta beklet → geri yukarı → DOKUN → 2. ekran açılır → o da gezilir.
       16s döngü, net duraklamalarla (kaydırma artık atlanmaz). */
    .tp-click .tp-fr { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; object-position:center top; border-radius:25px; display:block; }
    .tp-click .tp-fr:not(.tp-fr-b) { animation: tpScrollA 16s ease-in-out infinite; }
    .tp-click .tp-fr-b { opacity:0; animation: tpFrameB 16s ease-in-out infinite; }
    @keyframes tpScrollA {
        0%,8%   { object-position:center 0% }      /* 1. ekranı göster */
        22%     { object-position:center 100% }     /* yavaşça aşağı kaydır */
        30%     { object-position:center 100% }     /* altta beklet */
        42%     { object-position:center 0% }        /* geri en üste */
        47%,100%{ object-position:center 0% }        /* dokunuşu bekle */
    }
    @keyframes tpFrameB {
        0%,47%  { opacity:0; object-position:center 0% }
        50%     { opacity:1; object-position:center 0% }   /* dokunuş → 2. ekran açıldı */
        58%     { opacity:1; object-position:center 0% }   /* üstte beklet (gör) */
        72%     { opacity:1; object-position:center 100% }  /* aşağı kaydır */
        80%     { opacity:1; object-position:center 100% }  /* altta beklet */
        92%     { opacity:1; object-position:center 0% }    /* geri yukarı */
        96%     { opacity:1 } 99%,100%{ opacity:0 }         /* kapan → başa dön */
    }
    .tp-tap { position:absolute; z-index:5; bottom:16%; width:36px; height:36px; margin-left:-18px; border-radius:50%;
        background:rgba(37,99,235,.28); border:2px solid rgba(37,99,235,.8); opacity:0; pointer-events:none;
        box-shadow:0 0 0 4px rgba(37,99,235,.14); animation: tpTap 16s ease-in-out infinite; }
    @keyframes tpTap {
        0%,44%  { opacity:0; transform:scale(.4) }
        47%     { opacity:.95; transform:scale(1) }         /* parmak değdi */
        52%     { opacity:0; transform:scale(1.85) }        /* dalga yayıldı → ekran açıldı */
        100%    { opacity:0; transform:scale(.4) }
    }
    .tp-click.d1 .tp-fr:not(.tp-fr-b), .tp-click.d1 .tp-fr-b, .tp-click.d1 .tp-tap { animation-delay:-4s; }
    .tp-click.d2 .tp-fr:not(.tp-fr-b), .tp-click.d2 .tp-fr-b, .tp-click.d2 .tp-tap { animation-delay:-8s; }
    .tp-click.d3 .tp-fr:not(.tp-fr-b), .tp-click.d3 .tp-fr-b, .tp-click.d3 .tp-tap { animation-delay:-12s; }
    @media (prefers-reduced-motion: reduce){ .tp-click .tp-fr:not(.tp-fr-b),.tp-click .tp-fr-b{ animation:none } .tp-click .tp-fr-b{ opacity:0 } .tp-tap{ display:none } }
    .tp-scr { position:absolute; inset:0; border-radius:25px; overflow:hidden; background:#fff; display:flex; flex-direction:column; }
    .tp-top { background:var(--dark); color:#fff; padding:26px 14px 12px; }
    .tp-top.tp-top-lt { background:linear-gradient(135deg,var(--teal),#4f46e5); }
    .tp-top b { display:block; font-size:13px; font-weight:700; }
    .tp-top span { font-size:10.5px; color:rgba(255,255,255,.72); }
    .tp-chips { display:flex; gap:5px; padding:10px 12px 2px; }
    .tp-chips i { font-style:normal; font-size:10px; font-weight:600; padding:4px 9px; border-radius:999px; background:var(--bg-2); color:var(--muted); white-space:nowrap; }
    .tp-chips i.on { background:var(--teal-50); color:var(--teal-700); }
    .tp-body { flex:1; padding:8px 12px; overflow:hidden; }
    .tp-row { display:flex; align-items:center; gap:9px; padding:8px 2px; border-top:1px solid var(--line-2); }
    .tp-row:first-child { border-top:0; }
    .tp-th { width:32px; height:32px; border-radius:8px; background:linear-gradient(135deg,var(--teal-50),var(--bg-2)); flex:none; }
    .tp-av { width:30px; height:30px; border-radius:50%; background:var(--teal-50); color:var(--teal-700); font-weight:800; font-size:12px; display:grid; place-items:center; flex:none; }
    .tp-rt { flex:1; text-align:left; line-height:1.25; }
    .tp-rt b { display:block; font-size:12px; font-weight:650; color:var(--ink); }
    .tp-rt i { font-style:normal; font-size:10px; color:var(--muted); }
    .tp-pr { font-size:12px; font-weight:700; color:var(--ink); }
    .tp-badge { font-size:9.5px; font-weight:700; padding:3px 7px; border-radius:999px; white-space:nowrap; }
    .tp-kpis { display:grid; grid-template-columns:1fr 1fr 1fr; gap:6px; margin:4px 0 12px; }
    .tp-kpi { border:1px solid var(--line-2); border-radius:9px; padding:8px 6px; text-align:left; }
    .tp-kpi i { font-style:normal; font-size:8px; font-weight:700; color:var(--soft); text-transform:uppercase; letter-spacing:.02em; display:block; }
    .tp-kpi b { font-size:12px; font-weight:800; letter-spacing:-.02em; }
    .tp-chart { display:flex; align-items:flex-end; gap:5px; height:60px; padding:6px 2px 0; }
    .tp-chart span { flex:1; background:linear-gradient(180deg,var(--teal),#6366f1); border-radius:3px 3px 0 0; }
    .tp-cta { margin:0 12px 14px; height:38px; border-radius:10px; background:var(--teal); color:#fff; display:flex; align-items:center; justify-content:center; font-weight:650; font-size:12px; }
    .tp-cta.tp-cta-soft { background:var(--teal-50); color:var(--teal-700); }
    .fsol-t { margin-top:22px; }
    .fsol-t .f-lbl { font-size:11px; color:var(--soft); font-weight:700; text-transform:uppercase; letter-spacing:.06em; }
    .fsol-t h3 { font-size:19px; font-weight:800; letter-spacing:-.02em; margin:5px 0 8px; }
    .fsol-t p { font-size:13.5px; color:var(--muted); line-height:1.55; max-width:250px; margin:0 auto; }
    /* Güven bandı */
    .stats { display:grid; grid-template-columns: repeat(3,1fr); gap:18px; margin-top:36px; }
    .stat { text-align:center; padding:28px 18px; border:1px solid var(--line); border-radius:var(--radius-lg); background:#fff; box-shadow:var(--shadow-xs); }
    .stat-n { font-size: clamp(20px,2.4vw,27px); font-weight:800; letter-spacing:-.02em; background: linear-gradient(90deg,var(--teal),#4f46e5); -webkit-background-clip:text; background-clip:text; -webkit-text-fill-color:transparent; }
    .stat-l { font-size:13px; color:var(--muted); margin-top:7px; line-height:1.5; }
    /* Müşteri yorumları slider */
    .tcar-wrap { margin-top:40px; }
    .tcar { display:grid; grid-auto-flow:column; grid-auto-columns: calc((100% - 40px)/3); gap:20px; overflow-x:auto; scroll-snap-type:x mandatory; scroll-behavior:smooth; padding:4px 2px 16px; scrollbar-width:none; }
    .tcar::-webkit-scrollbar{ display:none; }
    .tq { position:relative; scroll-snap-align:start; border:1px solid var(--line); border-radius:var(--radius-lg); background:#fff; padding:30px 26px 26px; display:flex; flex-direction:column; box-shadow:var(--shadow-xs); overflow:hidden; transition:transform .28s var(--ease), box-shadow .28s, border-color .28s; }
    .tq::before { content:""; position:absolute; top:0; left:0; right:0; height:3px; background:linear-gradient(90deg, var(--teal), var(--accent)); }
    .tq:hover { transform:translateY(-4px); box-shadow:var(--shadow); border-color:var(--teal-100); }
    .tq-mark { position:absolute; top:6px; right:22px; font-family:Georgia,'Times New Roman',serif; font-size:96px; line-height:1; color:var(--teal-50); font-weight:800; pointer-events:none; user-select:none; }
    .tq .stars { position:relative; color:var(--accent); font-size:15px; letter-spacing:3px; margin-bottom:14px; }
    .tq blockquote { position:relative; margin:0; font-size:15.5px; line-height:1.66; color:var(--ink-2); flex:1; }
    .tq blockquote::before { content:"“"; }
    .tq blockquote::after { content:"”"; }
    .tq .tq-who { display:flex; align-items:center; gap:12px; margin-top:20px; padding-top:16px; border-top:1px solid var(--line-2); }
    .tq .tq-av { width:44px; height:44px; border-radius:50%; background:linear-gradient(135deg,var(--teal),var(--teal-800)); color:#fff; display:grid; place-items:center; font-weight:800; font-size:16px; flex:none; box-shadow:0 4px 12px rgba(37,99,235,.28); }
    .tq .tq-meta { display:flex; flex-direction:column; line-height:1.3; min-width:0; }
    .tq .tq-n { display:block; font-weight:700; font-size:14px; color:var(--ink); }
    .tq .tq-b { display:block; font-size:12.5px; color:var(--muted); }
    .tq .tq-sec { margin-left:auto; flex:none; font-size:11px; font-weight:700; color:var(--teal-700); background:var(--teal-50); border:1px solid var(--teal-100); padding:4px 9px; border-radius:999px; }
    .tcar-nav { display:flex; gap:8px; justify-content:center; margin-top:4px; }
    .tcar-nav button { width:44px; height:44px; border-radius:50%; border:1px solid var(--line); background:#fff; color:var(--ink); display:grid; place-items:center; cursor:pointer; transition:border-color .16s, color .16s, background .16s; }
    .tcar-nav button:hover { border-color:var(--teal); color:var(--teal); background:var(--teal-50); }
    .tcar-nav svg { width:20px; height:20px; }
    .tcar-note { text-align:center; font-size:12px; color:var(--soft); margin-top:12px; }
    /* Referanslar — sağa kayan sonsuz şerit (marquee) */
    .refmq { position:relative; overflow:hidden; -webkit-mask-image:linear-gradient(90deg,transparent,#000 7%,#000 93%,transparent); mask-image:linear-gradient(90deg,transparent,#000 7%,#000 93%,transparent); }
    .refmq-track { display:flex; gap:16px; width:max-content; animation:refscroll 40s linear infinite; }
    .refmq:hover .refmq-track { animation-play-state:paused; }
    @keyframes refscroll { from{ transform:translateX(0); } to{ transform:translateX(calc(-50% - 8px)); } }
    @media (prefers-reduced-motion: reduce){ .refmq-track{ animation:none; flex-wrap:wrap; justify-content:center; width:auto; } }
    .refmq .reftype { flex:none; min-width:212px; }
    .refmq .reflogo { flex:none; width:230px; }
    /* Referanslar — işletme türü çipi */
    .reftype { display:flex; align-items:center; gap:13px; padding:16px 18px; border:1px solid var(--line); border-radius:var(--radius-lg); background:#fff; box-shadow:var(--shadow-xs); font-weight:700; font-size:14.5px; color:var(--ink); transition:transform .24s var(--ease), box-shadow .24s, border-color .24s; }
    .reftype:hover { transform:translateY(-3px); box-shadow:var(--shadow); border-color:var(--teal-100); }
    .reftype-ic { width:40px; height:40px; flex:none; border-radius:11px; display:grid; place-items:center; color:var(--teal-700); background:var(--teal-50); border:1px solid var(--teal-100); }
    .reftype-ic svg { width:20px; height:20px; }
    .ref-cta { text-align:center; margin-top:28px; font-size:14px; color:var(--muted); }
    .ref-cta a { color:var(--teal-700); font-weight:700; text-decoration:none; display:inline-flex; align-items:center; gap:5px; }
    .ref-cta a svg { width:15px; height:15px; }
    .ref-cta a:hover { color:var(--teal-800); }
    /* Referanslar — gerçek logo/isim duvarı */
    .reflogos { display:grid; grid-template-columns:repeat(4,1fr); gap:16px; }
    .reflogo { display:flex; flex-direction:column; align-items:center; justify-content:center; gap:9px; min-height:124px; padding:20px; border:1px solid var(--line); border-radius:var(--radius-lg); background:#fff; box-shadow:var(--shadow-xs); text-align:center; transition:transform .24s var(--ease), box-shadow .24s; }
    .reflogo:hover { transform:translateY(-3px); box-shadow:var(--shadow); }
    .reflogo-img { max-width:150px; max-height:54px; width:auto; height:auto; object-fit:contain; filter:grayscale(1); opacity:.72; transition:filter .24s, opacity .24s; }
    .reflogo:hover .reflogo-img { filter:none; opacity:1; }
    .reflogo-av { width:46px; height:46px; border-radius:50%; background:linear-gradient(135deg,var(--teal),var(--teal-800)); color:#fff; display:grid; place-items:center; font-weight:800; font-size:18px; }
    .reflogo-nm { font-weight:800; font-size:15px; color:var(--ink); }
    .reflogo-sec { font-size:11.5px; font-weight:700; color:var(--teal-700); background:var(--teal-50); border:1px solid var(--teal-100); padding:3px 9px; border-radius:999px; }
    @media (max-width: 900px){ .four{ grid-template-columns:1fr 1fr; } .stats{ grid-template-columns:1fr 1fr; } .tcar{ grid-auto-columns: calc((100% - 20px)/2); } .reftypes,.reflogos{ grid-template-columns:1fr 1fr; } }
    @media (max-width: 620px){ .four{ grid-template-columns:1fr; } .stats{ grid-template-columns:1fr; } .tcar{ grid-auto-columns: 86%; } }

    /* QR / KDS split görselleri */
    .split .lead { color: var(--muted); font-size: 16.5px; margin: 14px 0 24px; line-height: 1.6; }
    .split h2 { font-size: clamp(24px, 3.1vw, 33px); font-weight: 800; letter-spacing: -.025em; margin: 14px 0 0; line-height: 1.15; }
    .pm { background: #fff; }
    .pm-hero { background: var(--dark); color: #fff; padding: 18px 16px; } .pm-hero b { font-size: 15px; } .pm-hero span { font-size: 12px; color: #9db8b5; }
    .pm-cats { display: flex; gap: 6px; padding: 12px; } .pm-cats i { font-style: normal; font-size: 11.5px; font-weight: 600; padding: 6px 11px; border-radius: 999px; background: var(--bg-2); color: var(--muted); white-space: nowrap; } .pm-cats i.on { background: var(--teal-50); color: var(--teal-700); border: 1px solid var(--teal-100); }
    .pm-item { display: flex; gap: 12px; padding: 9px 14px; align-items: center; border-top: 1px solid var(--line-2); } .pm-item .pi-img { width: 42px; height: 42px; border-radius: 9px; background: var(--bg-2); flex: none; } .pm-item .pi-t { font-size: 13.5px; font-weight: 650; } .pm-item .pi-d { font-size: 11px; color: var(--muted); } .pm-item .pi-p { margin-left: auto; font-weight: 700; color: var(--ink); font-size: 13.5px; }
    .pm-bar { margin: 12px 14px 16px; height: 46px; border-radius: 11px; background: var(--teal); color: #fff; display: flex; align-items: center; justify-content: center; font-weight: 650; font-size: 14px; }

    /* Fiyat kartları */
    .price-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; align-items: start; }
    .price { background: #fff; border: 1px solid var(--line); border-radius: 18px; padding: 26px; }
    .price.pop { border-color: var(--teal); box-shadow: var(--shadow); position: relative; }
    .price.pop .tag { position: absolute; top: -11px; left: 26px; background: var(--teal); color: #fff; font-size: 11px; font-weight: 700; padding: 3px 11px; border-radius: 999px; }
    .price .pn { font-size: 17px; font-weight: 800; } .price .pd { font-size: 13.5px; color: var(--muted); margin: 5px 0 14px; min-height: 38px; line-height: 1.5; }
    .price .pp { font-size: 14px; font-weight: 800; color: var(--teal-700); margin-bottom: 16px; }
    .price ul { list-style: none; margin: 0 0 18px; padding: 0; display: grid; gap: 10px; }
    .price li { font-size: 13.5px; display: flex; gap: 9px; color: var(--ink-2); } .price li .ck { width: 18px; height: 18px; flex: none; }

    /* Demo form */
    .demo-wrap { display: grid; grid-template-columns: 1fr 1fr; gap: 44px; align-items: start; }
    .demo-wrap h2 { font-size: clamp(24px, 3.1vw, 33px); font-weight: 800; letter-spacing: -.025em; margin: 14px 0 0; }
    .form { background: #fff; border: 1px solid var(--line); border-radius: 18px; padding: 26px; box-shadow: var(--shadow-sm); }
    .form h3 { margin: 0; font-size: 19px; font-weight: 700; } .form .fsub { color: var(--muted); font-size: 13.5px; margin: 4px 0 18px; }
    .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
    .field { margin-bottom: 12px; } .field label { display: block; font-size: 12.5px; font-weight: 600; color: var(--ink-2); margin-bottom: 5px; }
    .field input, .field select, .field textarea { width: 100%; height: 46px; border: 1px solid var(--line); border-radius: 10px; padding: 0 13px; font: inherit; font-size: 15px; background: #fff; color: var(--ink); }
    .field textarea { height: 82px; padding: 11px 13px; resize: vertical; }
    .field input:focus, .field select:focus, .field textarea:focus { outline: none; border-color: var(--teal); box-shadow: var(--ring); }
    .msg { margin-top: 12px; font-size: 14px; font-weight: 600; min-height: 20px; } .msg.ok { color: var(--ok); } .msg.err { color: var(--err); }
    .promises { display: grid; gap: 12px; margin-top: 22px; } .promises span { font-size: 15px; color: var(--ink-2); display: flex; gap: 10px; align-items: center; } .promises .ck { width: 20px; height: 20px; flex: none; }

    @media (max-width: 960px) {
        .hero { padding: 26px 0 36px; } .hero-grid { grid-template-columns: 1fr; gap: 30px; }
        .hero-vis .f-a, .hero-vis .f-b { display: none; }
        .sectors { grid-template-columns: 1fr 1fr; }
        .flowsplit { grid-template-columns: 1fr; gap: 28px; }
        .eco3, .price-grid { grid-template-columns: 1fr; }
        .split, .demo-wrap { grid-template-columns: 1fr; gap: 28px; }
    }
    @media (max-width: 560px) { .sectors { grid-template-columns: 1fr; } .ec ul { grid-template-columns: 1fr; } .hero-metrics { gap: 16px; } }
</style>
@endpush

@section('content')

{{-- ===== HERO ===== --}}
<section class="hero">
    <div class="wrap hero-grid">
        <div>
            <span class="eyebrow">{!! $ic['store'] !!} Bulut tabanlı restoran &amp; kafe yönetim sistemi</span>
            <h1>İşletmenizin tüm operasyonu <span class="ac">tek platformda</span></h1>
            <p class="sub">Siparişten mutfağa, kasadan stoğa, personelden raporlamaya kadar restoran ve kafenizin her adımını tek ekrandan yönetin.</p>
            <div class="hero-cta">
                <a href="/#demo" class="btn btn-primary btn-lg">Ücretsiz Demo Talep Et {!! $ic['arrow'] !!}</a>
                <a href="#kesfet" class="btn btn-line btn-lg">Sistemi Keşfet</a>
            </div>
            <div class="hero-note">
                <span>{!! $tick !!} Kurulum ücreti yok</span>
                <span>{!! $tick !!} Kredi kartı gerekmez</span>
                <span>{!! $tick !!} Menü aktarım desteği</span>
            </div>
        </div>
        <div class="hero-vis reveal">
            <div class="shot">
                <div class="frame-bar"><i></i><i></i><i></i><span class="fb-url">panel.bambumpos.com</span></div>
                <img src="/assets/site/shots/app-dashboard.jpg?v=2" width="1440" height="900" loading="eager" decoding="async"
                     alt="BamBumPOS yönetim paneli — canlı ciro, tahsilat, açık masa ve sipariş özeti">
            </div>
            <div class="float f-a"><span class="fi" style="background:var(--teal-50);color:var(--teal-700)">{!! $ic['card'] !!}</span><div><div class="ft">Ödeme onaylandı</div><div class="fd">Masa 7 · ₺340</div></div></div>
            <div class="float f-b"><span class="fi" style="background:#fef3c7;color:#b45309">{!! $ic['box'] !!}</span><div><div class="ft">Kritik stok uyarısı</div><div class="fd">Espresso çekirdeği</div></div></div>
        </div>
    </div>
</section>

{{-- ===== DEĞER ŞERİDİ ===== --}}
<section class="sec-sm bg-2" id="kesfet" style="border-bottom:1px solid var(--line)">
    <div class="wrap grid g-4">
        @foreach([
            ['zap','Daha hızlı satış','Tek dokunuşla adisyon, hızlı ödeme, QR self-servis.'],
            ['shield','Daha az hata','Sipariş otomatik istasyona düşer, kayıp sipariş biter.'],
            ['chart','Daha yüksek kontrol','Rol bazlı yetki, işlem kaydı, anlık bildirim.'],
            ['trend','Daha kârlı yönetim','Reçete maliyeti ve fire analiziyle sızıntıları görün.'],
        ] as $i => $v)
            <div class="reveal @if($i%4) d{{ $i%4 }} @endif" style="display:flex;gap:13px;align-items:flex-start">
                <span style="width:42px;height:42px;border-radius:11px;background:#fff;border:1px solid var(--teal-100);color:var(--teal);display:grid;place-items:center;flex:none">{!! $ic[$v[0]] !!}</span>
                <div><div style="font-weight:700;font-size:15px;margin-bottom:3px">{{ $v[1] }}</div><div style="font-size:13.5px;color:var(--muted);line-height:1.5">{{ $v[2] }}</div></div>
            </div>
        @endforeach
    </div>
</section>

{{-- ===== TEK PLATFORM, DÖRT AKILLI ÇÖZÜM (telefon mockup'ları) ===== --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['layers'] !!} BamBumPOS ekosistemi</span><h2>Tek Platform, <span class="ac">Dört Akıllı Çözüm</span></h2><p>Restoran ve kafe operasyonlarınızı parçalamayın. Satış, yönetim, ekip ve dijital sipariş mükemmel bir uyum içinde çalışır.</p></div>
        <div class="four" style="margin-top:52px">

            {{-- 1) Satış (POS) --}}
            <div class="fsol reveal">
                <div class="tp-phone tp-click">
                    <img class="tp-fr" src="/assets/site/screens/ck-satis-a.jpg?v=1" alt="BamBumPOS masa panosu" loading="lazy" decoding="async">
                    <img class="tp-fr tp-fr-b" src="/assets/site/screens/ck-satis-b.jpg?v=1" alt="BamBumPOS sipariş panosu" loading="lazy" decoding="async">
                    <span class="tp-tap" style="left:50%"></span>
                </div>
                <div class="fsol-t"><span class="f-lbl">Satışın kalbi</span><h3>BamBumPOS Satış</h3><p>Masa, adisyon, hızlı satış ve ödeme; hesap böl/birleştir, markadan bağımsız POS ve ÖKC ile hızlı tahsilat.</p></div>
            </div>

            {{-- 2) Manager (dashboard) --}}
            <div class="fsol reveal d1">
                <div class="tp-phone tp-click d1">
                    <img class="tp-fr" src="/assets/site/screens/ck-manager-a.jpg?v=1" alt="BamBumPOS Manager / özet" loading="lazy" decoding="async">
                    <img class="tp-fr tp-fr-b" src="/assets/site/screens/ck-manager-b.jpg?v=1" alt="BamBumPOS Manager / vardiya" loading="lazy" decoding="async">
                    <span class="tp-tap" style="left:50%"></span>
                </div>
                <div class="fsol-t"><span class="f-lbl">Yönetim paneli</span><h3>BamBumPOS Manager</h3><p>Ciro, şube, stok, hedef ve raporlar tek yönetim ekranında; patron işletmesini cebinden anlık takip eder, karar verir.</p></div>
            </div>

            {{-- 3) Team (vardiya) --}}
            <div class="fsol reveal d2">
                <div class="tp-phone tp-click d2">
                    <img class="tp-fr" src="/assets/site/screens/ck-team-a.jpg?v=1" alt="BamBumPOS Team / panelim" loading="lazy" decoding="async">
                    <img class="tp-fr tp-fr-b" src="/assets/site/screens/ck-team-b.jpg?v=1" alt="BamBumPOS Team / mesaim" loading="lazy" decoding="async">
                    <span class="tp-tap" style="left:30%"></span>
                </div>
                <div class="fsol-t"><span class="f-lbl">Personel bölümü</span><h3>BamBumPOS Team</h3><p>Personel giriş-çıkış, vardiya, mola, görev, prim ve maaş — ekibin her şeyi tek personel ekranında.</p></div>
            </div>

            {{-- 4) QR (dijital menü) — menüyü gez → ürüne dokun → ürün detayı --}}
            <div class="fsol reveal d3">
                <div class="tp-phone tp-click d3">
                    <img class="tp-fr" src="/assets/site/screens/qr-menu.jpg?v=1" alt="BamBumPOS QR dijital menü" loading="lazy" decoding="async">
                    <img class="tp-fr tp-fr-b" src="/assets/site/screens/qr-product.jpg?v=1" alt="BamBumPOS QR ürün detayı — foto, fiyat, alerjen" loading="lazy" decoding="async">
                    <span class="tp-tap" style="left:88%"></span>
                </div>
                <div class="fsol-t"><span class="f-lbl">Dijital sipariş</span><h3>BamBumPOS QR &amp; Kiosk</h3><p>Masadan dijital sipariş, garson çağır, hesap iste ve self-servis kiosk — çoklu dil desteğiyle.</p></div>
            </div>

        </div>
    </div>
</section>

{{-- ===== SEKTÖRLER ===== --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><h2>Her işletme tipine hazır kurulum</h2><p>Menü yapınızdan hazırlık akışınıza kadar sektörünüze göre önceden yapılandırılmış bir sistemle başlayın.</p></div>
        <div class="sectors" style="margin-top:44px">
            @foreach([
                ['Kafe', 'Hızlı servis, QR self-servis ve barista akışı', '/kafe-pos-sistemi', 'coffee', 'kafe'],
                ['Restoran', 'Masa/adisyon, kat planı ve mutfak istasyonları', '/restoran-pos-sistemi', 'utensils', 'restoran'],
                ['Nargile Salonu', 'Nargile hazırlık kulvarı ve masa süre takibi', '/nargile-salonu-pos-sistemi', 'flame', 'nargile'],
                ['Bar & Pub', 'Hızlı bar satışı, adisyon ve hesap bölme', '/bar-pub-pos-sistemi', 'glass', 'bar-pub'],
                ['Fast Food', 'Sayaç satışı, kiosk ve paket sipariş', '/fast-food-pos-sistemi', 'burger', 'fast-food'],
                ['Otel & Sosyal Tesis', 'Çoklu nokta, oda/üye hesabı ve tesis raporu', '/otel-pos-sistemi', 'bed', 'otel'],
                ['Paket Servis', 'Telefon/online sipariş, kurye ve bölge yönetimi', '/paket-servis-pos-sistemi', 'truck', 'paket-servis'],
                ['Çok Şubeli Zincir', 'Merkezi menü, şube karşılaştırma, stok transferi', '/cok-subeli-restoran-yonetimi', 'branch', 'cok-subeli'],
            ] as $i => $s)
                <a class="scard reveal @if($i%4) d{{ $i%4 }} @endif" href="{{ $s[2] }}">
                    <img class="scard-img" src="/assets/site/sectors/{{ $s[4] }}.jpg?v=1" alt="{{ $s[0] }} için BamBumPOS POS çözümü" loading="lazy" decoding="async" width="720" height="900">
                    <span class="scard-ic">{!! $ic[$s[3]] !!}</span>
                    <div class="scard-body">
                        <h3>{{ $s[0] }}</h3>
                        <p>{{ $s[1] }}</p>
                        <span class="scard-l">Özellikleri keşfet {!! $ic['arrow'] !!}</span>
                    </div>
                </a>
            @endforeach
        </div>
    </div>
</section>

{{-- ===== GÜVEN BANDI ===== --}}
@php($bc = config('social.businesses_count'))
<section class="sec">
    <div class="wrap">
        <div class="sec-head center">
            <span class="eyebrow">{!! $ic['shield'] !!} Güven</span>
            <h2>@if($bc){{ $bc }} işletme @endif BamBumPOS ile büyüyor</h2>
            <p>Kafeden çok şubeli zincire, nargile salonundan paket servise; farklı ölçekte işletmeler operasyonlarını tek platformda yönetiyor.</p>
        </div>
        <div class="stats">
            @foreach(config('social.stats', []) as $s)
                <div class="stat reveal"><div class="stat-n">{{ $s['num'] }}</div><div class="stat-l">{{ $s['label'] }}</div></div>
            @endforeach
        </div>
    </div>
</section>

{{-- ===== KARMAŞAYI UÇTAN UCA ÇÖZÜMLE (operasyon akışı) ===== --}}
<section class="sec bg-2">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['layers'] !!} Uçtan uca operasyon</span><h2>Karmaşayı uçtan uca çözümle bitirin</h2><p>Sipariş alınır, doğru istasyona düşer, hazırlanır, servis edilir; stok düşer, rapor güncellenir, patron anında bilgilenir — hepsi birbirine bağlı tek akışta.</p></div>
        <div class="flowsplit" style="margin-top:40px">
            <div class="reveal">
                <div class="shot">
                    <div class="frame-bar"><i></i><i></i><i></i><span class="fb-url">Masa Panosu — BamBumPOS</span></div>
                    <img src="/assets/site/shots/app-masalar.jpg?v=2" width="1440" height="900" loading="lazy" decoding="async" alt="BamBumPOS masa panosu — dolu/boş masalar ve alanlar">
                </div>
            </div>
            <div class="steps">
                @foreach([
                    ['Sipariş alınır', 'Garson, QR menü, kiosk veya paket — tüm kanallar tek adisyonda birleşir.'],
                    ['İstasyona düşer', 'Yemek mutfağa, içecek baristaya, nargile hazırlığa otomatik yönlenir.'],
                    ['Hazırlanır & servis edilir', 'Hazırlık ekranı durumu günceller, komi hazır ürünü görür ve servis eder.'],
                    ['Ödeme alınır', 'Hesap bölme/birleştirme, markadan bağımsız POS ve ÖKC ile hızlı tahsilat.'],
                    ['Stok düşer', 'Reçeteye göre malzemeler otomatik düşer; kritik stok uyarısı üretilir.'],
                    ['Rapor & bildirim', 'Ciro, ürün ve personel raporları anlık güncellenir; patron mobil bildirim alır.'],
                ] as $i => $st)
                    <div class="stp reveal"><div class="n">{{ $i+1 }}</div><div><h4>{{ $st[0] }}</h4><p>{{ $st[1] }}</p></div></div>
                @endforeach
            </div>
        </div>
    </div>
</section>

{{-- ===== EKOSİSTEM (koyu bölüm) ===== --}}
<section class="sec eco-dark">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['layers'] !!} BamBumPOS ekosistemi</span><h2>Tek adisyon programı değil, bir işletme ekosistemi</h2><p>İhtiyacınıza göre açıp kapatabileceğiniz, birbirine bağlı ürün aileleri.</p></div>
        <div class="eco3" style="margin-top:44px">
            @foreach([
                ['card','Satış','Masa, adisyon ve ödeme', ['Masa & adisyon', 'Hızlı satış', 'Hesap böl/birleştir', 'İkram & indirim', 'Servis ücreti', 'Ödeme']],
                ['chart','Manager','Ciro, şube ve raporlar', ['Ciro & şubeler', 'Stok', 'Personel', 'Raporlar', 'Anlık bildirim', 'Mobil patron']],
                ['users','Team','Personel ve vardiya', ['Giriş-çıkış', 'Vardiya & mola', 'Görev & hedef', 'Prim & komisyon', 'İzin', 'Maaş & avans']],
                ['qr','QR','Masadan dijital sipariş', ['Dijital menü', 'Masadan sipariş', 'Garson çağır', 'Hesap iste', 'Çoklu dil', 'Alerjen bilgisi']],
                ['kiosk','Kiosk','Self servis sipariş', ['Self servis', 'Ürün önerisi', 'Sepet büyütme', 'Kartla ödeme', 'Çoklu dil', 'Sıra numarası']],
                ['plug','Entegrasyon','Ödeme, ÖKC ve API', ['Sanal POS', 'Yazarkasa/ÖKC', 'Paket platformlar', 'Muhasebe', 'Donanım', 'API & Webhook']],
            ] as $i => $e)
                <div class="ec reveal @if($i%3) d{{ $i%3 }} @endif">
                    <div class="ec-h"><span class="ec-ic">{!! $ic[$e[0]] !!}</span><div><b>BamBumPOS</b><h3>{{ $e[1] }}</h3></div></div>
                    <ul>@foreach($e[3] as $li)<li><span class="d">{!! $ic['check'] !!}</span> {{ $li }}</li>@endforeach</ul>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- ===== QR MENÜ ===== --}}
<section class="sec bg-2" id="qr">
    <div class="wrap split">
        <div>
            
            <h2>Müşteriniz masadan, kendi dilinde sipariş versin</h2>
            <p class="lead">Karekodu okutan misafir menüyü görür, varyant ve ekstra seçer, sepete ekler, garson çağırır ve hesap ister. Siparişler doğrudan istasyonlara düşer.</p>
            <ul class="checks">
                <li>{!! $tick !!} Kategori, varyant, ekstra malzeme ve alerjen bilgisi</li>
                <li>{!! $tick !!} Sepete ekleme, garson çağırma ve hesap isteme</li>
                <li>{!! $tick !!} Sipariş durumu takibi — mutfaktan masaya</li>
                <li>{!! $tick !!} TR / EN / DE çoklu dil ve markanıza özel görünüm</li>
            </ul>
            <a href="/qr-menu" class="btn btn-primary" style="margin-top:24px">QR Menüyü İncele {!! $ic['arrow'] !!}</a>
        </div>
        <div class="reveal d1">@include('marketing.partials.mockup-phone')</div>
    </div>
</section>

{{-- ===== HAZIRLIK İSTASYONLARI ===== --}}
<section class="sec" id="kds">
    <div class="wrap split">
        <div class="reveal">
            <div class="shot">
                <div class="frame-bar"><i></i><i></i><i></i><span class="fb-url">Mutfak Ekranı — BamBumPOS</span></div>
                <img src="/assets/site/shots/app-mutfak.jpg?v=2" width="1440" height="900" loading="lazy" decoding="async" alt="BamBumPOS mutfak ekranı — sipariş fişleri, istasyon filtreleri ve gecikme uyarısı">
            </div>
        </div>
        <div>
            
            <h2>Herkes kendi kulvarında, hiçbir sipariş kaybolmaz</h2>
            <p class="lead">Ürünler tanımına göre otomatik yönlenir: yemek mutfağa, içecek baristaya, nargile hazırlık ekranına, hazır ürünler komiye. Gecikmeyi renk ve süre ile görürsünüz.</p>
            <ul class="checks">
                <li>{!! $tick !!} Yemek → Mutfak, İçecek → Barista, Nargile → Hazırlık</li>
                <li>{!! $tick !!} Süre ve renk uyarısıyla gecikme takibi</li>
                <li>{!! $tick !!} Hazır ürün komi ekranına düşer, servis işaretlenir</li>
                <li>{!! $tick !!} İstasyonları eklentiyle açıp kapatın</li>
            </ul>
            <a href="/mutfak-ekran-sistemi" class="btn btn-primary" style="margin-top:24px">Hazırlık Ekranlarını İncele {!! $ic['arrow'] !!}</a>
        </div>
    </div>
</section>

{{-- ===== NEDEN (açık, uyumlu) ===== --}}
<section class="sec bg-2" id="neden">
    <div class="wrap">
        <div class="sec-head center"><h2>Güçlü, güvenli ve sizin markanıza ait</h2><p>Teknik özellikleri değil, işletmenize kattığı değeri konuşuyoruz.</p></div>
        <div class="grid g-4" style="margin-top:44px">
            @foreach([
                ['shield','Veri güvenliği','Şifreli bağlantı, rol bazlı erişim, işlem kayıtları ve otomatik yedek.'],
                ['branch','Ölçeklenebilir','Tek şubeden çok şubeli zincire; merkezi yönetim ve konsolide rapor.'],
                ['clock','Kesintisiz','Bulut altyapı, yüksek erişilebilirlik ve hızlı destek yanıtı.'],
                ['zap','Kolay öğrenilir','Personelin dakikalar içinde öğrendiği sade ve hızlı arayüz.'],
            ] as $i => $w)
                <div class="card hover reveal @if($i%4) d{{ $i%4 }} @endif">
                    <div class="c-ic">{!! $ic[$w[0]] !!}</div>
                    <h3 style="font-size:16.5px">{{ $w[1] }}</h3><p>{{ $w[2] }}</p>
                </div>
            @endforeach
        </div>
    </div>
</section>

{{-- ===== FİYATLANDIRMA ===== --}}
<section class="sec">
    <div class="wrap">
        <div class="sec-head center"><h2>İşletmenizin ölçeğine uygun paket</h2><p>Küçük kafeden çok şubeli zincire kadar; ihtiyacınız büyüdükçe modül ekleyin.</p></div>
        <div class="price-grid" style="margin-top:44px">
            <div class="price reveal">
                <div class="pn">Başlangıç</div><div class="pd">Küçük kafe ve hızlı servis işletmeleri için</div>
                <div class="pp">Teklif Al</div>
                <ul><li>{!! $tick !!} Temel POS & adisyon</li><li>{!! $tick !!} QR menü & masa yönetimi</li><li>{!! $tick !!} Temel raporlar</li><li>{!! $tick !!} Belirli personel sayısı</li></ul>
                <a href="/#demo" class="btn btn-line" style="width:100%">Teklif Al</a>
            </div>
            <div class="price pop reveal d1">
                <span class="tag">En popüler</span>
                <div class="pn">Profesyonel</div><div class="pd">Büyüyen restoran ve kafeler için</div>
                <div class="pp">Teklif Al</div>
                <ul><li>{!! $tick !!} Başlangıç’taki her şey</li><li>{!! $tick !!} Personel & vardiya</li><li>{!! $tick !!} Stok & reçete</li><li>{!! $tick !!} Rezervasyon & paket sipariş</li><li>{!! $tick !!} Gelişmiş raporlar</li></ul>
                <a href="/#demo" class="btn btn-primary" style="width:100%">Demo Talep Et</a>
            </div>
            <div class="price reveal d2">
                <div class="pn">Kurumsal</div><div class="pd">Çok şubeli ve zincir işletmeler için</div>
                <div class="pp">Teklif Al</div>
                <ul><li>{!! $tick !!} Profesyonel’deki her şey</li><li>{!! $tick !!} Çoklu / özel şube</li><li>{!! $tick !!} Merkezi yönetim & stok transferi</li><li>{!! $tick !!} Özel entegrasyon & SLA</li><li>{!! $tick !!} Öncelikli destek</li></ul>
                <a href="/#demo" class="btn btn-line" style="width:100%">Satışla Görüş</a>
            </div>
        </div>
        <div class="center" style="margin-top:26px"><a href="/fiyatlandirma" style="color:var(--teal-700);font-weight:650">Detaylı fiyatlandırma ve karşılaştırma →</a></div>
    </div>
</section>

{{-- ===== DEMO FORM ===== --}}
<section class="sec bg-2" id="demo">
    <div class="wrap demo-wrap">
        <div>
            
            <h2>İşletmenize özel demo talep edin</h2>
            <p class="lead">Formu doldurun, ekibimiz kısa sürede sizinle iletişime geçsin. Sisteme özel kurulum ve fiyat için hiçbir taahhüt gerekmez.</p>
            <div class="promises">
                <span>{!! $tick !!} 14 gün ücretsiz deneme</span>
                <span>{!! $tick !!} Kurulum & menü aktarımı desteği</span>
                <span>{!! $tick !!} Kredi kartı gerekmez, taahhüt yok</span>
            </div>
        </div>
        <form class="form" id="demoForm" onsubmit="return submitDemo(event)">
            <h3>Ücretsiz Demo İste</h3>
            <div class="fsub">Bilgilerinizi bırakın, biz arayalım.</div>
            <div class="grid2">
                <div class="field"><label>Ad Soyad *</label><input name="name" required maxlength="120" placeholder="Adınız"></div>
                <div class="field"><label>Telefon *</label><input name="phone" required maxlength="40" inputmode="tel" placeholder="05xx…"></div>
            </div>
            <div class="grid2">
                <div class="field"><label>İşletme adı</label><input name="business" maxlength="160" placeholder="Kafe / restoran"></div>
                <div class="field"><label>Sektör</label>
                    <select name="sector"><option value="">Seçin…</option><option>Kafe</option><option>Restoran</option><option>Nargile Salonu</option><option>Bar & Pub</option><option>Fast Food</option><option>Otel & Sosyal Tesis</option><option>Diğer</option></select>
                </div>
            </div>
            <div class="field"><label>E-posta</label><input name="email" type="email" maxlength="160" placeholder="ornek@isletme.com"></div>
            <div class="field"><label>Mesaj (isteğe bağlı)</label><textarea name="message" maxlength="1000" placeholder="İhtiyacınızı kısaca yazın…"></textarea></div>
            <button type="submit" class="btn btn-primary" style="width:100%">Demo Talebini Gönder</button>
            <div class="msg" id="demoMsg" role="status"></div>
        </form>
    </div>
</section>

{{-- ===== REFERANSLAR ===== --}}
@php($refs = config('social.references', []))
@php($refTypes = config('social.reference_types', []))
<section class="sec bg-2" id="referanslar">
    <div class="wrap">
        <div class="sec-head center">
            <span class="eyebrow">{!! $ic['store'] !!} Referanslar</span>
            <h2>Farklı sektörlerde, farklı ölçeklerde tercih ediliyor</h2>
            <p>Tek şubeli bir kafeden çok şubeli zincire kadar; BamBumPOS her işletme türünün akışına uyum sağlar.</p>
        </div>
        @if(count($refs))
            <div class="refmq" style="margin-top:40px">
                <div class="refmq-track">
                    @foreach(array_merge($refs, $refs) as $r)
                        <div class="reflogo">
                            @if(!empty($r['logo']))
                                <img class="reflogo-img" src="{{ $r['logo'] }}" alt="{{ $r['name'] }}" loading="lazy" decoding="async">
                            @else
                                <span class="reflogo-av">{{ mb_strtoupper(mb_substr($r['name'], 0, 1)) }}</span>
                                <span class="reflogo-nm">{{ $r['name'] }}</span>
                            @endif
                            @if(!empty($r['sector']))<span class="reflogo-sec">{{ $r['sector'] }}</span>@endif
                        </div>
                    @endforeach
                </div>
            </div>
        @else
            <div class="refmq" style="margin-top:40px">
                <div class="refmq-track">
                    @foreach(array_merge($refTypes, $refTypes) as $rt)
                        <div class="reftype">
                            <span class="reftype-ic">{!! $ic[$rt['icon']] ?? '' !!}</span>
                            <span class="reftype-l">{{ $rt['label'] }}</span>
                        </div>
                    @endforeach
                </div>
            </div>
            <p class="ref-cta">Siz de bu listede yer alın — <a href="/iletisim">BamBumPOS referansı olun {!! $ic['arrow'] !!}</a></p>
        @endif
    </div>
</section>

{{-- ===== MÜŞTERİ YORUMLARI (premium slider) ===== --}}
@php($tst = config('social.testimonials', []))
@php($tphl = config('social.testimonials_are_placeholder'))
@if(count($tst))
<section class="sec" id="yorumlar">
    <div class="wrap">
        <div class="sec-head center"><span class="eyebrow">{!! $ic['tag'] !!} Müşteri yorumları</span><h2>İşletmeler BamBumPOS’u seviyor</h2><p>Farklı sektörlerden işletmelerin gözünden gerçek kullanım deneyimi.</p></div>
        <div class="tcar-wrap">
            <div class="tcar" data-tcar>
                @foreach($tst as $t)
                    <figure class="tq reveal">
                        <span class="tq-mark" aria-hidden="true">”</span>
                        @unless($tphl)<div class="stars" aria-label="5 üzerinden 5">★★★★★</div>@endunless
                        <blockquote>{{ $t['quote'] }}</blockquote>
                        <figcaption class="tq-who">
                            <span class="tq-av">{{ mb_strtoupper(mb_substr($t['name'], 0, 1)) }}</span>
                            <span class="tq-meta">
                                <span class="tq-n">{{ $t['name'] }}</span>
                                <span class="tq-b">{{ $t['business'] }}</span>
                            </span>
                            @if(!empty($t['sector']))<span class="tq-sec">{{ $t['sector'] }}</span>@endif
                        </figcaption>
                    </figure>
                @endforeach
            </div>
            <div class="tcar-nav">
                <button type="button" data-tcar-prev aria-label="Önceki yorum"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg></button>
                <button type="button" data-tcar-next aria-label="Sonraki yorum"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg></button>
            </div>
            @if($tphl)<div class="tcar-note">Örnek yorumlar — gerçek müşteri yorumlarıyla değiştirilecek (config/social.php).</div>@endif
        </div>
    </div>
</section>
@endif

{{-- ===== SSS ===== --}}
<section class="sec" id="sss">
    <div class="wrap">
        <div class="sec-head center"><h2>Sık sorulan sorular</h2></div>
        <div class="faq">
            <details class="qa"><summary>Kurulum ne kadar sürer? <span class="x">+</span></summary><p>Menünüzü yükledikten sonra QR kodları yazdırıp aynı gün satışa başlayabilirsiniz. Ekibimiz menü aktarımında yardımcı olur.</p></details>
            <details class="qa"><summary>Hangi ödeme cihazlarıyla çalışır? <span class="x">+</span></summary><p>Markadan bağımsız POS entegratörü sayesinde banka sanal POS, YN-POS/ÖKC yazarkasalar ve ödeme kuruluşlarıyla uyumludur.</p></details>
            <details class="qa"><summary>İnternet kesilirse ne olur? <span class="x">+</span></summary><p>Menü ve sipariş akışı bulutta çalışır; verileriniz güvenli ve yedeklidir. Bağlantı geri geldiğinde kaldığınız yerden devam edersiniz.</p></details>
            <details class="qa"><summary>İstemediğim modülleri kapatabilir miyim? <span class="x">+</span></summary><p>Evet. Nargile, kiosk, teslimat, prim gibi modüller eklentidir; Ayarlar › Eklentiler’den tek tıkla açıp kapatırsınız.</p></details>
            <details class="qa"><summary>Müşteri menüyü İngilizce/Almanca görebilir mi? <span class="x">+</span></summary><p>Evet, QR menü TR/EN/DE dil seçicisiyle gelir; ürün adları sizin girdiğiniz gibi, arayüz seçilen dilde görünür.</p></details>
        </div>
    </div>
</section>

{{-- ===== FINAL CTA ===== --}}
<section class="sec dark center">
    <div class="wrap">
        <h2 style="color:#fff;font-size:clamp(26px,3.4vw,40px);font-weight:800;letter-spacing:-.025em">İşletmenizi BamBumPOS ile yönetmeye başlayın</h2>
        <p style="color:#9db8b5;font-size:17px;margin:16px auto 28px;max-width:560px">Karmaşayı bırakın, satışa odaklanın. Kurulum ve menü aktarımıyla dakikalar içinde hazır olun.</p>
        <div style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap">
            <a href="/#demo" class="btn btn-primary btn-lg">Ücretsiz Demo Talep Et {!! $ic['arrow'] !!}</a>
            <a href="https://wa.me/{{ ltrim(config('site.contact.whatsapp'),'+') }}" target="_blank" rel="noopener" class="btn btn-ghost btn-lg">WhatsApp’tan Yaz</a>
        </div>
    </div>
</section>
@endsection

@push('scripts')
<script>
    async function submitDemo(e){
        e.preventDefault();
        var f = e.target, msg = document.getElementById('demoMsg');
        var btn = f.querySelector('button[type=submit]');
        msg.className = 'msg'; msg.textContent = '';
        var body = {};
        new FormData(f).forEach(function(v,k){ body[k]=v; });
        if(!body.name || !body.phone){ msg.className='msg err'; msg.textContent='Ad ve telefon zorunludur.'; return false; }
        btn.disabled = true; var old = btn.textContent; btn.textContent = 'Gönderiliyor…';
        try{
            var r = await fetch('/demo-talep', {
                method:'POST',
                headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-TOKEN':'{{ csrf_token() }}'},
                body: JSON.stringify(body)
            });
            var d = await r.json().catch(function(){return {};});
            if(r.ok){ msg.className='msg ok'; msg.textContent = d.message || 'Talebiniz alındı! En kısa sürede size ulaşacağız.'; f.reset(); }
            else{ msg.className='msg err'; msg.textContent = d.message || (d.errors ? Object.values(d.errors)[0][0] : 'Gönderilemedi, tekrar deneyin.'); }
        }catch(err){ msg.className='msg err'; msg.textContent='Bağlantı hatası, tekrar deneyin.'; }
        finally{ btn.disabled=false; btn.textContent=old; }
        return false;
    }
    document.querySelectorAll('a[href^="#"]').forEach(function(a){
        a.addEventListener('click', function(e){ var t=document.querySelector(a.getAttribute('href')); if(t){ e.preventDefault(); t.scrollIntoView({behavior:'smooth'}); } });
    });
</script>
@endpush
