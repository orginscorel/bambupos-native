<script setup lang="ts">
/**
 * PATRON PANELİ · Görev Atama.
 * Patron/yönetici personele görev atar ve durumlarını izler. Mevcut yönetici
 * uçlarını kullanır (GET/POST /api/v1/tasks) — yetki: tasks.assign (backend).
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { usePermissions } from '@/composables/usePermissions';
import { useToast } from '@/composables/useToast';
import BossLayout from '@/Layouts/BossLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

interface StaffLite {
    id: number;
    name: string;
    position: string | null;
}
interface TaskDto {
    id: number;
    title: string;
    description: string | null;
    priority: 'low' | 'normal' | 'high';
    status: 'open' | 'in_progress' | 'done';
    due_at: string | null;
    assigned_to: { id: number; name: string; position: string | null } | null;
    created_at: string | null;
    completed_at: string | null;
}

const { success, danger } = useToast();
/* Yönetim izni (tasks.assign) — StaffTaskAdminController::store/update/destroy
 * backend'de abort_unless(tasks.assign) ile korunuyor ama liste ucu (index)
 * `can` alanı döndürmüyor; bu yüzden ortak izin okuyucusu (usePermissions,
 * auth.permissions) kullanılıyor — Boss/Index.vue'daki `can('boss.view')`
 * ile aynı desen. Görev atama formu yalnız bu izne sahip kullanıcıya
 * gösterilir; backend 403 koruması zaten mevcut, bu yalnız UX/tutarlılık. */
const { can } = usePermissions();
const canManage = computed(() => can('tasks.assign'));

const loading = ref(true);
const staff = ref<StaffLite[]>([]);
const tasks = ref<TaskDto[]>([]);

const form = reactive({
    assigned_to_id: '' as number | '',
    title: '',
    description: '',
    priority: 'normal' as 'low' | 'normal' | 'high',
    due_at: '',
});
const errors = ref<Record<string, string>>({});
const busy = ref(false);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<{ tasks: TaskDto[]; staff: StaffLite[] }>('/api/v1/tasks');
        tasks.value = res.tasks ?? [];
        staff.value = res.staff ?? [];
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}
onMounted(load);

const canSubmit = computed(() => form.assigned_to_id !== '' && form.title.trim().length > 0);

async function submit(): Promise<void> {
    if (busy.value || !canSubmit.value) return;
    busy.value = true;
    errors.value = {};
    try {
        await api('/api/v1/tasks', {
            method: 'POST',
            body: {
                assigned_to_id: form.assigned_to_id,
                title: form.title.trim(),
                description: form.description.trim() || null,
                priority: form.priority,
                due_at: form.due_at || null,
            },
        });
        const who = staff.value.find((s) => s.id === form.assigned_to_id)?.name ?? 'personel';
        success('Görev atandı', `${who} kişisine "${form.title.trim()}" görevi verildi.`);
        form.title = '';
        form.description = '';
        form.due_at = '';
        form.priority = 'normal';
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [k, v] of Object.entries(e.errors)) errors.value[k] = v[0];
            if (Object.keys(errors.value).length === 0) danger('Atanamadı', e.displayMessage);
        } else {
            danger('Atanamadı', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        busy.value = false;
    }
}

const openTasks = computed(() => tasks.value.filter((t) => t.status !== 'done'));
const doneTasks = computed(() => tasks.value.filter((t) => t.status === 'done'));

const PRIORITY_META: Record<string, { label: string; variant: 'neutral' | 'info' | 'warning' | 'danger' }> = {
    low: { label: 'Düşük', variant: 'neutral' },
    normal: { label: 'Normal', variant: 'info' },
    high: { label: 'Yüksek', variant: 'danger' },
};
const STATUS_META: Record<string, { label: string; variant: 'neutral' | 'info' | 'success' }> = {
    open: { label: 'Açık', variant: 'neutral' },
    in_progress: { label: 'Devam ediyor', variant: 'info' },
    done: { label: 'Tamamlandı', variant: 'success' },
};

function fmtDue(iso: string | null): string {
    if (!iso) return 'Süresiz';
    const d = new Date(iso);
    return d.toLocaleDateString('tr-TR', { day: '2-digit', month: 'short' }) + ' ' +
        d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
}
function isOverdue(t: TaskDto): boolean {
    return t.status !== 'done' && t.due_at !== null && new Date(t.due_at).getTime() < Date.now();
}
</script>

<template>
    <Head title="Görev Atama · Patron Paneli" />
    <BossLayout title="Görev Atama" subtitle="Personele görev ver, takip et">
        <div class="grid grid-cols-1 gap-5 lg:grid-cols-[380px_1fr]">
            <!-- ===== Görev ata formu (yalnız tasks.assign izni olan görür) ===== -->
            <section v-if="canManage" class="rounded-2xl border border-default bg-surface p-5 shadow-sm lg:sticky lg:top-28 lg:self-start">
                <div class="mb-4 flex items-center gap-2">
                    <span class="flex size-9 items-center justify-center rounded-xl bg-primary/10 text-primary">
                        <AppIcon name="clipboard" :size="18" />
                    </span>
                    <h2 class="text-base font-bold">Yeni görev ata</h2>
                </div>

                <form class="flex flex-col gap-3.5" @submit.prevent="submit">
                    <label class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Personel</span>
                        <select v-model="form.assigned_to_id" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm">
                            <option value="" disabled>Seçin…</option>
                            <option v-for="s in staff" :key="s.id" :value="s.id">
                                {{ s.name }}<template v-if="s.position"> · {{ s.position }}</template>
                            </option>
                        </select>
                        <span v-if="errors.assigned_to_id" class="text-xs text-danger">{{ errors.assigned_to_id }}</span>
                    </label>

                    <label class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Başlık</span>
                        <input v-model="form.title" type="text" maxlength="160" placeholder="ör. Depo sayımını tamamla"
                               class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                        <span v-if="errors.title" class="text-xs text-danger">{{ errors.title }}</span>
                    </label>

                    <label class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Açıklama <span class="font-normal">(isteğe bağlı)</span></span>
                        <textarea v-model="form.description" rows="2" placeholder="Detay…"
                                  class="resize-none rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm"></textarea>
                    </label>

                    <div class="grid grid-cols-2 gap-3">
                        <label class="flex flex-col gap-1">
                            <span class="text-xs font-semibold text-muted">Öncelik</span>
                            <select v-model="form.priority" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm">
                                <option value="low">Düşük</option>
                                <option value="normal">Normal</option>
                                <option value="high">Yüksek</option>
                            </select>
                        </label>
                        <label class="flex flex-col gap-1">
                            <span class="text-xs font-semibold text-muted">Son tarih</span>
                            <input v-model="form.due_at" type="datetime-local"
                                   class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                        </label>
                    </div>

                    <button type="submit" :disabled="!canSubmit || busy"
                            class="mt-1 inline-flex items-center justify-center gap-2 rounded-lg bg-primary px-4 py-2.5 text-sm font-semibold text-on-primary transition-opacity disabled:opacity-50">
                        <AppIcon v-if="!busy" name="check-circle" :size="16" />
                        <span>{{ busy ? 'Atanıyor…' : 'Görevi ata' }}</span>
                    </button>
                </form>
            </section>

            <!-- ===== Görev listesi ===== -->
            <section class="flex flex-col gap-4">
                <div v-if="loading" class="flex flex-col gap-3">
                    <BaseSkeleton v-for="i in 4" :key="i" class="h-20 rounded-xl" />
                </div>

                <template v-else>
                    <div>
                        <h3 class="mb-2 flex items-center gap-2 text-sm font-bold">
                            Aktif görevler
                            <BaseBadge variant="info">{{ openTasks.length }}</BaseBadge>
                        </h3>
                        <EmptyState v-if="openTasks.length === 0" icon="clipboard" title="Aktif görev yok"
                                    description="Sol taraftan yeni bir görev atayın." />
                        <ul v-else class="stagger-in flex flex-col gap-2.5">
                            <li v-for="t in openTasks" :key="t.id"
                                class="rounded-xl border border-default bg-surface p-3.5 shadow-sm">
                                <div class="flex items-start justify-between gap-3">
                                    <div class="min-w-0">
                                        <p class="truncate font-semibold">{{ t.title }}</p>
                                        <p v-if="t.description" class="mt-0.5 line-clamp-2 text-xs text-muted">{{ t.description }}</p>
                                    </div>
                                    <BaseBadge :variant="PRIORITY_META[t.priority].variant">{{ PRIORITY_META[t.priority].label }}</BaseBadge>
                                </div>
                                <div class="mt-2.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted">
                                    <span class="inline-flex items-center gap-1">
                                        <AppIcon name="user" :size="13" />
                                        {{ t.assigned_to?.name ?? '—' }}
                                    </span>
                                    <span class="inline-flex items-center gap-1" :class="{ 'text-danger font-semibold': isOverdue(t) }">
                                        <AppIcon name="calendar" :size="13" />
                                        {{ fmtDue(t.due_at) }}<template v-if="isOverdue(t)"> · gecikti</template>
                                    </span>
                                    <BaseBadge :variant="STATUS_META[t.status].variant">{{ STATUS_META[t.status].label }}</BaseBadge>
                                </div>
                            </li>
                        </ul>
                    </div>

                    <div v-if="doneTasks.length > 0">
                        <h3 class="mb-2 flex items-center gap-2 text-sm font-bold text-muted">
                            Tamamlanan
                            <BaseBadge variant="success">{{ doneTasks.length }}</BaseBadge>
                        </h3>
                        <ul class="flex flex-col gap-2">
                            <li v-for="t in doneTasks.slice(0, 8)" :key="t.id"
                                class="flex items-center justify-between gap-3 rounded-lg border border-default bg-surface-alt px-3.5 py-2.5 text-sm">
                                <span class="min-w-0 truncate text-muted line-through">{{ t.title }}</span>
                                <span class="shrink-0 text-xs text-muted">{{ t.assigned_to?.name ?? '—' }}</span>
                            </li>
                        </ul>
                    </div>
                </template>
            </section>
        </div>
    </BossLayout>
</template>
