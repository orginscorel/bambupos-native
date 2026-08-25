<?php

namespace App\Modules\Marketing\Models;

use Illuminate\Database\Eloquent\Model;

/** BamBumPOS pazarlama "Demo İste" talebi (satış öncesi lead). */
class DemoRequest extends Model
{
    protected $fillable = [
        'name', 'business', 'phone', 'email', 'sector', 'message',
        'status', 'source', 'ip', 'user_agent', 'handled_at',
    ];

    protected function casts(): array
    {
        return ['handled_at' => 'datetime'];
    }
}
