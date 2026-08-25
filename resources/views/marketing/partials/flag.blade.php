@php($f = $f ?? 'tr')
@if($f === 'tr')
<svg class="flag" viewBox="0 0 24 16" width="21" height="14" aria-hidden="true"><rect width="24" height="16" rx="2.5" fill="#e30a17"/><circle cx="9.4" cy="8" r="3.5" fill="#fff"/><circle cx="10.8" cy="8" r="2.8" fill="#e30a17"/><path d="M13.7 8l2.5-.82-1.55 2.1v-2.56l1.55 2.1z" fill="#fff"/></svg>
@elseif($f === 'de')
<svg class="flag" viewBox="0 0 24 16" width="21" height="14" aria-hidden="true"><clipPath id="fde"><rect width="24" height="16" rx="2.5"/></clipPath><g clip-path="url(#fde)"><rect width="24" height="16" fill="#ffce00"/><rect width="24" height="10.7" fill="#dd0000"/><rect width="24" height="5.34" fill="#000"/></g></svg>
@else
<svg class="flag" viewBox="0 0 24 16" width="21" height="14" aria-hidden="true"><clipPath id="fen"><rect width="24" height="16" rx="2.5"/></clipPath><g clip-path="url(#fen)"><rect width="24" height="16" fill="#012169"/><path d="M0 0l24 16M24 0L0 16" stroke="#fff" stroke-width="3.2"/><path d="M0 0l24 16M24 0L0 16" stroke="#c8102e" stroke-width="1.6"/><path d="M12 0v16M0 8h24" stroke="#fff" stroke-width="4.4"/><path d="M12 0v16M0 8h24" stroke="#c8102e" stroke-width="2.2"/></g></svg>
@endif
