<?php

namespace Database\Seeders;

use App\Modules\Identity\Models\Permission;
use Illuminate\Database\Seeder;

/**
 * İzin kataloğunu config/authz.php'den senkronlar (idempotent).
 */
class PermissionSeeder extends Seeder
{
    public function run(): void
    {
        $labels = config('authz.labels', []);

        foreach (config('authz.modules', []) as $module => $actions) {
            foreach ($actions as $action) {
                Permission::query()->updateOrCreate(
                    ['key' => "{$module}.{$action}"],
                    [
                        'module' => $module,
                        'action' => $action,
                        'label' => $labels[$action] ?? ucfirst($action),
                    ],
                );
            }
        }
    }
}
