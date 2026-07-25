<script setup lang="ts">
/**
 * Personel-taklidi (impersonation) — kompakt "Yöneticiye dön" düğmesi.
 *
 * Uygulama KÖKÜNDE (app.ts) render edilir → PanelShell kullanmayan tam-ekran
 * sayfalarda (Mutfak/Barista/Komi vb.) da erişilebilir. Kullanıcı talebiyle
 * tam-genişlik banner KALDIRILDI; yalnız sağ altta küçük bir dönüş düğmesi
 * kalır (kimi taklit ettiğin başlıkta/tooltip'te). `impersonating` verisi
 * HandleInertiaRequests ile global paylaşılır.
 */
import { computed, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import AppIcon from '@/Components/ui/AppIcon.vue';

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
        window.location.href = e instanceof ApiError && e.status === 401 ? '/giris' : '/panel/personel';
    }
}
</script>

<template>
    <Teleport to="body">
        <button
            v-if="impersonating"
            type="button"
            :disabled="stopping"
            :title="`${impersonating.name ?? 'Personel'} olarak görüntülüyorsunuz — yöneticiye dön`"
            class="fixed bottom-4 right-4 z-[2000] inline-flex items-center gap-2 rounded-full border border-warning-border bg-warning-soft px-4 py-2 text-sm font-semibold text-warning shadow-lg transition-colors hover:bg-warning hover:text-white disabled:opacity-60"
            aria-label="Yöneticiye dön"
            @click="stop"
        >
            <AppIcon name="logout" :size="16" />
            {{ stopping ? 'Dönülüyor…' : 'Yöneticiye dön' }}
        </button>
    </Teleport>
</template>
