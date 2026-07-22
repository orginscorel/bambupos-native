<?php

namespace App\Modules\Kds\Services;

use App\Modules\Kds\Models\Station;
use Illuminate\Support\Collection;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * İstasyon kataloğu: YERLEŞİK istasyonlar (config/kds.php) + işletmenin
 * KENDİ istasyonları (kds_stations, tenant-scope'lu) tek listede.
 *
 * Ürün kartındaki `station` ve kalemdeki snapshot bu anahtarlarla eşleşir.
 */
class StationRegistry
{
    /**
     * Tüm istasyonlar (yerleşik + özel).
     *
     * @return Collection<int, array{key: string, name: string, is_builtin: bool, is_active: bool, sort_order: int, id: int|null}>
     */
    public function all(bool $activeOnly = true): Collection
    {
        $builtins = collect(config('kds.builtin_stations', []))->values()->map(fn (array $s, int $i): array => [
            'id' => null,
            'key' => $s['key'],
            'name' => $s['name'],
            'is_builtin' => true,
            'is_active' => true,
            'sort_order' => $i,
        ]);

        $custom = Station::query()
            ->when($activeOnly, fn ($q) => $q->where('is_active', true))
            ->orderBy('sort_order')->orderBy('id')
            ->get()
            ->map(fn (Station $s): array => [
                'id' => $s->id,
                'key' => $s->key,
                'name' => $s->name,
                'is_builtin' => false,
                'is_active' => (bool) $s->is_active,
                'sort_order' => 100 + (int) $s->sort_order,
            ]);

        return $builtins->concat($custom)->values();
    }

    /** Geçerli istasyon anahtarı mı (yerleşik ya da bu kiracının özel tanımı)? */
    public function isValid(?string $key): bool
    {
        if ($key === null || $key === '') {
            return false;
        }

        return $this->all(activeOnly: false)->contains(fn (array $s): bool => $s['key'] === $key);
    }

    public function labelFor(?string $key): ?string
    {
        if ($key === null || $key === '') {
            return null;
        }

        $found = $this->all(activeOnly: false)->first(fn (array $s): bool => $s['key'] === $key);

        return $found['name'] ?? $key;
    }

    /**
     * Ürün formu / süzgeçler için seçenek listesi.
     *
     * @return array<int, array{value: string, label: string}>
     */
    public function options(): array
    {
        return $this->all()
            ->map(fn (array $s): array => ['value' => $s['key'], 'label' => $s['name']])
            ->all();
    }

    /** Özel istasyon oluşturma — anahtar addan türetilir, çakışma reddedilir. */
    public function create(string $name, int $sortOrder = 0): Station
    {
        $key = $this->uniqueKeyFor($name);

        return Station::query()->create([
            'key' => $key,
            'name' => $name,
            'sort_order' => $sortOrder,
            'is_active' => true,
        ]);
    }

    private function uniqueKeyFor(string $name): string
    {
        $base = Str::slug($name, '_');

        if ($base === '' || Str::startsWith($base, '_')) {
            throw ValidationException::withMessages(['name' => ['İstasyon adı anahtara çevrilemedi.']]);
        }

        $base = Str::limit($base, 32, '');
        $key = $base;
        $i = 2;

        while ($this->isValid($key)) {
            $key = $base.'_'.$i;
            $i++;

            if ($i > 50) {
                throw ValidationException::withMessages(['name' => ['Bu ada çok benzeyen istasyonlar zaten var.']]);
            }
        }

        return $key;
    }
}
