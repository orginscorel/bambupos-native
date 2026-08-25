<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Enums\TableShape;
use App\Modules\Venue\Enums\TableStatus;
use App\Modules\Venue\Models\Area;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Masa yönetimi (Faz-2): zengin liste + tekil/toplu oluşturma + durum +
 * toplu işlemler. Tüm sorgular tenant-scope'lu; yabancı kayıt 404/etkisiz.
 */
class VenueTableController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Table::class);

        // ŞUBE KAPSAMI: yalnız geçerli şubenin masaları.
        $query = Table::query()->with(['area:id,name,floor_id', 'area.floor:id,name', 'branch:id,name'])
            ->where('branch_id', $this->currentBranchId());

        if ($request->filled('area_id')) {
            $request->query('area_id') === 'none'
                ? $query->whereNull('area_id')
                : $query->where('area_id', (int) $request->query('area_id'));
        }

        if ($request->filled('status')) {
            $query->where('status', (string) $request->query('status'));
        }

        if ($request->filled('active')) {
            $query->where('is_active', $request->boolean('active'));
        }

        if ($request->filled('q')) {
            $q = (string) $request->query('q');
            $query->where(function ($sub) use ($q): void {
                $sub->where('name', 'like', "%{$q}%");

                if (ctype_digit($q)) {
                    $sub->orWhere('number', (int) $q);
                }
            });
        }

        $tables = $query->orderBy('branch_id')->orderBy('number')->orderBy('name')
            ->paginate(min((int) $request->query('per_page', 50), 200));

        $tables->getCollection()->transform(fn (Table $table): array => $this->present($table));

        return response()->json(['tables' => $tables]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Table::class);

        $data = $request->validate([
            // Şube bağlamdan gelir (ScopesToBranch); istekteki değer yok sayılır.
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'area_id' => ['nullable', 'integer'],
            'name' => ['required', 'string', 'max:100'],
            'number' => ['nullable', 'integer', 'min:1', 'max:999999'],
            'capacity' => ['sometimes', 'integer', 'min:1', 'max:200'],
            'shape' => ['sometimes', Rule::enum(TableShape::class)],
            'is_joinable' => ['sometimes', 'boolean'],
            'notes' => ['nullable', 'string', 'max:255'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        // ŞUBE KAPSAMI: masa DAİMA geçerli şubede oluşturulur.
        $data['branch_id'] = $this->currentBranchId();
        $branch = $this->resolveBranch((int) $data['branch_id']);
        $areaId = $this->resolveAreaId($data['area_id'] ?? null, (int) $branch->id);

        $number = $data['number'] ?? $this->nextNumber((int) $branch->id);
        $this->assertAvailable((int) $branch->id, [$data['name']], [$number]);

        $table = new Table([
            'name' => $data['name'],
            'number' => $number,
            'capacity' => $data['capacity'] ?? 4,
            'shape' => $data['shape'] ?? TableShape::Square->value,
            'is_joinable' => $data['is_joinable'] ?? true,
            'notes' => $data['notes'] ?? null,
            'is_active' => $data['is_active'] ?? true,
        ]);
        $table->branch_id = $branch->id;
        $table->area_id = $areaId;
        $table->save(); // qr_token otomatik (ADR-008)

        return response()->json(['table' => $this->present($table->fresh(['area.floor', 'branch']))], 201);
    }

    /**
     * Toplu oluşturma: "Teras 1-20" → ad = "{önek} {n}", masa no = n.
     * Ya hepsi ya hiçbiri (transaction); çakışan ad/no 422 ile listelenir.
     */
    public function bulkStore(Request $request): JsonResponse
    {
        $this->authorize('create', Table::class);

        $data = $request->validate([
            // Şube bağlamdan gelir (ScopesToBranch); istekteki değer yok sayılır.
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'area_id' => ['nullable', 'integer'],
            'name_prefix' => ['required', 'string', 'max:80'],
            'start' => ['required', 'integer', 'min:1', 'max:999999'],
            'end' => ['required', 'integer', 'min:1', 'max:999999', 'gte:start'],
            'capacity' => ['sometimes', 'integer', 'min:1', 'max:200'],
            'shape' => ['sometimes', Rule::enum(TableShape::class)],
            'is_joinable' => ['sometimes', 'boolean'],
        ]);

        if ($data['end'] - $data['start'] + 1 > 200) {
            throw ValidationException::withMessages(['end' => ['Tek seferde en fazla 200 masa oluşturulabilir.']]);
        }

        // ŞUBE KAPSAMI: toplu masa DAİMA geçerli şubede oluşturulur.
        $data['branch_id'] = $this->currentBranchId();
        $branch = $this->resolveBranch((int) $data['branch_id']);
        $areaId = $this->resolveAreaId($data['area_id'] ?? null, (int) $branch->id);

        $prefix = trim($data['name_prefix']);
        $numbers = range((int) $data['start'], (int) $data['end']);
        $names = array_map(fn (int $n): string => "{$prefix} {$n}", $numbers);

        $this->assertAvailable((int) $branch->id, $names, $numbers);

        $created = DB::transaction(function () use ($branch, $areaId, $prefix, $numbers, $data): array {
            $ids = [];

            foreach ($numbers as $n) {
                $table = new Table([
                    'name' => "{$prefix} {$n}",
                    'number' => $n,
                    'capacity' => $data['capacity'] ?? 4,
                    'shape' => $data['shape'] ?? TableShape::Square->value,
                    'is_joinable' => $data['is_joinable'] ?? true,
                ]);
                $table->branch_id = $branch->id;
                $table->area_id = $areaId;
                $table->save();

                $ids[] = $table->id;
            }

            return $ids;
        });

        return response()->json(['created_count' => count($created), 'table_ids' => $created], 201);
    }

    /**
     * Masa META verisini günceller (ad/no/kapasite/şekil/alan/not/birleştirilebilirlik).
     *
     * KASITLI OLARAK `status` kabul ETMEZ (denetim BLOKER #1): durum geçişleri
     * yalnız açık-adisyon korumalı {@see updateStatus()} ucundan yapılır — aksi
     * halde bu genel-amaçlı uç üzerinden dolu bir masa manuel olarak boşa
     * çekilebilir ve TableStatusSynchronizer'ın koruduğu masa↔adisyon senkronu
     * bozulup aktif adisyon panodan "kaybolabilirdi".
     */
    public function update(Request $request, Table $table): JsonResponse
    {
        $this->authorize('update', $table);

        $data = $request->validate([
            'area_id' => ['sometimes', 'nullable', 'integer'],
            'name' => ['sometimes', 'string', 'max:100'],
            'number' => ['sometimes', 'integer', 'min:1', 'max:999999'],
            'capacity' => ['sometimes', 'integer', 'min:1', 'max:200'],
            'shape' => ['sometimes', Rule::enum(TableShape::class)],
            'is_joinable' => ['sometimes', 'boolean'],
            'notes' => ['nullable', 'string', 'max:255'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (isset($data['name']) && $data['name'] !== $table->name) {
            $this->assertAvailable((int) $table->branch_id, [$data['name']], [], $table->id);
        }

        if (isset($data['number']) && (int) $data['number'] !== (int) $table->number) {
            $this->assertAvailable((int) $table->branch_id, [], [(int) $data['number']], $table->id);
        }

        // AÇIK ADİSYON KORUMASI (denetim #2/YÜKSEK): deaktivasyon masayı ops
        // panosundan (is_active=true filtresi) tamamen düşürür; açık adisyonu
        // varken masa "kaybolmasın".
        if (($data['is_active'] ?? true) === false && $this->tableHasOpenOrder($table)) {
            throw ValidationException::withMessages([
                'is_active' => ['Masada açık adisyon var; masa pasifleştirilemez. Önce adisyonu kapatın (ödeme/iptal).'],
            ]);
        }

        if (array_key_exists('area_id', $data)) {
            $table->area_id = $this->resolveAreaId($data['area_id'], (int) $table->branch_id);
            unset($data['area_id']);
        }

        $table->fill($data);
        $table->save();

        return response()->json(['table' => $this->present($table->fresh(['area.floor', 'branch']))]);
    }

    /** Yalnız durum değişikliği (geçiş kuralları sipariş fazında bağlanacak). */
    public function updateStatus(Request $request, Table $table): JsonResponse
    {
        $this->authorize('update', $table);

        $data = $request->validate(['status' => ['required', Rule::enum(TableStatus::class)]]);

        // AÇIK ADİSYON KORUMASI (denetim #11): masada açık adisyon varken masayı
        // "boş/rezerve/servis dışı/temizlik"e ELLE çekmek masa↔adisyon senkronunu
        // bozar (aktif adisyon panoda kaybolur). Bu durumları engelle; masa durumu
        // adisyon kapandığında (ödeme/iptal) otomatik güncellenir.
        if ($this->freesTable(TableStatus::from($data['status'])) && $this->tableHasOpenOrder($table)) {
            throw ValidationException::withMessages([
                'status' => ['Masada açık adisyon var; durumu elle değiştiremezsiniz. Önce adisyonu kapatın (ödeme/iptal).'],
            ]);
        }

        $table->update(['status' => $data['status']]);

        return response()->json(['table' => $this->present($table->fresh(['area.floor', 'branch']))]);
    }

    /** Masayı "boş bırakan" durumlar — açık adisyon varken elle seçilemez. */
    private function freesTable(TableStatus $status): bool
    {
        return in_array($status, [
            TableStatus::Available,
            TableStatus::Reserved,
            TableStatus::ReservationLate,
            TableStatus::Cleaning,
            TableStatus::OutOfService,
        ], true);
    }

    /** Masada kapanmamış (açık/tahsilat fazında) adisyon var mı? */
    private function tableHasOpenOrder(Table $table): bool
    {
        return Order::query()
            ->where('table_id', $table->getKey())
            ->whereNotIn('status', OrderStatus::closedValues())
            ->exists();
    }

    /**
     * Toplu işlem. Yabancı kiracının id'leri scope'a takılır ve etkisizdir.
     */
    public function bulkAction(Request $request): JsonResponse
    {
        $data = $request->validate([
            'table_ids' => ['required', 'array', 'min:1', 'max:500'],
            'table_ids.*' => ['integer'],
            'action' => ['required', Rule::in(['activate', 'deactivate', 'delete', 'set_status', 'set_area'])],
            'status' => ['required_if:action,set_status', Rule::enum(TableStatus::class)],
            'area_id' => ['nullable', 'integer'],
        ]);

        $tables = Table::query()->whereIn('id', $data['table_ids'])->get();

        if ($tables->isEmpty()) {
            return response()->json(['affected' => 0]);
        }

        foreach ($tables as $table) {
            $this->authorize($data['action'] === 'delete' ? 'delete' : 'update', $table);
        }

        $affected = 0;
        $skippedOpenOrder = [];

        DB::transaction(function () use ($tables, $data, &$affected, &$skippedOpenOrder): void {
            foreach ($tables as $table) {
                switch ($data['action']) {
                    case 'activate':
                        $table->update(['is_active' => true]);
                        break;
                    case 'deactivate':
                        // Denetim #2/YÜKSEK: açık adisyonlu masa deaktive edilirse
                        // OrderController::board() `is_active=true` filtresiyle onu
                        // hiç göstermez → ödenmemiş sipariş yönetilemez hale gelir.
                        if ($this->tableHasOpenOrder($table)) {
                            $skippedOpenOrder[] = $table->id;
                            continue 2; // bu masayı atla (affected artmaz)
                        }
                        $table->update(['is_active' => false]);
                        break;
                    case 'delete':
                        // Denetim #2/YÜKSEK: aynı guard silme için de geçerli — aksi
                        // halde tekli silme (destroy) yerine toplu silme bypass olurdu.
                        if ($this->tableHasOpenOrder($table)) {
                            $skippedOpenOrder[] = $table->id;
                            continue 2;
                        }
                        $table->delete();
                        break;
                    case 'set_status':
                        // Denetim #11: açık adisyonlu masayı toplu işlemle de boşa çekme.
                        if ($this->freesTable(TableStatus::from($data['status'])) && $this->tableHasOpenOrder($table)) {
                            $skippedOpenOrder[] = $table->id;
                            continue 2; // bu masayı atla (affected artmaz)
                        }
                        $table->update(['status' => $data['status']]);
                        break;
                    case 'set_area':
                        $table->area_id = $this->resolveAreaId($data['area_id'] ?? null, (int) $table->branch_id);
                        $table->save();
                        break;
                }

                $affected++;
            }
        });

        // "Net hata" (denetim #2): kaç masanın açık adisyon nedeniyle atlandığı
        // yanıtta açıkça döner; arayüz bunu ayrı bir uyarıda gösterebilir.
        return response()->json([
            'affected' => $affected,
            'skipped_open_order_ids' => $skippedOpenOrder,
        ]);
    }

    public function destroy(Request $request, Table $table): JsonResponse
    {
        $this->authorize('delete', $table);

        // AÇIK ADİSYON KORUMASI (denetim #2/YÜKSEK): tekli silme de bulkAction'daki
        // guard'ın aynısını taşımalı — aksi halde masalar teker teker silinerek
        // toplu-işlem koruması bypass edilebilirdi. service_requests.table_id
        // cascadeOnDelete olduğundan silme, o masaya ait bekleyen "garson çağır"
        // isteklerini de sessizce siler; açık adisyon varken buna izin verme.
        if ($this->tableHasOpenOrder($table)) {
            throw ValidationException::withMessages([
                'table' => ['Masada açık adisyon var; masa silinemez. Önce adisyonu kapatın (ödeme/iptal).'],
            ]);
        }

        $table->delete();

        return response()->json(['ok' => true]);
    }

    /** @return array<string, mixed> */
    private function present(Table $table): array
    {
        $status = $table->status instanceof TableStatus
            ? $table->status
            : TableStatus::tryFrom((string) $table->status) ?? TableStatus::Available;

        $shape = TableShape::tryFrom((string) $table->shape) ?? TableShape::Square;

        return [
            'id' => $table->id,
            'branch_id' => $table->branch_id,
            'branch_name' => $table->branch?->name,
            'area_id' => $table->area_id,
            'area_name' => $table->area?->name,
            'floor_name' => $table->area?->floor?->name,
            'name' => $table->name,
            'number' => $table->number,
            'capacity' => $table->capacity,
            'shape' => $shape->value,
            'shape_label' => $shape->label(),
            'status' => $status->value,
            'status_label' => $status->label(),
            'status_icon' => $status->icon(),
            'status_variant' => $status->variant(),
            'is_joinable' => $table->is_joinable,
            'notes' => $table->notes,
            'is_active' => $table->is_active,
            'menu_url' => $table->menuUrl(),
            'qr_rotated_at' => $table->qr_rotated_at?->toIso8601String(),
        ];
    }

    private function resolveBranch(int $branchId): Branch
    {
        $branch = Branch::query()->find($branchId); // scoped: yabancı şube çözülmez

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        return $branch;
    }

    /** Alan, aynı kiracının aynı şubesine ait olmalı. */
    private function resolveAreaId(mixed $areaId, int $branchId): ?int
    {
        if ($areaId === null || $areaId === '') {
            return null;
        }

        $area = Area::query()->where('branch_id', $branchId)->find((int) $areaId);

        if ($area === null) {
            throw ValidationException::withMessages(['area_id' => ['Alan bu şubede bulunamadı.']]);
        }

        return (int) $area->id;
    }

    private function nextNumber(int $branchId): int
    {
        return (int) Table::query()->where('branch_id', $branchId)->max('number') + 1;
    }

    /**
     * Ad ve masa no şube içinde tekildir; çakışanlar 422 ile listelenir.
     *
     * @param  array<int, string>  $names
     * @param  array<int, int>  $numbers
     */
    private function assertAvailable(int $branchId, array $names, array $numbers, ?int $ignoreId = null): void
    {
        $errors = [];

        if ($names !== []) {
            $taken = Table::query()->where('branch_id', $branchId)
                ->whereIn('name', $names)
                ->when($ignoreId !== null, fn ($q) => $q->whereKeyNot($ignoreId))
                ->pluck('name');

            if ($taken->isNotEmpty()) {
                $errors['name_prefix'] = ['Şu adlar bu şubede zaten kullanılıyor: '.$taken->implode(', ')];
                $errors['name'] = $errors['name_prefix'];
            }
        }

        if ($numbers !== []) {
            $taken = Table::query()->where('branch_id', $branchId)
                ->whereIn('number', $numbers)
                ->when($ignoreId !== null, fn ($q) => $q->whereKeyNot($ignoreId))
                ->pluck('number');

            if ($taken->isNotEmpty()) {
                $errors['number'] = ['Şu masa numaraları bu şubede zaten kullanılıyor: '.$taken->implode(', ')];
            }
        }

        if ($errors !== []) {
            throw ValidationException::withMessages($errors);
        }
    }
}
