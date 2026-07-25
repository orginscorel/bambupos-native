<script setup lang="ts">
/**
 * Global personel-taklidi (impersonation) şeridi.
 *
 * Uygulama KÖKÜNDE (app.ts) render edilir → PanelShell kullanmayan tam-ekran
 * sayfalarda (Mutfak/Barista/Komi KDS ekranları vb.) da görünür. Aksi halde
 * bir istasyon personelini taklit edip tam-ekran KDS'e düşünce "Yöneticiye dön"
 * afişi olmadığı için geri dönülemiyordu (kök neden).
 *
 * `impersonating` verisi HandleInertiaRequests ile global paylaşılır.
 */
import { computed, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';

const page = usePage();
const impersonating = computed<{ name: string | null } | null>(
    () => ((page.props as Record<string, unknown>).impersonating as { name: string | null } | null) ?? null,
);

const stopping = ref(false);

async function stop(): Promise<void> {
    if (stopping.value) return;
    stopping.value = true;
    try {
        const res = await api<{ redirect_to?: string }>('/api/v1/staff/stop-impersonate', { method: 'POST' });
        window.location.href = res.redirect_to ?? '/panel/personel';
    } catch (e) {
        // Köprü hata verse bile yöneticinin çıkabilmesi için sağlam düşüş:
        // personel sayfasına zorla; oturum sunucuda hâlâ taklitse orada düzelir.
        window.location.href = e instanceof ApiError && e.status === 401 ? '/giris' : '/panel/personel';
    }
}
</script>

<template>
    <Teleport to="body">
        <div
            v-if="impersonating"
            class="fixed inset-x-0 top-0 z-[2000] flex items-center justify-center gap-3 border-b border-warning-border bg-warning-soft px-4 py-1.5 text-sm text-warning shadow-md"
            role="alert"
        >
            <span class="truncate">
                <strong>{{ impersonating.name ?? 'Personel' }}</strong> olarak görüntülüyorsunuz — test modu.
            </span>
            <button
                type="button"
                class="shrink-0 rounded-md border border-warning-border bg-raised px-3 py-1 text-xs font-semibold text-body transition-colors hover:bg-inset disabled:opacity-60"
                :disabled="stopping"
                @click="stop"
            >
                {{ stopping ? 'Dönülüyor…' : '← Yöneticiye dön' }}
            </button>
        </div>
    </Teleport>
</template>
