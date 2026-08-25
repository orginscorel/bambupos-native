@php($a = config('site.announcement'))
<div class="site-annc" style="background:var(--ink);color:#dfe8e7;font-size:13px;font-weight:500">
    <div class="wrap" style="display:flex;align-items:center;justify-content:center;gap:14px;min-height:38px;text-align:center;flex-wrap:wrap;padding-top:7px;padding-bottom:7px">
        <span>{{ $a['text'] }}</span>
        @if(!empty($a['cta_url']))
            <a href="{{ $a['cta_url'] }}" style="color:#fff;border:1px solid rgba(255,255,255,.22);padding:3px 12px;border-radius:999px;font-weight:600;font-size:12px;white-space:nowrap">{{ $a['cta_label'] }} →</a>
        @endif
    </div>
</div>
