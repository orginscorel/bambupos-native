<?php

namespace App\Modules\Settings\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\View\View;

/**
 * Public menü (venue.menu) görünümüne marka verisini bağlayan composer.
 *
 * Neden composer? Logo/marka alanı Ayarlar (Settings) modülünün malıdır;
 * Venue modülüne dokunmadan menü başlığına logo + kategori renk/ikon
 * meta'sını buradan veririz. Kiracı, ADR-008'e sadık kalarak YALNIZ
 * route'daki opak token'dan çözülür (istekten kimlik parametresi alınmaz).
 *
 * Cache güvenliği (ADR-011): çıktı token'a göre deterministiktir, çerez
 * veya kişiye özel veri yoktur → tam-sayfa cache aynen korunur. Maliyet
 * 2-3 hafif PK/unique sorgudur ve sayfa zaten 120 sn cache'lidir.
 */
class PublicMenuBranding
{
    public function compose(View $view): void
    {
        $brandLogoUrl = null;
        $catMeta = [];
        // §9 feature-flag: public menü davranışı. Kiracı çözülemezse (geçersiz
        // token) makul varsayılan = açık. Çıktı token'a göre deterministik
        // kalır → tam-sayfa cache (ADR-011) korunur.
        $menuFeatures = ['qr_ordering' => true, 'service_calls' => true];

        $token = request()?->route('token');

        // ADR-008 biçimi: 26 karakter base32; uymayan girdi DB'ye inmez.
        if (is_string($token) && preg_match('/^[A-Za-z2-7]{26}$/', $token) === 1) {
            $token = strtoupper($token);

            $tenantId = DB::table('tables')->where('qr_token', $token)->value('tenant_id')
                ?? DB::table('branches')->where('qr_token', $token)->value('tenant_id');

            if ($tenantId !== null) {
                $menuFeatures['qr_ordering'] = Features::enabled((int) $tenantId, 'qr_ordering');
                $menuFeatures['service_calls'] = Features::enabled((int) $tenantId, 'service_calls');

                $logoPath = DB::table('tenants')->where('id', $tenantId)->value('logo_path');

                if ($logoPath !== null && $logoPath !== '') {
                    $brandLogoUrl = Storage::disk('public')->url($logoPath);
                }

                // Story baloncukları: panelde tanımlıysa kategori rengi/ikonu/görseli.
                // Öncelik sırası (category-strip.blade.php'de uygulanır):
                // kategori görseli → kategorideki ilk ürün görseli → renk+baş harf.
                foreach (DB::table('categories')->where('tenant_id', $tenantId)
                    ->where('is_active', true)->get(['id', 'color', 'icon', 'image_path']) as $c) {
                    $catMeta[(int) $c->id] = [
                        'color' => $c->color,
                        'icon' => $c->icon,
                        'image' => $c->image_path !== null && $c->image_path !== ''
                            ? Storage::disk('public')->url($c->image_path)
                            : null,
                    ];
                }
            }
        }

        $view->with('brandLogoUrl', $brandLogoUrl);
        $view->with('catMeta', $catMeta);
        $view->with('menuFeatures', $menuFeatures);
    }
}
