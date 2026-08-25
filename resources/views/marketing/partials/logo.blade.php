@php($dark = $logoDark ?? false)
<svg class="logo-mk" width="34" height="34" viewBox="0 0 36 36" aria-hidden="true" focusable="false">
    <rect width="36" height="36" rx="10" fill="{{ $dark ? '#fff' : '#2563eb' }}"/>
    <g fill="{{ $dark ? '#2563eb' : '#fff' }}">
        <rect x="8.5" y="20" width="4" height="7" rx="1.4"/>
        <rect x="16" y="14.5" width="4" height="12.5" rx="1.4"/>
        <rect x="23.5" y="9" width="4" height="18" rx="1.4"/>
    </g>
    <circle cx="27" cy="10.5" r="2.4" fill="{{ $dark ? '#2563eb' : '#93c5fd' }}"/>
</svg>
<span class="logo-wm {{ $dark ? 'on-dark' : '' }}">BamBum<i>POS</i></span>
