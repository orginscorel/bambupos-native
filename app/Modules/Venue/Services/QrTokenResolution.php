<?php

namespace App\Modules\Venue\Services;

use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;

/**
 * Token çözümleme sonucu (değer nesnesi).
 * status: ok | revoked | inactive | invalid
 * type:   table | branch (yalnız ok/revoked/inactive'de anlamlı)
 */
final class QrTokenResolution
{
    private function __construct(
        public readonly string $status,
        public readonly ?string $type = null,
        public readonly ?Tenant $tenant = null,
        public readonly ?Branch $branch = null,
        public readonly ?Table $table = null,
    ) {
    }

    public static function ok(Tenant $tenant, Branch $branch, ?Table $table): self
    {
        return new self('ok', $table !== null ? 'table' : 'branch', $tenant, $branch, $table);
    }

    public static function revoked(): self
    {
        return new self('revoked');
    }

    public static function inactive(): self
    {
        return new self('inactive');
    }

    public static function invalid(): self
    {
        return new self('invalid');
    }
}
