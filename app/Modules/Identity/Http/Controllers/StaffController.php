<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Identity\Services\StaffService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class StaffController extends Controller
{
    public function __construct(
        private readonly StaffService $staff,
        private readonly AuditLogger $audit,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', User::class);

        // Katman 4: liste daima servis-tarafı kiracı süzgeciyle.
        $staff = User::ofCurrentTenant()
            ->with('roles:id,name')
            ->orderBy('first_name')
            ->paginate(50);

        return response()->json($staff);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', User::class);

        $tenantId = $request->user()->tenant_id;

        $data = $request->validate([
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'email' => [
                'required', 'email',
                Rule::unique('users')->where('tenant_id', $tenantId),
            ],
            'phone' => ['nullable', 'string', 'max:32'],
            'staff_code' => [
                'nullable', 'string', 'max:32',
                Rule::unique('users')->where('tenant_id', $tenantId),
            ],
            'department' => ['nullable', 'string', 'max:100'],
            'position' => ['nullable', 'string', 'max:100'],
            'hired_at' => ['nullable', 'date'],
            'password' => ['required', 'string', \Illuminate\Validation\Rules\Password::min(10)],
            'branch_id' => ['nullable', 'integer'],
            'roles' => ['sometimes', 'array'],
            'roles.*' => ['integer'],
        ]);

        $roleIds = $data['roles'] ?? [];
        $branchId = $data['branch_id'] ?? null;
        unset($data['roles'], $data['branch_id']);

        $user = $this->staff->create($data, $branchId, $roleIds);

        return response()->json(['user' => $user->only(['id', 'name', 'email', 'staff_code'])], 201);
    }

    public function show(Request $request, User $staff): JsonResponse
    {
        $this->authorize('view', $staff);

        return response()->json(['user' => $staff->load('roles:id,name')]);
    }

    public function update(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $data = $request->validate([
            'first_name' => ['sometimes', 'string', 'max:100'],
            'last_name' => ['sometimes', 'string', 'max:100'],
            'phone' => ['nullable', 'string', 'max:32'],
            'department' => ['nullable', 'string', 'max:100'],
            'position' => ['nullable', 'string', 'max:100'],
            'hired_at' => ['nullable', 'date'],
            'is_active' => ['sometimes', 'boolean'],
            'branch_id' => ['nullable', 'integer'],
            'roles' => ['sometimes', 'array'],
            'roles.*' => ['integer'],
        ]);

        $roleIds = array_key_exists('roles', $data) ? $data['roles'] : null;
        $branchId = $data['branch_id'] ?? null;
        unset($data['roles'], $data['branch_id']);

        $user = $this->staff->update($staff, $data, $branchId, $roleIds);

        return response()->json(['user' => $user->fresh()->load('roles:id,name')]);
    }

    public function destroy(Request $request, User $staff): JsonResponse
    {
        $this->authorize('delete', $staff);

        $this->audit->log('staff.deleted', $staff, $staff->only(['first_name', 'last_name', 'email', 'staff_code']), null);

        $staff->roles()->detach();
        $staff->delete();

        return response()->json(['ok' => true]);
    }
}
