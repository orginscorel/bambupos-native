<?php

namespace App\Modules\Identity\Support;

/**
 * Rol şablonları (config/authz.php 'templates'):
 * seed + "Garson gibi başlat" akışının tek kaynağı.
 */
class RoleTemplates
{
    /**
     * @return array<string, array{name: string, description: string, system: bool, permissions: array<int, string>}>
     */
    public static function all(): array
    {
        $catalog = [];

        foreach ((array) config('authz.modules', []) as $module => $actions) {
            foreach ($actions as $action) {
                $catalog[] = "{$module}.{$action}";
            }
        }

        $result = [];

        foreach ((array) config('authz.templates', []) as $key => $template) {
            $keys = ($template['all'] ?? false)
                ? array_values(array_diff($catalog, $template['except'] ?? []))
                : array_values(array_intersect($template['permissions'] ?? [], $catalog));

            $result[$key] = [
                'name' => (string) $template['name'],
                'description' => (string) ($template['description'] ?? ''),
                'system' => (bool) ($template['system'] ?? false),
                'permissions' => $keys,
            ];
        }

        return $result;
    }

    /** @return array<int, string>|null şablonun izin anahtarları */
    public static function permissionKeys(string $key): ?array
    {
        return self::all()[$key]['permissions'] ?? null;
    }
}
