<script setup lang="ts">
import { ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import PermissionMatrix from './PermissionMatrix.vue';
import type { OverrideSets, StaffMeta, StaffRow } from '../types';

/**
 * Kişi bazlı yetki istisnaları: rol setinin üstüne ek (+) / eksik (−).
 * Matris hücrelerinde kaynak rozeti görünür: "rolden" / "kişiye özel".
 */
const props = defineProps<{
    open: boolean;
    meta: StaffMeta | null;
    staff: StaffRow | null;
}>();

const emit = defineEmits<{ close: []; saved: [] }>();

const { success, danger } = useToast();

const loading = ref(false);
const saving = ref(false);
const roleKeys = ref<string[]>([]);
const overrides = ref<OverrideSets>({ grant: [], revoke: [] });

watch(
    () => [props.open, props.staff?.id],
    async () => {
        if (!props.open || !props.staff) return;
        loading.value = true;
        try {
            const result = await api<{ role_permissions: string[]; overrides: OverrideSets }>(
                `/api/v1/staff-access/${props.staff.id}/effective`,
            );
            roleKeys.value = result.role_permissions;
            overrides.value = result.overrides;
        } catch (e) {
            danger('İzinler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
            emit('close');
        } finally {
            loading.value = false;
        }
    },
    { immediate: true },
);

async function save(): Promise<void> {
    if (!props.staff || saving.value) return;
    saving.value = true;
    try {
        await api(`/api/v1/staff-access/${props.staff.id}/overrides`, {
            method: 'PUT',
            body: { grants: overrides.value.grant, revokes: overrides.value.revoke },
        });
        success('İstisnalar kaydedildi', `${props.staff.name} için kişiye özel izinler güncellendi.`);
        emit('saved');
        emit('close');
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        saving.value = false;
    }
}
</script>

<template>
    <BaseDrawer
        :open="open"
        :title="staff ? `Yetki İstisnaları — ${staff.name}` : 'Yetki İstisnaları'"
        width-class="sm:max-w-2xl"
        @close="emit('close')"
    >
        <div class="flex flex-col gap-4">
            <p class="text-sm text-muted">
                Bu ekran rol setini DEĞİŞTİRMEZ; yalnız bu kişiye özel ek (+) veya eksik (−) izin yazar.
                Rozetler kaynağı gösterir: <strong>rolden</strong> geliyor / <strong>kişiye özel</strong>.
            </p>

            <template v-if="loading">
                <BaseSkeleton v-for="i in 4" :key="i" class="h-24 w-full" />
            </template>

            <PermissionMatrix
                v-else
                mode="user"
                :catalog="meta?.catalog ?? []"
                :role-keys="roleKeys"
                v-model:overrides="overrides"
                :actor-permissions="meta?.actor.permissions ?? []"
            />

            <div class="sticky bottom-0 flex justify-end gap-2 border-t border-default bg-raised py-3">
                <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">İstisnaları Kaydet</BaseButton>
            </div>
        </div>
    </BaseDrawer>
</template>
