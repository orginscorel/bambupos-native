<?php

namespace Tests\Feature\Shifts;

use App\Modules\Identity\Models\AuditLog;
use App\Modules\Shifts\Models\ClockDevice;
use App\Modules\Shifts\Models\LocationConsent;
use App\Modules\Shifts\Models\ShiftSetting;
use App\Modules\Shifts\Models\TimeEntry;
use Illuminate\Support\Str;

/**
 * İşe giriş/çıkış: PIN eşleme, süre/mola/fazla mesai hesabı, geç kalma,
 * manuel düzeltme denetimi, KVKK konum kuralı, yetkili cihaz ucu.
 */
class TimeClockTest extends ShiftsTestCase
{
    public function test_pin_dogru_personeli_esler_ve_giris_acar(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $other = $this->addStaff($ctx);

        $this->setPin($staff, '246813');
        $this->setPin($other, '935172');

        $response = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => 'in',
            'pin' => '246813',
        ])->assertOk();

        // Mesai, oturum sahibine değil PIN sahibine yazılır.
        $this->assertSame($staff->id, $response->json('user.id'));
        $this->assertSame('working', $response->json('state.status'));
        $this->assertDatabaseHas('time_entries', [
            'user_id' => $staff->id,
            'status' => 'open',
            'method_in' => 'pin',
        ]);
    }

    public function test_yanlis_pin_reddedilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => 'in',
            'pin' => '999999',
        ])->assertStatus(422);

        $this->assertDatabaseCount('time_entries', 0);
    }

    public function test_ayni_pin_iki_personelde_ise_personel_kodu_istenir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff1 = $this->addStaff($ctx, ['catalog.view'], ['staff_code' => 'P-100']);
        $staff2 = $this->addStaff($ctx, ['catalog.view'], ['staff_code' => 'P-200']);

        $this->setPin($staff1, '246813');
        $this->setPin($staff2, '246813');

        // Kod olmadan: belirsiz → 422
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => 'in',
            'pin' => '246813',
        ])->assertStatus(422)->assertJsonValidationErrors(['staff_code']);

        // Kodla: doğru kişi
        $response = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => 'in',
            'pin' => '246813',
            'staff_code' => 'P-200',
        ])->assertOk();

        $this->assertSame($staff2->id, $response->json('user.id'));
    }

    public function test_baska_kiracinin_pini_bu_kiracida_calismaz(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $staffB = $this->addStaff($b);
        $this->setPin($staffB, '246813');

        $this->actingAs($a['user'])->postJson('/api/v1/shifts/clock', [
            'action' => 'in',
            'pin' => '246813',
        ])->assertStatus(422);
    }

    public function test_mesai_suresi_mola_dusulur_ve_fazla_mesai_hesaplanir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        // 09:00-17:00 vardiya, 60 dk planlı mola → plan 420 dk
        $today = now()->format('Y-m-d');
        $this->travelTo("{$today} 09:00:00");
        $this->makeShift($ctx, $staff, "{$today} 09:00:00", "{$today} 17:00:00", ['break_min' => 60]);

        $clock = fn (string $action) => $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => $action,
            'pin' => '246813',
        ]);

        $clock('in')->assertOk();

        $this->travelTo("{$today} 12:00:00");
        $clock('break_start')->assertOk();

        $this->travelTo("{$today} 12:30:00");
        $clock('break_end')->assertOk();

        // 19:00'da çıkış: brüt 600 dk − 30 dk mola = 570 dk çalışma;
        // plan 420 dk → fazla mesai 150 dk.
        $this->travelTo("{$today} 19:00:00");
        $response = $clock('out')->assertOk();

        $entry = $response->json('entry');
        $this->assertSame(570, $entry['worked_min']);
        $this->assertSame(30, $entry['break_total_min']);
        $this->assertSame(150, $entry['overtime_min']);
        $this->assertSame(0, $entry['late_min']);
        $this->assertSame(0, $entry['early_leave_min']);
    }

    public function test_gec_kalma_ve_erken_cikis_toleransla_hesaplanir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $today = now()->format('Y-m-d');
        $this->makeShift($ctx, $staff, "{$today} 09:00:00", "{$today} 17:00:00");

        $clock = fn (string $action) => $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => $action,
            'pin' => '246813',
        ]);

        // 09:20 giriş (tolerans 5 dk → 20 dk geç), 16:30 çıkış (30 dk erken)
        $this->travelTo("{$today} 09:20:00");
        $clock('in')->assertOk();

        $this->travelTo("{$today} 16:30:00");
        $entry = $clock('out')->assertOk()->json('entry');

        $this->assertSame(20, $entry['late_min']);
        $this->assertSame(30, $entry['early_leave_min']);
        $this->assertSame(430, $entry['worked_min']); // 7 sa 10 dk
        $this->assertSame(50, TimeEntry::withoutTenancy()->find($entry['id'])->missing_min); // eksik çalışma
    }

    public function test_manuel_duzeltme_neden_ister_ve_denetim_kaydina_duser(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $today = now()->format('Y-m-d');
        $this->travelTo("{$today} 09:00:00");
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'in', 'pin' => '246813'])->assertOk();
        $this->travelTo("{$today} 17:00:00");
        $entryId = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'out', 'pin' => '246813'])
            ->json('entry.id');

        // Neden olmadan reddedilir
        $this->actingAs($ctx['user'])->putJson("/api/v1/shifts/time-entries/{$entryId}", [
            'clock_out_at' => "{$today} 18:00:00",
        ])->assertStatus(422);

        // Sınırlı personel düzeltemez
        $this->actingAs($staff)->putJson("/api/v1/shifts/time-entries/{$entryId}", [
            'clock_out_at' => "{$today} 18:00:00",
            'reason' => 'Çıkış unutuldu',
        ])->assertForbidden();

        // Yönetici nedenle düzeltir
        $this->actingAs($ctx['user'])->putJson("/api/v1/shifts/time-entries/{$entryId}", [
            'clock_out_at' => "{$today} 18:00:00",
            'reason' => 'Çıkış unutuldu',
        ])->assertOk();

        $entry = TimeEntry::withoutTenancy()->find($entryId);
        $this->assertSame(540, $entry->worked_min);
        $this->assertSame('Çıkış unutuldu', $entry->edit_reason);
        $this->assertSame($ctx['user']->id, (int) $entry->edited_by_id);

        // Denetim kaydı: eski/yeni değerler + neden
        $log = AuditLog::withoutTenancy()
            ->where('action', 'shifts.time_entry_corrected')
            ->where('entity_id', $entryId)
            ->latest('id')
            ->first();

        $this->assertNotNull($log);
        $this->assertSame($ctx['user']->id, $log->user_id);
        $this->assertSame('Çıkış unutuldu', $log->new_values['reason']);
    }

    public function test_kvkk_konum_varsayilan_saklanmaz_riza_ve_ayarla_saklanir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $payload = ['action' => 'in', 'pin' => '246813', 'lat' => 41.01, 'lng' => 28.97];

        // 1) Varsayılan: işletme ayarı KAPALI → koordinat gelse bile saklanmaz
        $entryId = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', $payload)->json('entry.id');
        $this->assertNull(TimeEntry::withoutTenancy()->find($entryId)->lat_in);
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'out', 'pin' => '246813']);

        // 2) Ayar açık ama personel RIZASI YOK → yine saklanmaz
        $this->asTenant($ctx['tenant'], function (): void {
            $s = ShiftSetting::current();
            $s->location_tracking_enabled = true;
            $s->location_policy = 'Konum verisi yalnız mesai doğrulaması için işlenir.';
            $s->save();
        });

        $entryId = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', $payload)->json('entry.id');
        $this->assertNull(TimeEntry::withoutTenancy()->find($entryId)->lat_in);
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'out', 'pin' => '246813']);

        // 3) Personel açık rıza verir → artık saklanır
        $this->actingAs($staff)->postJson('/api/v1/shifts/location-consent')->assertOk();
        $this->assertTrue($this->asTenant($ctx['tenant'], fn () => LocationConsent::activeFor($staff->id)));

        $entryId = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', $payload)->json('entry.id');
        $this->assertEqualsWithDelta(41.01, TimeEntry::withoutTenancy()->find($entryId)->lat_in, 0.0001);
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'out', 'pin' => '246813']);

        // 4) Rıza geri çekilir → tekrar saklanmaz
        $this->actingAs($staff)->deleteJson('/api/v1/shifts/location-consent')->assertOk();

        $entryId = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', $payload)->json('entry.id');
        $this->assertNull(TimeEntry::withoutTenancy()->find($entryId)->lat_in);
    }

    public function test_yetkili_cihaz_token_ile_oturumsuz_giris_yapilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $token = Str::random(40);
        $this->asTenant($ctx['tenant'], function () use ($ctx, $token): void {
            $device = new ClockDevice(['name' => 'Mutfak Tableti', 'branch_id' => $ctx['branch']->id, 'is_active' => true]);
            $device->token_hash = ClockDevice::hashToken($token);
            $device->save();
        });

        // Geçersiz token → 401
        $this->postJson('/api/v1/shifts/device-clock', ['action' => 'in', 'pin' => '246813'], [
            'X-Device-Token' => 'yanlis-token',
        ])->assertUnauthorized();

        // Geçerli token → giriş açılır, yöntem 'device', şube cihazdan gelir
        $response = $this->postJson('/api/v1/shifts/device-clock', ['action' => 'in', 'pin' => '246813'], [
            'X-Device-Token' => $token,
        ])->assertOk();

        $this->assertSame($staff->id, $response->json('user.id'));
        $this->assertDatabaseHas('time_entries', [
            'user_id' => $staff->id,
            'method_in' => 'device',
            'branch_id' => $ctx['branch']->id,
        ]);
    }

    public function test_acik_kayit_yokken_cikis_reddedilir_ve_cift_giris_engellenir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $clock = fn (string $action) => $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', [
            'action' => $action,
            'pin' => '246813',
        ]);

        $clock('out')->assertStatus(422);
        $clock('in')->assertOk();
        $clock('in')->assertStatus(422); // çift giriş yok
    }
}
