@php($crumbs = $crumbs ?? [])
@if(count($crumbs))
<nav class="crumbs" aria-label="Breadcrumb">
    <div class="wrap" style="display:flex;flex-wrap:wrap;gap:6px;align-items:center;font-size:13px;color:var(--muted);padding-top:14px">
        @foreach($crumbs as $i => $c)
            @if(!empty($c['u']) && $i < count($crumbs)-1)
                <a href="{{ $c['u'] }}" style="color:var(--muted)">{{ $c['t'] }}</a><span style="color:var(--soft)">/</span>
            @else
                <span style="color:var(--ink-2);font-weight:600">{{ $c['t'] }}</span>
            @endif
        @endforeach
    </div>
</nav>
@endif
