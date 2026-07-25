<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Venue\Services\QrTokenResolution;
use App\Modules\Venue\Services\QrTokenResolver;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Public QR ucu: `/m/{token}` (ADR-008).
 *
 * - Kiracı/şube/masa YALNIZ opak token'dan çözülür; URL'de veya istekte
 *   başka hiçbir kimlik kabul edilmez → başka masaya erişim imkânsız.
 * - Rotasyonla eskiyen token 410 + açıklama sayfası döner.
 * - Rate limit: IP başına; aşımda 429 (NAT gerçeği: limit cömert ama
 *   tarama girişimini keser). Şüpheli kullanım denetim kaydına düşer
 *   (QrTokenResolver).
 * - ADR-011: geçerli yanıt LiteSpeed tam-sayfa cache başlıkları taşır;
 *   oturum middleware'i bilinçli olarak YOKTUR (Set-Cookie sızmaz).
 */
class PublicMenuController extends Controller
{
    public function __construct(private readonly QrTokenResolver $resolver)
    {
    }

    public function show(Request $request, string $token): Response
    {
        // IP bazlı emniyet supabı (LiteSpeed cache'i ıskalayan istekler için).
        $limiterKey = 'qr-scan:'.sha1((string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 120)) {
            return response()->view('venue.qr-throttled', [], 429)
                ->header('Retry-After', (string) RateLimiter::availableIn($limiterKey))
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        RateLimiter::hit($limiterKey, 60);

        $resolution = $this->resolver->resolve($token, $request);

        if ($resolution->status === 'revoked' || $resolution->status === 'inactive') {
            // ADR-008: yenilenen QR basılana kadar eski karta açıklama.
            return response()->view('venue.qr-gone', [
                'reason' => $resolution->status,
            ], 410)->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        if ($resolution->status !== 'ok') {
            return response()->view('venue.qr-not-found', [], 404)
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        $tenant = $resolution->tenant;
        $branch = $resolution->branch;
        $table = $resolution->table;

        // Menü içeriği: bu kiracının + şubesinin aktif ürünleri.
        // (Catalog modülü public menüyü devraldığında bu sorgu oradan beslenecek;
        //  kiracı süzgeci her koşulda token'dan çözülen tenant_id'dir.)
        $products = DB::table('products')
            ->where('tenant_id', $tenant->getKey())
            ->where(function ($q) use ($branch): void {
                $q->whereNull('branch_id')->orWhere('branch_id', $branch->getKey());
            })
            ->where('is_active', true)
            ->orderBy('name')
            ->limit(500)
            ->get(['name', 'price_minor', 'currency']);

        return response()->view('venue.menu', [
            'tenantName' => $tenant->name,
            'branchName' => $branch->name,
            'tableLabel' => $table !== null
                ? trim($table->name.($table->number !== null ? ' · No '.$table->number : ''))
                : null,
            'products' => $products,
        ])
            // ADR-011: tam-sayfa public cache + tag purge altyapısı
            ->header('X-LiteSpeed-Cache-Control', 'public, max-age=120')
            ->header('X-LiteSpeed-Tag', sprintf('t%d, b%d', $tenant->getKey(), $branch->getKey()));
    }
}
