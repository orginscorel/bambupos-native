<?php

namespace App\Modules\Reports\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Kuyrukta üretilen rapor dışa aktarması. Kiracı scope'u (ADR-004) sayesinde
 * yabancı kiracının kaydı route binding'de 404 üretir.
 */
class ReportExport extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'branch_id',
        'user_id',
        'report_key',
        'format',
        'params',
        'status',
        'file_path',
        'rows_count',
        'error',
        'finished_at',
    ];

    protected function casts(): array
    {
        return [
            'params' => 'array',
            'rows_count' => 'integer',
            'finished_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function isReady(): bool
    {
        return $this->status === 'done' && $this->file_path !== null;
    }

    public function fileName(): string
    {
        return sprintf(
            '%s-%s-%s.%s',
            $this->report_key,
            (string) ($this->params['from'] ?? ''),
            (string) ($this->params['to'] ?? ''),
            $this->format,
        );
    }
}
