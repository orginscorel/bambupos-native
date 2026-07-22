<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import PermissionMatrix from './components/PermissionMatrix.vue';
import StaffShell from './components/StaffShell.vue';
import type { RoleSummary, StaffMeta } from './types';

/**
 * /panel/personel/roller — rol yönetimi + YETKİ MATRİSİ.
 *  - Rol oluştur (şablondan başlatma: "Garson gibi başlat"), düzenle,
 *    kopyala, sil.
 *  - is_system roller korumalı: silinemez, izin seti değiştirilemez.
 *  - Matris hücreleri switch; modül başlığında "tümü" switch'i;
 *    tehlikeli izinler uyarı rengi + açıklama ile işaretli.
 */
const { success, danger } = useToast();

const loading = ref(true);
const meta = ref<StaffMeta | null>(null);

const canManage = computed(() => meta.value?.actor.can_manage_roles ?? false);

/* ---- Editör durumu ---- */
const selectedId = ref<number | null>(null);
const editor = ref({ name: '', description: '', granted: [] as string[] });
const dirty = ref(false);
const saving = ref(false);
const errors = ref<Record<string, string>>({});

const selectedRole = computed<RoleSummary | null>(
    () => meta.value?.roles.find((r) => r.id === selectedId.value) ?? null,
);
const isNew = computed(() => selectedId.value === null && creating.value);
const readonlyMatrix = computed(() => {
    if (isNew.value) return false;
    return !canManage.value || (selectedRole.value?.is_system ?? false);
});

/* ---- Yeni rol (şablondan başlat) ---- */
const creating = ref(false);
const templateKey = ref('');

const templateOptions = computed(() => [
    { value: '', label: 'Boş başla (izinleri elle seç)' },
    ...(meta.value?.templates ?? []).map((t) => ({ value: t.key, label: `${t.name} gibi başlat` })),
]);

function selectRole(role: RoleSummary): void {
    creating.value = false;
    selectedId.value = role.id;
    editor.value = {
        name: role.name,
        description: role.description ?? '',
        granted: [...role.permission_keys],
    };
    dirty.value = false;
    errors.value = {};
}

function startCreate(): void {
    creating.value = true;
    selectedId.value = null;
    templateKey.value = '';
    editor.value = { name: '', description: '', granted: [] };
    dirty.value = false;
    errors.value = {};
}

function applyTemplate(key: string): void {
    templateKey.value = key;
    const template = meta.value?.templates.find((t) => t.key === key);
    if (!template) {
        editor.value = { ...editor.value, granted: [] };
        return;
    }
    if (!editor.value.name) editor.value.name = template.name;
    if (!editor.value.description) editor.value.description = template.description;
    // Aktörün kendinde olmayan izinler şablondan da açılamaz (sunucu da engeller)
    const actorSet = new Set(meta.value?.actor.permissions ?? []);
    editor.value.granted = template.permissions.filter((k) => actorSet.has(k));
    dirty.value = true;
}

function onGranted(keys: string[]): void {
    editor.value.granted = keys;
    dirty.value = true;
}

/** İzin anahtarlarını sunucunun beklediği id listesine çevirir. */
function keysToIds(keys: string[]): number[] {
    const map = new Map<string, number>();
    for (const mod of meta.value?.catalog ?? []) {
        for (const p of mod.permissions) if (p.id !== null) map.set(p.key, p.id);
    }
    return keys.map((k) => map.get(k)).filter((id): id is number => id !== undefined);
}

async function loadMeta(): Promise<void> {
    loading.value = true;
    try {
        meta.value = await api<StaffMeta>('/api/v1/staff-access/meta');
        // Seçim koru / ilk rolü seç
        const current = meta.value.roles.find((r) => r.id === selectedId.value);
        if (current) selectRole(current);
        else if (!creating.value && meta.value.roles.length > 0) selectRole(meta.value.roles[0]);
    } catch (e) {
        danger('Roller yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(loadMeta);

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};
    try {
        if (isNew.value) {
            const result = await api<{ role: { id: number } }>('/api/v1/roles', {
                method: 'POST',
                body: {
                    name: editor.value.name,
                    description: editor.value.description || null,
                    permissions: keysToIds(editor.value.granted),
                },
            });
            success('Rol oluşturuldu', editor.value.name);
            creating.value = false;
            selectedId.value = result.role.id;
        } else if (selectedId.value !== null) {
            await api(`/api/v1/roles/${selectedId.value}`, {
                method: 'PUT',
                body: {
                    name: editor.value.name,
                    description: editor.value.description || null,
                    permissions: keysToIds(editor.value.granted),
                },
            });
            success('Rol güncellendi', editor.value.name);
        }
        dirty.value = false;
        await loadMeta();
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [field, msgs] of Object.entries(e.errors)) errors.value[field] = msgs[0] ?? '';
            danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Lütfen tekrar deneyin.');
        }
    } finally {
        saving.value = false;
    }
}

async function copyRole(role: RoleSummary): Promise<void> {
    try {
        const result = await api<{ role: { id: number } }>(`/api/v1/roles/${role.id}/copy`, { method: 'POST', body: {} });
        success('Rol kopyalandı', `${role.name} (Kopya)`);
        selectedId.value = result.role.id;
        creating.value = false;
        await loadMeta();
    } catch (e) {
        danger('Kopyalanamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    }
}

/* ---- Silme ---- */
const deleteTarget = ref<RoleSummary | null>(null);
const deleting = ref(false);

async function deleteRole(): Promise<void> {
    const role = deleteTarget.value;
    if (!role || deleting.value) return;
    deleting.value = true;
    try {
        await api(`/api/v1/roles/${role.id}`, { method: 'DELETE' });
        success('Rol silindi', role.name);
        deleteTarget.value = null;
        if (selectedId.value === role.id) selectedId.value = null;
        await loadMeta();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        deleting.value = false;
    }
}
</script>

<template>
    <Head title="Roller & Yetkiler" />
    <StaffShell title="Roller & Yetkiler">
        <div class="grid grid-cols-1 gap-4 lg:grid-cols-[280px_1fr]">
            <!-- Sol: rol listesi -->
            <div class="flex flex-col gap-2">
                <BaseButton v-if="canManage" block @click="startCreate">
                    <AppIcon name="plus" :size="16" />
                    Yeni Rol
                </BaseButton>

                <template v-if="loading">
                    <BaseSkeleton v-for="i in 4" :key="i" class="h-14 w-full" />
                </template>

                <template v-else>
                <button
                    v-for="role in meta?.roles ?? []"
                    :key="role.id"
                    type="button"
                    class="flex flex-col gap-0.5 rounded-lg border px-3 py-2.5 text-left transition-colors duration-(--dur-fast)"
                    :class="
                        selectedId === role.id && !creating
                            ? 'border-primary bg-primary-soft'
                            : 'border-default bg-raised hover:border-strong'
                    "
                    @click="selectRole(role)"
                >
                    <span class="flex items-center gap-1.5">
                        <span class="text-sm font-medium text-body">{{ role.name }}</span>
                        <BaseBadge v-if="role.is_system" variant="primary" no-icon>sistem</BaseBadge>
                    </span>
                    <span class="text-xs text-subtle">
                        {{ role.users_count }} kişi · {{ role.permission_keys.length }} izin
                    </span>
                </button>
                </template>
            </div>

            <!-- Sağ: editör + matris -->
            <div class="flex min-w-0 flex-col gap-4">
                <template v-if="loading">
                    <BaseSkeleton class="h-40 w-full" />
                </template>

                <EmptyState
                    v-else-if="!creating && !selectedRole"
                    icon="users"
                    title="Rol seçin"
                    description="Soldan bir rol seçin veya yeni rol oluşturun."
                />

                <template v-else>
                    <div class="flex flex-col gap-4 rounded-lg border border-default bg-raised p-4">
                        <div class="flex flex-wrap items-center justify-between gap-2">
                            <h2 class="text-base font-semibold text-body">
                                {{ isNew ? 'Yeni Rol' : editor.name || selectedRole?.name }}
                            </h2>
                            <span class="flex gap-2">
                                <BaseButton
                                    v-if="!isNew && canManage && selectedRole"
                                    size="sm"
                                    variant="secondary"
                                    @click="copyRole(selectedRole)"
                                >
                                    Kopyala
                                </BaseButton>
                                <BaseButton
                                    v-if="!isNew && canManage && selectedRole && !selectedRole.is_system"
                                    size="sm"
                                    variant="danger"
                                    @click="deleteTarget = selectedRole"
                                >
                                    Sil
                                </BaseButton>
                            </span>
                        </div>

                        <p v-if="selectedRole?.is_system && !isNew" class="flex items-center gap-2 rounded-md bg-warning-soft px-3 py-2 text-xs text-warning">
                            <AppIcon name="alert-triangle" :size="14" />
                            Sistem rolü: silinemez ve izin seti değiştirilemez (işletme sahibi kilitlenemez).
                        </p>

                        <FormField v-if="isNew" label="Şablondan başlat" hint="Hazır bir setle başlayıp özelleştirebilirsiniz.">
                            <BaseSelect :model-value="templateKey" :options="templateOptions" @update:model-value="applyTemplate(String($event))" />
                        </FormField>

                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <FormField label="Rol adı" required :error="errors.name">
                                <BaseInput v-model="editor.name" :disabled="readonlyMatrix" @update:model-value="dirty = true" />
                            </FormField>
                            <FormField label="Açıklama" :error="errors.description">
                                <BaseInput v-model="editor.description" :disabled="readonlyMatrix" @update:model-value="dirty = true" />
                            </FormField>
                        </div>
                        <p v-if="errors.permissions" class="text-xs text-danger">{{ errors.permissions }}</p>
                    </div>

                    <PermissionMatrix
                        mode="role"
                        :catalog="meta?.catalog ?? []"
                        :granted="editor.granted"
                        :actor-permissions="meta?.actor.permissions ?? []"
                        :readonly="readonlyMatrix"
                        @update:granted="onGranted"
                    />

                    <div v-if="!readonlyMatrix" class="sticky bottom-0 flex items-center justify-between gap-2 border-t border-default bg-raised py-3">
                        <span class="text-xs text-subtle">
                            {{ editor.granted.length }} izin seçili
                            <template v-if="dirty"> · kaydedilmemiş değişiklik var</template>
                        </span>
                        <BaseButton :loading="saving" :disabled="!dirty && !isNew" @click="save">
                            {{ isNew ? 'Rolü Oluştur' : 'Değişiklikleri Kaydet' }}
                        </BaseButton>
                    </div>
                </template>
            </div>
        </div>

        <BaseModal :open="deleteTarget !== null" title="Rolü sil" size="sm" @close="deleteTarget = null">
            <div class="flex flex-col gap-4">
                <p class="text-sm text-body">
                    <strong>{{ deleteTarget?.name }}</strong> rolü silinecek.
                    <template v-if="(deleteTarget?.users_count ?? 0) > 0">
                        Bu rol {{ deleteTarget?.users_count }} kişiye atanmış — silinirse bu kişiler rolden gelen izinlerini kaybeder.
                    </template>
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="deleteTarget = null">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="deleting" @click="deleteRole">Sil</BaseButton>
                </div>
            </div>
        </BaseModal>
    </StaffShell>
</template>
