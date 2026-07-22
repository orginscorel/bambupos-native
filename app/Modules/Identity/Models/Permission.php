<?php

namespace App\Modules\Identity\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * İzin kataloğu: platform genelinde sabittir (tenant_id YOK),
 * "modül.işlem" anahtarıyla tanımlanır (config/authz.php'den seed edilir).
 * Kiracılar katalogdan izin seçerek kendi rollerini kurar.
 */
class Permission extends Model
{
    protected $fillable = [
        'module',
        'action',
        'key',
        'label',
    ];

    public function roles(): BelongsToMany
    {
        return $this->belongsToMany(Role::class, 'permission_role');
    }
}
