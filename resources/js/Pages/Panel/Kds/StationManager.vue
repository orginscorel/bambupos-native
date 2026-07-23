<script setup lang="ts">
import { ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import type { StationRow } from './kds';

/**
 * İstasyon tanımları (kds.manage): yerleşikler salt-okunur, işletmenin
 * kendi istasyonları eklenir/pasifleştirilir/silinir + personel-istasyon
 * ataması ("yalnız kendi istasyonunu görsün"). Panel bileşen diliyle.
 */
const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { success, danger } = useToast();

const stations = ref<StationRow[]>([]);
const assignments = ref<{ id: number; name: string; position: string | null; station_keys: string[] }[]>([]);
const loading = ref(false);
const busy = ref(false);
const newName = ref('');
const tab = ref('stations');

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
        <p v-if="loading" class="py-6 text-center text-muted">Yükleniyor…</p>

        <BaseTabs
            v-else
            v-model="tab"
            :tabs="[
                { key: 'stations', label: 'İstasyonlar' },
                { key: 'assignments', label: 'Personel Ataması', icon: 'users' },
            ]"
        >
            <!-- ==== İstasyon listesi + ekleme ==== -->
            <template #stations>
                <div class="flex flex-col gap-3">
                    <div class="flex gap-2">
                        <BaseInput
                            v-model="newName"
                            placeholder="Yeni istasyon adı (ör. Pizza Fırını)"
                            class="flex-1"
                            @keyup.enter="addStation"
                        />
                        <BaseButton :disabled="!newName.trim() || busy" @click="addStation">
                            <AppIcon name="plus" :size="16" />
                            Ekle
                        </BaseButton>
                    </div>

                    <ul class="divide-y divide-default rounded-lg border border-default">
                        <li v-for="s in stations" :key="s.key" class="flex flex-wrap items-center gap-2 px-3 py-2">
                            <span class="font-medium" :class="s.is_active ? '' : 'line-through opacity-55'">{{ s.name }}</span>
                            <BaseBadge variant="neutral">{{ s.key }}</BaseBadge>
                            <BaseBadge v-if="s.is_builtin" variant="neutral">yerleşik</BaseBadge>
                            <span v-if="!s.is_builtin" class="ml-auto flex items-center gap-2">
                                <BaseSwitch
                                    :model-value="s.is_active"
                                    :busy="busy"
                                    :aria-label="s.is_active ? `${s.name} istasyonunu pasifleştir` : `${s.name} istasyonunu aktifleştir`"
                                    @update:model-value="toggleActive(s)"
                                />
                                <BaseButton
                                    variant="ghost"
                                    icon-only
                                    :label="`${s.name} istasyonunu sil`"
                                    :disabled="busy"
                                    class="text-danger"
                                    @click="removeStation(s)"
                                >
                                    <AppIcon name="trash" :size="16" />
                                </BaseButton>
                            </span>
                        </li>
                    </ul>
                    <p class="text-sm text-muted">
                        Yerleşik istasyonlar silinemez. Ürünler istasyonlara <strong>Menü → Ürün → Operasyon</strong>
                        kartından yönlendirilir.
                    </p>
                </div>
            </template>

            <!-- ==== Personel ataması ==== -->
            <template #assignments>
                <div class="flex flex-col gap-3">
                    <p class="text-sm text-muted">
                        Atama yapılan personel mutfak ekranında <strong>yalnız kendi istasyonlarını</strong> görür ve
                        işaretler. Ataması olmayan personel tüm istasyonları görür.
                    </p>
                    <ul class="divide-y divide-default rounded-lg border border-default">
                        <li v-for="u in assignments" :key="u.id" class="px-3 py-2.5">
                            <p class="font-medium">
                                {{ u.name }}
                                <span v-if="u.position" class="text-sm font-normal text-muted">— {{ u.position }}</span>
                            </p>
                            <div class="mt-1.5 flex flex-wrap gap-1.5">
                                <button
                                    v-for="s in stations.filter((x) => x.is_active)"
                                    :key="s.key"
                                    type="button"
                                    class="inline-flex h-9 items-center rounded-full border px-3 text-sm font-medium transition-colors"
                                    :class="u.station_keys.includes(s.key)
                                        ? 'border-primary bg-primary text-on-primary'
                                        : 'border-default bg-raised text-body hover:bg-inset'"
                                    :disabled="busy"
                                    @click="toggleAssignment(u, s.key)"
                                >
                                    {{ s.name }}
                                </button>
                            </div>
                        </li>
                    </ul>
                </div>
            </template>
        </BaseTabs>
    </BaseModal>
</template>
