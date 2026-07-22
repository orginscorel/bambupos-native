<?php

namespace App\Modules\Tables\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class TableController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Table::class);

        return response()->json(['tables' => Table::query()->orderBy('name')->paginate(100)]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Table::class);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'branch_id' => ['required', 'integer'],
        ]);

        $branch = Branch::query()->find($data['branch_id']);

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $table = new Table(['name' => $data['name']]);
        $table->branch_id = $branch->id;
        $table->save(); // qr_token otomatik (ADR-008)

        return response()->json(['table' => $table], 201);
    }

    public function show(Request $request, Table $table): JsonResponse
    {
        $this->authorize('view', $table);

        return response()->json(['table' => $table]);
    }

    public function update(Request $request, Table $table): JsonResponse
    {
        $this->authorize('update', $table);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:100'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $table->update($data);

        return response()->json(['table' => $table]);
    }

    /** QR rotasyonu: eski token anında geçersiz (ADR-008). */
    public function rotateQr(Request $request, Table $table): JsonResponse
    {
        $this->authorize('update', $table);

        $table->rotateQrToken();

        return response()->json(['table' => $table->fresh()]);
    }

    public function destroy(Request $request, Table $table): JsonResponse
    {
        $this->authorize('delete', $table);

        $table->delete();

        return response()->json(['ok' => true]);
    }
}
