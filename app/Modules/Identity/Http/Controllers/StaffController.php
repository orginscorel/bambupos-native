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
        // §13: gizli terminal kullanıcıları (is_terminal) personel listesinde
        // GÖRÜNMEZ — bunlar cihaz hesabıdır, insan personel değildir.
        $query = User::ofCurrentTenant()
            ->where('is_terminal', false)
            ->with(['roles:id,name,is_system', 'branch:id,name'])
            ->withCount('personalPermissions as personal_overrides_count');

        // Arama: ad / e-posta / personel kodu / telefon
        if (($q = trim((string) $request->query('q', ''))) !== '') {
            $query->where(function ($w) use ($q): void {
                $w->where('name', 'like', "%{$q}%")
                    ->orWhere('email', 'like', "%{$q}%")
                    ->orWhere('staff_code', 'like', "%{$q}%")
                    ->orWhere('phone', 'like', "%{$q}%");
            });
        }

        if (($branchId = (int) $request->query('branch_id', 0)) > 0) {
            $query->where('branch_id', $branchId);
        }

        if (($roleId = (int) $request->query('role_id', 0)) > 0) {
            $query->whereHas('roles', fn ($r) => $r->where('roles.id', $roleId));
        }

        $status = (string) $request->query('status', '');
        if ($status === 'active') {
            $query->where('is_active', true);
        } elseif ($status === 'passive') {
            $query->where('is_active', false);
        }

        $staff = $query->orderBy('first_name')->paginate(50);

        // pin_hash gizlidir; listeye yalnız var/yok bilgisi çıkar.
        $staff->getCollection()->transform(function (User $u): User {
            $u->setAttribute('has_pin', $u->pin_hash !== null);

            return $u;
        });

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
            'default_screen' => ['nullable', 'string', Rule::in(array_keys((array) config('authz.screens', [])))],
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
            'default_screen' => ['nullable', 'string', Rule::in(array_keys((array) config('authz.screens', [])))],
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
