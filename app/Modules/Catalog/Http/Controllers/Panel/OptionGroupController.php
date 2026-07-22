<?php

namespace App\Modules\Catalog\Http\Controllers\Panel;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\OptionGroup;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/** Seçenek grubu + grup içi seçenekler (tek payload'da yönetilir). */
class OptionGroupController extends Controller
{
    public function page(): Response
    {
        $this->authorize('viewAny', OptionGroup::class);

        return Inertia::render('Panel/Catalog/Options/Index');
    }

    public function index(): JsonResponse
    {
        $this->authorize('viewAny', OptionGroup::class);

        $groups = OptionGroup::query()
            ->with('options')
            ->withCount('products')
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get();

        return response()->json(['option_groups' => $groups]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', OptionGroup::class);

        [$data, $options] = $this->validated($request);

        $group = DB::transaction(function () use ($data, $options) {
            $data['sort_order'] = ((int) OptionGroup::query()->max('sort_order')) + 10;
            $group = OptionGroup::query()->create($data);
            $this->syncOptions($group, $options);

            return $group;
        });

        return response()->json(['option_group' => $group->load('options')->loadCount('products')], 201);
    }

    public function update(Request $request, OptionGroup $optionGroup): JsonResponse
    {
        $this->authorize('update', $optionGroup);

        [$data, $options] = $this->validated($request);

        DB::transaction(function () use ($optionGroup, $data, $options): void {
            $optionGroup->update($data);
            $this->syncOptions($optionGroup, $options);
        });

        return response()->json(['option_group' => $optionGroup->fresh('options')->loadCount('products')]);
    }

    public function destroy(OptionGroup $optionGroup): JsonResponse
    {
        $this->authorize('delete', $optionGroup);

        $optionGroup->delete(); // pivot + seçenekler FK cascade

        return response()->json(['ok' => true]);
    }

    /** @return array{0: array<string, mixed>, 1: array<int, array<string, mixed>>|null} */
    private function validated(Request $request): array
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:500'],
            'selection_type' => ['required', Rule::in(OptionGroup::SELECTION_TYPES)],
            'is_required' => ['sometimes', 'boolean'],
            'min_select' => ['sometimes', 'integer', 'min:0', 'max:50'],
            'max_select' => ['nullable', 'integer', 'min:1', 'max:50'],
            'free_limit' => ['sometimes', 'integer', 'min:0', 'max:50'],
            'is_active' => ['sometimes', 'boolean'],

            'options' => ['sometimes', 'array', 'max:50'],
            'options.*.id' => ['nullable', 'integer'],
            'options.*.name' => ['required_with:options', 'string', 'max:150'],
            'options.*.price_minor' => ['required_with:options', 'integer', 'min:0', 'max:99999999999'],
            'options.*.is_default' => ['sometimes', 'boolean'],
            'options.*.is_active' => ['sometimes', 'boolean'],
        ]);

        if (($data['selection_type'] ?? '') === 'single') {
            $data['max_select'] = 1;
            $data['min_select'] = ! empty($data['is_required']) ? 1 : 0;
        }

        if (isset($data['min_select'], $data['max_select'])
            && $data['max_select'] !== null
            && (int) $data['max_select'] < (int) $data['min_select']) {
            throw ValidationException::withMessages([
                'max_select' => ['En fazla seçim, en az seçimden küçük olamaz.'],
            ]);
        }

        $options = $data['options'] ?? null;
        unset($data['options']);

        return [$data, $options];
    }

    /** @param array<int, array<string, mixed>>|null $options */
    private function syncOptions(OptionGroup $group, ?array $options): void
    {
        if (! is_array($options)) {
            return;
        }

        $keptIds = [];

        foreach (array_values($options) as $index => $row) {
            $attributes = [
                'name' => $row['name'],
                'price_minor' => (int) $row['price_minor'],
                'is_default' => (bool) ($row['is_default'] ?? false),
                'is_active' => (bool) ($row['is_active'] ?? true),
                'sort_order' => ($index + 1) * 10,
            ];

            $existing = ! empty($row['id'])
                ? $group->options()->whereKey((int) $row['id'])->first()
                : null;

            if ($existing !== null) {
                $existing->update($attributes);
                $keptIds[] = $existing->id;
            } else {
                $keptIds[] = $group->options()->create($attributes)->id;
            }
        }

        $group->options()->whereNotIn('id', $keptIds)->delete();
    }
}
