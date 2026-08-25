<script setup lang="ts">
/**
 * /panel/gorevler — yönetici görev atama panosu:
 * personele görev ata (başlık/açıklama/öncelik/son tarih), durum sütunları
 * (Açık / Devam / Bitti), düzenle / sil. Yazma butonları `tasks.assign`
 * iznine, sayfa `tasks.view` iznine bağlıdır (arayüz gizleme; asıl koruma backend).
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { usePermissions } from '@/composables/usePermissions';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';

type TaskPriority = 'low' | 'normal' | 'high';
type TaskStatus = 'open' | 'in_progress' | 'done';

interface StaffOption {
    id: number;
    name: string;
    position: string | null;
}

interface TaskDTO {
    id: number;
    title: string;
    description: string | null;
    priority: TaskPriority;
    status: TaskStatus;
    due_at: string | null;
    branch_id: number | null;
    assigned_to: { id: number; name: string; position: string | null } | null;
    created_by: { id: number; name: string } | null;
    created_at: string | null;
    completed_at: string | null;
}

interface TasksResponse {
    tasks: TaskDTO[];
    staff: StaffOption[];
}

const { can } = usePermissions();
const { success, danger } = useToast();

const canView = computed(() => can('tasks.view'));
const canAssign = computed(() => can('tasks.assign'));

const loading = ref(true);
const tasks = ref<TaskDTO[]>([]);
const staff = ref<StaffOption[]>([]);

const dtFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

const priorityMeta: Record<TaskPriority, { label: string; variant: 'neutral' | 'primary' | 'danger' }> = {
    low: { label: 'Düşük', variant: 'neutral' },
    normal: { label: 'Normal', variant: 'primary' },
    high: { label: 'Yüksek', variant: 'danger' },
};

const columns: { status: TaskStatus; label: string }[] = [
    { status: 'open', label: 'Açık' },
    { status: 'in_progress', label: 'Devam ediyor' },
    { status: 'done', label: 'Tamamlandı' },
];

const priorityOptions = [
    { value: 'low', label: 'Düşük' },
    { value: 'normal', label: 'Normal' },
    { value: 'high', label: 'Yüksek' },
];

const statusOptions = [
    { value: 'open', label: 'Açık' },
    { value: 'in_progress', label: 'Devam ediyor' },
    { value: 'done', label: 'Tamamlandı' },
];

const staffOptions = computed(() => [
    { value: '', label: 'Personel seçin', disabled: true },
    ...staff.value.map((s) => ({ value: String(s.id), label: s.position ? `${s.name} · ${s.position}` : s.name })),
]);

function tasksByStatus(status: TaskStatus): TaskDTO[] {
    return tasks.value.filter((t) => t.status === status);
}

function isOverdue(task: TaskDTO): boolean {
    return task.status !== 'done' && task.due_at !== null && new Date(task.due_at).getTime() < Date.now();
}

const dueFmt = (iso: string | null): string => (iso ? dtFmt.format(new Date(iso)) : '');

/** ISO → datetime-local input değeri (yerel saat). */
function toDatetimeLocal(iso: string | null): string {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<TasksResponse>('/api/v1/tasks');
        tasks.value = res.tasks ?? [];
        staff.value = res.staff ?? [];
    } catch (e) {
        danger('Görevler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(() => {
    if (canView.value) void load();
    else loading.value = false;
});

/* ---- Oluştur / Düzenle formu ---- */
const formOpen = ref(false);
const editingId = ref<number | null>(null);
const saving = ref(false);
const form = reactive({
    assigned_to_id: '',
    title: '',
    description: '',
    priority: 'normal' as TaskPriority,
    due_at: '',
    status: 'open' as TaskStatus,
});
const formErrors = reactive<Record<string, string>>({});

function resetForm(): void {
    form.assigned_to_id = '';
    form.title = '';
    form.description = '';
    form.priority = 'normal';
    form.due_at = '';
    form.status = 'open';
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
}

function openCreate(): void {
    editingId.value = null;
    resetForm();
    formOpen.value = true;
}

function openEdit(task: TaskDTO): void {
    editingId.value = task.id;
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
    form.assigned_to_id = task.assigned_to ? String(task.assigned_to.id) : '';
    form.title = task.title;
    form.description = task.description ?? '';
    form.priority = task.priority;
    form.due_at = toDatetimeLocal(task.due_at);
    form.status = task.status;
    formOpen.value = true;
}

async function save(): Promise<void> {
    saving.value = true;
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
    try {
        if (editingId.value === null) {
            const body = {
                assigned_to_id: Number(form.assigned_to_id) || null,
                title: form.title,
                description: form.description || null,
                priority: form.priority,
                due_at: form.due_at || null,
            };
            await api('/api/v1/tasks', { method: 'POST', body });
            success('Görev atandı');
        } else {
            const body = {
                title: form.title,
                description: form.description || null,
                priority: form.priority,
                due_at: form.due_at || null,
                status: form.status,
            };
            await api(`/api/v1/tasks/${editingId.value}`, { method: 'PUT', body });
            success('Görev güncellendi');
        }
        formOpen.value = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            Object.entries(e.errors).forEach(([k, v]) => (formErrors[k] = v[0] ?? ''));
            if (!Object.keys(e.errors).length) danger(e.displayMessage);
        }
    } finally {
        saving.value = false;
    }
}

/* ---- Sil ---- */
const deleteTarget = ref<TaskDTO | null>(null);
const deleting = ref(false);

async function remove(): Promise<void> {
    const task = deleteTarget.value;
    if (!task || deleting.value) return;
    deleting.value = true;
    try {
        await api(`/api/v1/tasks/${task.id}`, { method: 'DELETE' });
        success('Görev silindi');
        deleteTarget.value = null;
        await load();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        deleting.value = false;
    }
}
</script>

<template>
    <Head title="Görevler" />
    <PanelShell title="Görevler" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <!-- Yetki yok -->
        <div v-if="!canView">
            <EmptyState
                icon="alert-circle"
                title="Erişim yok"
                description="Görevleri görüntülemek için yetkiniz bulunmuyor."
            />
        </div>

        <div v-else class="flex flex-col gap-4">
            <!-- Araç çubuğu -->
            <div class="flex flex-wrap items-center gap-2">
                <p class="text-sm text-muted">Personele görev atayın ve ilerlemesini takip edin.</p>
                <span class="grow" />
                <BaseButton v-if="canAssign" @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Görev Ata
                </BaseButton>
            </div>

            <!-- Yükleniyor -->
            <div v-if="loading" class="grid grid-cols-1 gap-4 lg:grid-cols-3">
                <BaseSkeleton v-for="i in 3" :key="i" class="h-40 w-full rounded-lg" />
            </div>

            <!-- Boş -->
            <EmptyState
                v-else-if="tasks.length === 0"
                icon="check-circle"
                title="Henüz görev yok"
                :description="canAssign ? 'İlk görevi atayarak başlayın.' : 'Atanmış görev bulunmuyor.'"
            >
                <template v-if="canAssign" #action>
                    <BaseButton @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Görev Ata
                    </BaseButton>
                </template>
            </EmptyState>

            <!-- Durum sütunları -->
            <div v-else class="grid grid-cols-1 gap-4 lg:grid-cols-3">
                <section
                    v-for="col in columns"
                    :key="col.status"
                    class="flex flex-col gap-3 rounded-lg border border-default bg-surface-alt p-3"
                >
                    <div class="flex items-center justify-between px-1">
                        <h2 class="text-sm font-semibold text-body">{{ col.label }}</h2>
                        <span class="rounded-full bg-inset px-2 py-0.5 text-xs font-medium text-muted">
                            {{ tasksByStatus(col.status).length }}
                        </span>
                    </div>

                    <p v-if="tasksByStatus(col.status).length === 0" class="px-1 py-4 text-center text-xs text-subtle">
                        Görev yok
                    </p>

                    <article
                        v-for="task in tasksByStatus(col.status)"
                        :key="task.id"
                        class="rounded-lg border border-default bg-raised p-3 shadow-(--shadow-card)"
                        :class="task.status === 'done' ? 'opacity-70' : ''"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <p class="text-sm font-semibold text-body" :class="task.status === 'done' ? 'line-through' : ''">
                                {{ task.title }}
                            </p>
                            <BaseBadge :variant="priorityMeta[task.priority].variant" no-icon class="shrink-0">
                                {{ priorityMeta[task.priority].label }}
                            </BaseBadge>
                        </div>

                        <p v-if="task.description" class="mt-1 line-clamp-3 text-xs text-muted">{{ task.description }}</p>

                        <div class="mt-2.5 flex flex-col gap-1 text-xs text-muted">
                            <span v-if="task.assigned_to" class="inline-flex items-center gap-1">
                                <AppIcon name="user" :size="13" />
                                {{ task.assigned_to.name }}
                            </span>
                            <span
                                v-if="task.due_at"
                                class="inline-flex items-center gap-1"
                                :class="isOverdue(task) ? 'font-semibold text-danger' : ''"
                            >
                                <AppIcon name="clock" :size="13" />
                                {{ dueFmt(task.due_at) }}<template v-if="isOverdue(task)"> · gecikti</template>
                            </span>
                        </div>

                        <div v-if="canAssign" class="mt-3 flex items-center justify-end gap-1 border-t border-default pt-2">
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${task.title} düzenle`" @click="openEdit(task)">
                                <AppIcon name="pencil" :size="15" />
                            </BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${task.title} sil`" @click="deleteTarget = task">
                                <AppIcon name="trash" :size="15" />
                            </BaseButton>
                        </div>
                    </article>
                </section>
            </div>
        </div>

        <!-- Oluştur / Düzenle modalı -->
        <BaseModal :open="formOpen" :title="editingId === null ? 'Görev Ata' : 'Görevi Düzenle'" @close="formOpen = false">
            <div class="flex flex-col gap-4">
                <FormField v-if="editingId === null" label="Personel" :error="formErrors.assigned_to_id" required>
                    <BaseSelect v-model="form.assigned_to_id" :options="staffOptions" />
                </FormField>
                <FormField label="Başlık" :error="formErrors.title" required>
                    <BaseInput v-model="form.title" placeholder="Görev başlığı" />
                </FormField>
                <FormField label="Açıklama" :error="formErrors.description">
                    <textarea
                        v-model="form.description"
                        rows="3"
                        placeholder="Ayrıntılar (opsiyonel)"
                        class="w-full rounded-md border border-strong bg-raised px-3 py-2 text-sm text-body placeholder:text-subtle transition-colors duration-(--dur-fast) focus:border-strong focus:outline-none focus:ring-2 focus:ring-ring-brand"
                    />
                </FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Öncelik" :error="formErrors.priority">
                        <BaseSelect v-model="form.priority" :options="priorityOptions" />
                    </FormField>
                    <FormField label="Son tarih" :error="formErrors.due_at">
                        <BaseInput v-model="form.due_at" type="datetime-local" />
                    </FormField>
                </div>
                <FormField v-if="editingId !== null" label="Durum" :error="formErrors.status">
                    <BaseSelect v-model="form.status" :options="statusOptions" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="formOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">{{ editingId === null ? 'Ata' : 'Kaydet' }}</BaseButton>
            </template>
        </BaseModal>

        <!-- Sil onayı -->
        <BaseModal :open="deleteTarget !== null" title="Görevi sil" size="sm" @close="deleteTarget = null">
            <p class="text-sm text-body">
                <strong>{{ deleteTarget?.title }}</strong> görevi kalıcı olarak silinecek. Bu işlem geri alınamaz.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="deleteTarget = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="deleting" @click="remove">Sil</BaseButton>
            </template>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
