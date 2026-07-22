<script setup lang="ts">
import { ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import type { StationRow } from './kds';

/**
 * İstasyon tanımları (kds.manage): yerleşikler salt-okunur, işletmenin
 * kendi istasyonları eklenir/pasifleştirilir/silinir + personel-istasyon
 * ataması ("yalnız kendi istasyonunu görsün").
 */
const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { success, danger } = useToast();

const stations = ref<StationRow[]>([]);
const assignments = ref<{ id: number; name: string; position: string | null; station_keys: string[] }[]>([]);
const loading = ref(false);
const busy = ref(false);
const newName = ref('');
const tab = ref<'stations' | 'assignments'>('stations');

async function load(): Promise<void> {
    loading.value = true;
    try {
        const [s, a] = await Promise.all([
            api<{ stations: StationRow[] }>('/api/v1/kds/stations'),
            api<{ users: typeof assignments.value }>('/api/v1/kds/station-assignments'),
        ]);
        stations.value = s.stations;
        assignments.value = a.users;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

watch(
    () => props.open,
    (open) => {
        if (open) void load();
    },
);

async function run(fn: () => Promise<unknown>, okMsg: string): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await fn();
        if (okMsg) success(okMsg, '');
        await load();
    } catch (e) {
        danger('İşlem tamamlanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

function addStation(): void {
    const name = newName.value.trim();
    if (!name) return;
    void run(() => api('/api/v1/kds/stations', { method: 'POST', body: { name } }), 'İstasyon eklendi').then(
        () => (newName.value = ''),
    );
}

function toggleActive(s: StationRow): void {
    if (s.id === null) return;
    void run(
        () => api(`/api/v1/kds/stations/${s.id}`, { method: 'PUT', body: { is_active: !s.is_active } }),
        s.is_active ? 'İstasyon pasifleştirildi' : 'İstasyon aktifleştirildi',
    );
}

function removeStation(s: StationRow): void {
    if (s.id === null) return;
    void run(() => api(`/api/v1/kds/stations/${s.id}`, { method: 'DELETE' }), 'İstasyon silindi');
}

function toggleAssignment(user: { id: number; station_keys: string[] }, key: string): void {
    const keys = user.station_keys.includes(key)
        ? user.station_keys.filter((k) => k !== key)
        : [...user.station_keys, key];
    void run(
        () => api(`/api/v1/kds/station-assignments/${user.id}`, { method: 'PUT', body: { station_keys: keys } }),
        'Atama güncellendi',
    );
}
</script>

<template>
    <BaseModal :open="open" title="İstasyon Yönetimi" size="lg" @close="emit('close')">
        <div class="mb-4 flex gap-2">
            <button
                class="h-10 rounded-lg px-4 font-semibold"
                :class="tab === 'stations' ? 'bg-orange-500 text-white' : 'bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200'"
                @click="tab = 'stations'"
            >
                İstasyonlar
            </button>
            <button
                class="h-10 rounded-lg px-4 font-semibold"
                :class="tab === 'assignments' ? 'bg-orange-500 text-white' : 'bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200'"
                @click="tab = 'assignments'"
            >
                Personel Ataması
            </button>
        </div>

        <p v-if="loading" class="py-6 text-center">Yükleniyor…</p>

        <!-- ==== İstasyon listesi + ekleme ==== -->
        <div v-else-if="tab === 'stations'" class="space-y-3">
            <div class="flex gap-2">
                <BaseInput v-model="newName" placeholder="Yeni istasyon adı (ör. Pizza Fırını)" class="flex-1" @keyup.enter="addStation" />
                <button
                    class="flex h-11 items-center gap-1 rounded-lg bg-orange-500 px-4 font-bold text-white disabled:opacity-50"
                    :disabled="!newName.trim() || busy"
                    @click="addStation"
                >
                    <AppIcon name="plus" :size="18" /> Ekle
                </button>
            </div>

            <ul class="divide-y divide-slate-200 rounded-lg border border-slate-200 dark:divide-slate-700 dark:border-slate-700">
                <li v-for="s in stations" :key="s.key" class="flex items-center gap-3 px-3 py-2">
                    <span class="font-semibold" :class="s.is_active ? '' : 'line-through opacity-50'">{{ s.name }}</span>
                    <span class="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500 dark:bg-slate-800 dark:text-slate-400">{{ s.key }}</span>
                    <span
                        v-if="s.is_builtin"
                        class="rounded-full bg-slate-200 px-2 py-0.5 text-xs font-semibold text-slate-600 dark:bg-slate-700 dark:text-slate-300"
                    >
                        yerleşik
                    </span>
                    <span class="ml-auto flex gap-1.5">
                        <button
                            v-if="!s.is_builtin"
                            class="h-9 rounded-lg bg-slate-200 px-3 text-sm font-semibold text-slate-700 dark:bg-slate-700 dark:text-slate-200"
                            :disabled="busy"
                            @click="toggleActive(s)"
                        >
                            {{ s.is_active ? 'Pasifleştir' : 'Aktifleştir' }}
                        </button>
                        <button
                            v-if="!s.is_builtin"
                            class="flex h-9 w-9 items-center justify-center rounded-lg bg-red-100 text-red-600 dark:bg-red-950"
                            :disabled="busy"
                            aria-label="İstasyonu sil"
                            @click="removeStation(s)"
                        >
                            <AppIcon name="trash" :size="16" />
                        </button>
                    </span>
                </li>
            </ul>
            <p class="text-sm text-slate-500">
                Yerleşik istasyonlar silinemez. Ürünler istasyonlara <strong>Menü → Ürün → Operasyon</strong> kartından yönlendirilir.
            </p>
        </div>

        <!-- ==== Personel ataması ==== -->
        <div v-else class="space-y-3">
            <p class="text-sm text-slate-500">
                Atama yapılan personel mutfak ekranında <strong>yalnız kendi istasyonlarını</strong> görür ve işaretler.
                Ataması olmayan personel tüm istasyonları görür.
            </p>
            <ul class="divide-y divide-slate-200 rounded-lg border border-slate-200 dark:divide-slate-700 dark:border-slate-700">
                <li v-for="u in assignments" :key="u.id" class="px-3 py-2">
                    <p class="font-semibold">{{ u.name }} <span v-if="u.position" class="text-sm font-normal text-slate-500">— {{ u.position }}</span></p>
                    <div class="mt-1.5 flex flex-wrap gap-1.5">
                        <button
                            v-for="s in stations.filter((x) => x.is_active)"
                            :key="s.key"
                            class="h-9 rounded-full px-3 text-sm font-semibold"
                            :class="u.station_keys.includes(s.key)
                                ? 'bg-orange-500 text-white'
                                : 'bg-slate-200 text-slate-600 dark:bg-slate-700 dark:text-slate-300'"
                            :disabled="busy"
                            @click="toggleAssignment(u, s.key)"
                        >
                            {{ s.name }}
                        </button>
                    </div>
                </li>
            </ul>
        </div>
    </BaseModal>
</template>
