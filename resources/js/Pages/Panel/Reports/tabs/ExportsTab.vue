<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { formatDateTime } from '@/lib/format';
import { ApiError } from '@/lib/http';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import { fetchExports, type ExportRow } from '../reports';

/**
 * Dışa aktarımlar: kuyruk durumu + indirme. Bekleyen iş varken kısa
 * aralıkla yoklar (queue worker cron'u dosyayı üretince "hazır" olur);
 * hepsi bittiğinde yoklama durur.
 */
const rows = ref<ExportRow[]>([]);
const loading = ref(true);
const error = ref('');

let timer: ReturnType<typeof setTimeout> | null = null;

async function load(): Promise<void> {
    try {
        rows.value = await fetchExports();
        error.value = '';
    } catch (e) {
        error.value = e instanceof ApiError ? e.displayMessage : 'Liste yüklenemedi.';
    } finally {
        loading.value = false;
    }

    const hasPending = rows.value.some((r) => r.status === 'queued' || r.status === 'processing');
    if (hasPending) {
        timer = setTimeout(() => void load(), 4000);
    }
}

onMounted(() => void load());
onUnmounted(() => {
    if (timer !== null) clearTimeout(timer);
});

defineExpose({ reload: () => void load() });

/** İndirme aynı sekmede dosya olarak iner (Content-Disposition: attachment). */
function download(r: ExportRow): void {
    if (r.download_url) window.location.href = r.download_url;
}

const statusMeta = computed(() => ({
    queued: { label: 'Kuyrukta', variant: 'info' as const },
    processing: { label: 'Hazırlanıyor', variant: 'warning' as const },
    done: { label: 'Hazır', variant: 'success' as const },
    failed: { label: 'Başarısız', variant: 'danger' as const },
}));
</script>

<template>
    <BaseCard title="Dışa aktarımlar" flush>
        <p v-if="error" class="px-4 py-3 text-sm text-danger">{{ error }}</p>
        <p v-else-if="loading" class="px-4 py-6 text-center text-sm text-muted">Yükleniyor…</p>

        <EmptyState
            v-else-if="rows.length === 0"
            icon="inbox"
            title="Henüz dışa aktarma yok"
            description="Herhangi bir rapor kartındaki 'Dışa aktar' menüsünden CSV, Excel ya da PDF isteyin; dosya kuyrukta üretilir ve burada listelenir."
        />

        <div v-else class="overflow-x-auto">
            <table class="w-full text-sm">
                <thead>
                    <tr class="border-b border-default bg-surface-alt">
                        <th class="px-3 py-2 text-left text-xs font-semibold text-muted">Rapor</th>
                        <th class="px-3 py-2 text-left text-xs font-semibold text-muted">Aralık</th>
                        <th class="px-3 py-2 text-left text-xs font-semibold text-muted">Biçim</th>
                        <th class="px-3 py-2 text-left text-xs font-semibold text-muted">Durum</th>
                        <th class="px-3 py-2 text-right text-xs font-semibold text-muted">Satır</th>
                        <th class="px-3 py-2 text-left text-xs font-semibold text-muted">İstendi</th>
                        <th class="px-3 py-2 text-right text-xs font-semibold text-muted">İndir</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="r in rows" :key="r.id" class="border-b border-default last:border-0">
                        <td class="px-3 py-2 font-medium whitespace-nowrap text-body">{{ r.title }}</td>
                        <td class="px-3 py-2 whitespace-nowrap text-muted">{{ r.from }} – {{ r.to }}</td>
                        <td class="px-3 py-2 uppercase whitespace-nowrap text-muted">{{ r.format }}</td>
                        <td class="px-3 py-2 whitespace-nowrap">
                            <BaseBadge :variant="statusMeta[r.status].variant">{{ statusMeta[r.status].label }}</BaseBadge>
                            <span v-if="r.error" class="ml-1 text-xs text-danger">{{ r.error }}</span>
                        </td>
                        <td class="px-3 py-2 text-right tabular-nums whitespace-nowrap text-muted">
                            {{ r.rows_count ?? '—' }}
                        </td>
                        <td class="px-3 py-2 whitespace-nowrap text-muted">
                            {{ r.created_at ? formatDateTime(r.created_at) : '—' }}
                        </td>
                        <td class="px-3 py-2 text-right whitespace-nowrap">
                            <BaseButton v-if="r.download_url" variant="secondary" size="sm" @click="download(r)">
                                İndir
                            </BaseButton>
                            <span v-else class="text-xs text-subtle">—</span>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </BaseCard>
</template>
