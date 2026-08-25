<?php

declare(strict_types=1);

namespace Tests\Feature\StaffTasks;

/**
 * Görev akışı: yönetici atama yetkisi + portal self-servis durum makinesi
 * (sahiplik + ileri-geçiş kuralı).
 */
class StaffTaskFlowTest extends StaffTasksTestCase
{
    public function test_yonetici_gorev_atama_tasks_assign_ister(): void
    {
        // İki kiracıyı da HTTP isteklerinden ÖNCE kur (istek sonrası kiracı
        // bağlamı set kalır; sonradan branch üretimi guard'a takılır).
        $ctx = $this->makeTenantWithUser(['tasks.view']);
        $staff = $this->addStaff($ctx);
        $ctx2 = $this->makeTenantWithUser();
        $staff2 = $this->addStaff($ctx2);

        // Yalnız tasks.view'lı yönetici atayamaz (yazma tasks.assign ister).
        $this->actingAs($ctx['user'])->postJson('/api/v1/tasks', [
            'assigned_to_id' => $staff->id,
            'title' => 'Depoyu say',
            'priority' => 'normal',
        ])->assertForbidden();

        // tasks.assign yetkili yönetici (tüm izinler) atayabilir.
        $this->actingAs($ctx2['user'])->postJson('/api/v1/tasks', [
            'assigned_to_id' => $staff2->id,
            'title' => 'Depoyu say',
            'priority' => 'normal',
        ])->assertCreated();

        $this->assertDatabaseHas('staff_tasks', [
            'assigned_to_id' => $staff2->id,
            'title' => 'Depoyu say',
            'status' => 'open',
        ]);
    }

    public function test_portal_baskasinin_gorevini_guncelleyemez_404(): void
    {
        $ctx = $this->makeTenantWithUser();
        $owner = $this->addStaff($ctx);
        $intruder = $this->addStaff($ctx);

        $task = $this->makeTask($ctx, $owner);

        // Başkasının görevi → sızıntısız 404.
        $this->actingAs($intruder)
            ->postJson($this->portalUrl("/api/v1/portal/tasks/{$task->id}/status"), ['status' => 'in_progress'])
            ->assertNotFound();

        $this->assertDatabaseHas('staff_tasks', ['id' => $task->id, 'status' => 'open']);
    }

    public function test_portal_tamamlanan_gorev_yeniden_acilamaz_422(): void
    {
        $ctx = $this->makeTenantWithUser();
        $owner = $this->addStaff($ctx);

        $task = $this->makeTask($ctx, $owner, ['status' => 'done', 'completed_at' => now()]);

        // done → in_progress geri alma yasak.
        $this->actingAs($owner)
            ->postJson($this->portalUrl("/api/v1/portal/tasks/{$task->id}/status"), ['status' => 'in_progress'])
            ->assertStatus(422);

        $this->assertDatabaseHas('staff_tasks', ['id' => $task->id, 'status' => 'done']);
    }

    public function test_portal_ileri_gecis_serbest(): void
    {
        $ctx = $this->makeTenantWithUser();
        $owner = $this->addStaff($ctx);

        $task = $this->makeTask($ctx, $owner);

        $this->actingAs($owner)
            ->postJson($this->portalUrl("/api/v1/portal/tasks/{$task->id}/status"), ['status' => 'done'])
            ->assertOk();

        $this->assertDatabaseHas('staff_tasks', ['id' => $task->id, 'status' => 'done']);
    }
}
