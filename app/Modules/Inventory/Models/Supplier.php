<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Tedarikçi (§17.6). payment_term_days = vade günü. */
class Supplier extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_suppliers';

    protected $fillable = [
        'name', 'contact_name', 'phone', 'email', 'tax_no',
        'address', 'payment_term_days', 'note', 'is_active',
    ];

    protected function casts(): array
    {
        return ['payment_term_days' => 'integer', 'is_active' => 'boolean'];
    }

    public function priceHistory(): HasMany
    {
        return $this->hasMany(SupplierPrice::class, 'supplier_id')->latest('recorded_at');
    }
}
