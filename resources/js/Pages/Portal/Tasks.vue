<script setup lang="ts">
/**
 * Portal "Görevlerim": kişiye atanmış görevler + sayaç rozetleri
 * (Açık/Devam/Bitti). Kart başına öncelik/son tarih/durum; "Başladım" ve
 * "Tamamladım" aksiyonları görevin durumunu ilerletir (self uç).
 */
import { computed, onMounted, ref } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

type TaskPriority = 'low' | 'normal' | 'high';
type TaskStatus = 'open' | 'in_progress' | 'done';

interface TaskDTO {
    id: number;
    title: string;
    description: string | null;
    priority: TaskPriority;
    status: TaskStatus;
    due_at: string | null;
    created_by?: { id: number; name: string } | null;
    created_at: string | null;
    completed_at: string | null;
}

interface TasksResponse {
    tasks: TaskDTO[];
    counts: { open: number; in_progress: number; done: number };
}

const { success, danger } = useToast();

const loading = ref(true);
const tasks = ref<TaskDTO[]>([]);
const counts = ref({ open: 0, in_progress: 0, done: 0 });
const busyId = ref(0);

const dtFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

const priorityMeta: Record<TaskPriority, { label: string; classes: string }> = {
    low: { label: 'Düşük', classes: 'bg-(--color-inset) text-muted' },
    normal: { label: 'Normal', classes: 'bg-(--p-indigo-soft) text-(--p-indigo)' },
    high: { label: 'Yüksek', classes: 'bg-(--p-rose-soft) text-(--p-rose)' },
};

const statusMeta: Record<TaskStatus, { label: string; classes: string }> = {
    open: { label: 'Açık', classes: 'bg-(--color-inset) text-muted' },
    in_progress: { label: 'Devam ediyor', classes: 'bg-(--p-indigo-soft) text-(--p-indigo)' },
    done: { label: 'Tamamlandı', classes: 'bg-(--p-emerald-soft) text-(--p-emerald)' },
};

function isOverdue(task: TaskDTO): boolean {
    return task.status !== 'done' && task.due_at !== null && new Date(task.due_at).getTime() < Date.now();
}

const dueFmt = (iso: string | null): string => (iso ? dtFmt.format(new Date(iso)) : '');

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<TasksResponse>('/api/v1/portal/tasks');
        tasks.value = res.tasks ?? [];
        counts.value = res.counts ?? { open: 0, in_progress: 0, done: 0 };
    } catch {
        tasks.value = [];
    } finally {
        loading.value = false;
    }
}

async function setStatus(task: TaskDTO, status: 'in_progress' | 'done'): Promise<void> {
    if (busyId.value) return;
    busyId.value = task.id;
    try {
        const res = await api<{ task: TaskDTO }>(`/api/v1/portal/tasks/${task.id}/status`, {
            method: 'POST',
            body: { status },
        });
        const idx = tasks.value.findIndex((t) => t.id === task.id);
        if (idx !== -1 && res.task) tasks.value[idx] = res.task;
        success(status === 'done' ? 'Görev tamamlandı' : 'Görev başlatıldı');
        // Sayaçları yeniden hesapla
        counts.value = tasks.value.reduce(
            (acc, t) => {
                acc[t.status] += 1;
                return acc;
            },
            { open: 0, in_progress: 0, done: 0 },
        );
    } catch (e) {
        danger(e instanceof ApiError ? e.displayMessage : 'İşlem tamamlanamadı.');
    } finally {
        busyId.value = 0;
    }
}

const isEmpty = computed(() => !loading.value && tasks.value.length === 0);

const openTotal = computed(() => counts.value.open + counts.value.in_progress);
const subtitle = computed(() => {
    if (loading.value) return 'Görevleriniz yükleniyor…';
    if (tasks.value.length === 0) return 'Atanmış görev yok';
    return openTotal.value > 0 ? `${openTotal.value} açık görev` : 'Tüm görevler tamam 🎉';
});

onMounted(load);
</script>

<template>
    <PortalLayout title="Görevlerim" active="tasks" :heading="'Görevlerim'" :subtitle="subtitle">
        <!-- Sayaç rozetleri (renkli tile'lar) -->
        <div class="grid grid-cols-3 gap-2.5 text-center">
            <div class="p-tile p-tile-amber">
                <p class="text-2xl font-extrabold tabular-nums">{{ counts.open }}</p>
                <p class="mt-0.5 text-xs opacity-80">Açık</p>
            </div>
            <div class="p-tile p-tile-indigo">
                <p class="text-2xl font-extrabold tabular-nums">{{ counts.in_progress }}</p>
                <p class="mt-0.5 text-xs opacity-80">Devam</p>
            </div>
            <div class="p-tile p-tile-emerald">
                <p class="text-2xl font-extrabold tabular-nums">{{ counts.done }}</p>
                <p class="mt-0.5 text-xs opacity-80">Bitti</p>
            </div>
        </div>

        <!-- Yükleniyor -->
        <div v-if="loading" class="mt-4 flex flex-col gap-3">
            <BaseSkeleton v-for="i in 3" :key="i" class="h-28 w-full rounded-2xl" />
        </div>

        <!-- Boş durum -->
        <div v-else-if="isEmpty" class="mt-4 p-card p-2">
            <EmptyState icon="check-circle" title="Size atanmış görev yok" description="Yeni görevler burada listelenir." />
        </div>

        <!-- Görev listesi -->
        <ul v-else class="mt-4 flex flex-col gap-3">
            <li
                v-for="task in tasks"
                :key="task.id"
                class="p-card p-4 transition"
                :class="task.status === 'done' ? 'opacity-60' : ''"
            >
                <div class="flex items-start justify-between gap-3">
                    <p class="text-base font-semibold text-body" :class="task.status === 'done' ? 'line-through' : ''">
                        {{ task.title }}
                    </p>
                    <span
                        class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold"
                        :class="priorityMeta[task.priority].classes"
                    >
                        {{ priorityMeta[task.priority].label }}
                    </span>
                </div>

                <p v-if="task.description" class="mt-1.5 text-sm text-muted">{{ task.description }}</p>

                <div class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-xs">
                    <span
                        class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 font-semibold"
                        :class="statusMeta[task.status].classes"
                    >
                        {{ statusMeta[task.status].label }}
                    </span>
                    <span
                        v-if="task.due_at"
                        class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 font-semibold"
                        :class="isOverdue(task) ? 'bg-(--p-rose-soft) text-(--p-rose)' : 'text-muted'"
                    >
                        <AppIcon name="clock" :size="13" />
                        {{ dueFmt(task.due_at) }}<template v-if="isOverdue(task)"> · gecikti</template>
                    </span>
                    <span v-if="task.created_by" class="inline-flex items-center gap-1 text-subtle">
                        <AppIcon name="user" :size="13" />
                        {{ task.created_by.name }}
                    </span>
                </div>

                <!-- Aksiyonlar -->
                <div v-if="task.status !== 'done'" class="mt-4 flex gap-2">
                    <BaseButton
                        v-if="task.status === 'open'"
                        size="sm"
                        variant="secondary"
                        :loading="busyId === task.id"
                        @click="setStatus(task, 'in_progress')"
                    >
                        Başladım
                    </BaseButton>
                    <BaseButton size="sm" :loading="busyId === task.id" @click="setStatus(task, 'done')">
                        Tamamladım
                    </BaseButton>
                </div>
            </li>
        </ul>
    </PortalLayout>
</template>
