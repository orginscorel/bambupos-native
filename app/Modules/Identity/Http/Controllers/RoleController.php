<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Services\RoleService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RoleController extends Controller
{
    public function __construct(private readonly RoleService $roles)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Role::class);

        // Role global scope'lu: yalnız bağlamdaki kiracının rolleri döner.
        return response()->json([
            'roles' => Role::query()->with('permissions:id,key,label')->orderBy('name')->get(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Role::class);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:500'],
            'permissions' => ['required', 'array', 'min:1'],
            'permissions.*' => ['integer'],
        ]);

        $role = $this->roles->create($request->user(), $data['name'], $data['description'] ?? null, $data['permissions']);

        return response()->json(['role' => $role->load('permissions:id,key')], 201);
    }

    public function show(Request $request, Role $role): JsonResponse
    {
        $this->authorize('view', $role);

        return response()->json(['role' => $role->load('permissions:id,key,label')]);
    }

    public function update(Request $request, Role $role): JsonResponse
    {
        $this->authorize('update', $role);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:500'],
            'permissions' => ['sometimes', 'array'],
            'permissions.*' => ['integer'],
        ]);

        $permissionIds = array_key_exists('permissions', $data) ? $data['permissions'] : null;
        unset($data['permissions']);

        $role = $this->roles->update($request->user(), $role, $data, $permissionIds);

        return response()->json(['role' => $role->fresh()->load('permissions:id,key')]);
    }

    public function destroy(Request $request, Role $role): JsonResponse
    {
        $this->authorize('delete', $role);

        $this->roles->delete($role);

        return response()->json(['ok' => true]);
    }
}
