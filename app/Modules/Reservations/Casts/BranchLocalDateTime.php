<?php

namespace App\Modules\Reservations\Casts;

use App\Modules\Tenancy\Models\Branch;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;

/**
 * reserved_at için "şube duvar saati" cast'i.
 *
 * KÖK NEDEN (timezone tuzağı): saklama app.timezone (UTC) iken personel ve
 * müşteri ŞUBE saatiyle (Europe/Istanbul, +3) düşünür. Ham cast UTC döndürünce
 * 19:30 seçilen rezervasyon panelde/okumada 16:30 görünüyordu (−3 kayma).
 *
 * ÇÖZÜM: değer DB'de app.timezone (UTC) olarak SAKLANIR — cron/whereBetween
 * bind'leri ve now() karşılaştırmaları UTC referansıyla tutarlı kalır — ama
 * PHP tarafına OKUNURKEN şube saat dilimine çevrilir. Carbon karşılaştırmaları
 * ANLIK (instant) tabanlı olduğundan yaklaşan/gecikme/hatırlatma hesapları
 * bu gösterim çevriminden etkilenmez; yalnız duvar saati doğru görünür.
 *
 * Not: app.timezone bir gün Europe/Istanbul olursa çevrim no-op olur (şube tz
 * = app tz) ve davranış aynı kalır — ileriye dönük güvenli.
 */
class BranchLocalDateTime implements CastsAttributes
{
    /** @var array<int, string> branch_id → timezone önbelleği (istek başına) */
    private static array $tzCache = [];

    /**
     * @param  array<string, mixed>  $attributes
     */
    public function get(Model $model, string $key, mixed $value, array $attributes): ?Carbon
    {
        if ($value === null) {
            return null;
        }

        return Carbon::parse((string) $value, config('app.timezone'))
            ->setTimezone($this->branchTimezone($model));
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    public function set(Model $model, string $key, mixed $value, array $attributes): ?string
    {
        if ($value === null) {
            return null;
        }

        $dt = $value instanceof \DateTimeInterface
            ? Carbon::instance(\DateTimeImmutable::createFromInterface($value))
            : Carbon::parse((string) $value, $this->branchTimezone($model));

        // Her zaman app.timezone (UTC) olarak SAKLA — tek referans çerçevesi.
        return $dt->copy()->setTimezone(config('app.timezone'))->format('Y-m-d H:i:s');
    }

    private function branchTimezone(Model $model): string
    {
        $branchId = (int) ($model->getAttribute('branch_id') ?? 0);
        $appTz = (string) config('app.timezone');

        if ($branchId <= 0) {
            return $appTz;
        }

        return self::$tzCache[$branchId] ??= (string) (
            Branch::query()->withoutGlobalScopes()->whereKey($branchId)->value('timezone') ?: $appTz
        );
    }
}
