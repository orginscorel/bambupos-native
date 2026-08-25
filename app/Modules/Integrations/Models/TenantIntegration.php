<?php

declare(strict_types=1);

namespace App\Modules\Integrations\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * Kiracı bazlı entegrasyon satırı — takılabilir çerçevenin deposu.
 *
 * BelongsToTenant → sorgular otomatik tenant_id ile süzülür (fail closed);
 * istekten gelen tenant_id asla yazılamaz (tenant_id fillable DEĞİL). Satır
 * yoksa entegrasyon KAPALI sayılır (Integrations cephesi karar verir).
 *
 * config: sağlayıcı API anahtarları/gizli değerleri (JSON). Gizli alanlar
 * panele MASKELİ döner; asla ham log/rapor'a yazılmaz.
 */
class TenantIntegration extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'key',
        'is_enabled',
        'config',
    ];

    protected function casts(): array
    {
        return [
            'is_enabled' => 'boolean',
            'config' => 'array',
        ];
    }
}
