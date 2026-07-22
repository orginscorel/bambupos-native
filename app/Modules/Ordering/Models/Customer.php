<?php

namespace App\Modules\Ordering\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\CustomerFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Customer extends Model
{
    /** @use HasFactory<CustomerFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'name',
        'phone',
        'email',
    ];

    protected static function newFactory(): Factory
    {
        return CustomerFactory::new();
    }
}
