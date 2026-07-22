<?php

namespace App\Modules\Identity\Concerns;

use App\Modules\Identity\Services\AuditLogger;

/**
 * Model olaylarını (created/updated/deleted) otomatik denetim kaydına düşer.
 * Hassas alanlar AuditLogger tarafında maskelenir.
 */
trait Auditable
{
    public static function bootAuditable(): void
    {
        static::created(function ($model): void {
            app(AuditLogger::class)->log(
                $model->getTable().'.created',
                $model,
                null,
                $model->attributesToArray(),
            );
        });

        static::updated(function ($model): void {
            $changes = $model->getChanges();
            unset($changes['updated_at']);

            if ($changes === []) {
                return;
            }

            $old = array_intersect_key($model->getOriginal(), $changes);

            app(AuditLogger::class)->log($model->getTable().'.updated', $model, $old, $changes);
        });

        static::deleted(function ($model): void {
            app(AuditLogger::class)->log(
                $model->getTable().'.deleted',
                $model,
                $model->attributesToArray(),
                null,
            );
        });
    }
}
