<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/** Stok kalemi kategorisi (Et, Süt Ürünü, İçecek, Sarf…). */
class ItemCategory extends Model
{
    use BelongsToTenant;

    protected $table = 'inv_categories';

    protected $fillable = ['name', 'sort_order'];
}
