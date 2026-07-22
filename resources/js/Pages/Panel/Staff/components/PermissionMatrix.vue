<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import type { CatalogModule, OverrideSets } from '../types';

/**
 * YETKİ MATRİSİ — modül × işlem; her hücre bir SWITCH.
 *
 * İki kip:
 *  - mode="role": rolün izin seti düzenlenir (v-model:granted, string[]).
 *  - mode="user": kişi bazlı istisna düzenlenir. Rolden gelen taban set
 *    (roleKeys) üstüne grant/revoke yazılır (v-model:overrides).
 *    Hücre rozetinde kaynağı görünür: "rolden" / "kişiye özel + / −".
 *
 * Tehlikeli izinler (config/authz.php 'dangerous') uyarı rengi + ikon +
 * kısa açıklamayla işaretlenir.
 *
 * Yetki yükseltme engeli (sunucuda da zorunlu): aktörün kendinde olmayan
 * izinler AÇILAMAZ — hücre kilitli çizilir.
 */
const props = withDefaults(
    defineProps<{
        catalog: CatalogModule[];
        mode: 'role' | 'user';
        /** role kipi: rolün izin anahtarları */
        granted?: string[];
        /** user kipi: rollerden gelen taban izinler */
        roleKeys?: string[];
        /** user kipi: kişisel istisnalar */
        overrides?: OverrideSets;
        /** Aktörün kendi izinleri (olmayan hücreler kilitli) */
        actorPermissions?: string[];
        readonly?: boolean;
    }>(),
    {
        granted: () => [],
        roleKeys: () => [],
        overrides: () => ({ grant: [], revoke: [] }),
        actorPermissions: () => [],
        readonly: false,
    },
);

const emit = defineEmits<{
    'update:granted': [keys: string[]];
    'update:overrides': [overrides: OverrideSets];
}>();

const grantedSet = computed(() => new Set(props.granted));
const roleSet = computed(() => new Set(props.roleKeys));
const grantSet = computed(() => new Set(props.overrides.grant));
const revokeSet = computed(() => new Set(props.overrides.revoke));
const actorSet = computed(() => new Set(props.actorPermissions));

/** Hücrenin etkin (açık) görünüp görünmeyeceği. */
function isOn(key: string): boolean {
    if (props.mode === 'role') return grantedSet.value.has(key);
    if (revokeSet.value.has(key)) return false;
    if (grantSet.value.has(key)) return true;
    return roleSet.value.has(key);
}

/** İstisna kaynağı: '' | 'role' | 'grant' | 'revoke' (user kipi rozetleri). */
function sourceOf(key: string): '' | 'role' | 'grant' | 'revoke' {
    if (props.mode !== 'user') return '';
    if (grantSet.value.has(key)) return 'grant';
    if (revokeSet.value.has(key)) return 'revoke';
    return roleSet.value.has(key) ? 'role' : '';
}

/** Aktör bu hücreyi AÇABİLİR mi (yetki yükseltme engeli)? Kapatmak serbest. */
function canTurnOn(key: string): boolean {
    return actorSet.value.has(key);
}

function cellDisabled(key: string): boolean {
    if (props.readonly) return true;
    // Kapalı ve aktörde de yoksa açılamaz → kilitli
    return !isOn(key) && !canTurnOn(key);
}

function setCell(key: string, value: boolean): void {
    if (props.readonly) return;

    if (props.mode === 'role') {
        const next = new Set(grantedSet.value);
        if (value) {
            if (!canTurnOn(key)) return;
            next.add(key);
        } else {
            next.delete(key);
        }
        emit('update:granted', [...next]);
        return;
    }

    // user kipi: role göre fark yazılır
    const grant = new Set(grantSet.value);
    const revoke = new Set(revokeSet.value);
    const fromRole = roleSet.value.has(key);

    if (value) {
        if (!canTurnOn(key)) return;
        revoke.delete(key); // rolden geliyorsa revoke'u kaldırmak yeter
        if (!fromRole) grant.add(key);
    } else {
        grant.delete(key);
        if (fromRole) revoke.add(key);
    }

    emit('update:overrides', { grant: [...grant], revoke: [...revoke] });
}

/** Modül başlığındaki "tümünü aç/kapa" durumu. */
function moduleState(mod: CatalogModule): { all: boolean; some: boolean } {
    const states = mod.permissions.map((p) => isOn(p.key));
    return { all: states.length > 0 && states.every(Boolean), some: states.some(Boolean) };
}

function setModule(mod: CatalogModule, value: boolean): void {
    for (const p of mod.permissions) {
        // Açarken aktörde olmayanlar atlanır; kapatma hepsine uygulanır
        if (value && !canTurnOn(p.key)) continue;
        if (isOn(p.key) !== value) setCell(p.key, value);
    }
}
</script>

<template>
    <div class="flex flex-col gap-3">
        <div
            v-for="mod in catalog"
            :key="mod.module"
            class="overflow-hidden rounded-lg border border-default bg-raised"
        >
            <div class="flex items-center justify-between gap-3 border-b border-default bg-surface-alt px-4 py-2.5">
                <span class="text-sm font-semibold text-body">{{ mod.label }}</span>
                <BaseSwitch
                    size="sm"
                    :model-value="moduleState(mod).all"
                    :aria-label="`${mod.label}: tümünü aç/kapa`"
                    label="Tümü"
                    label-position="left"
                    :disabled="readonly"
                    @update:model-value="setModule(mod, $event)"
                />
            </div>

            <ul class="grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3">
                <li
                    v-for="perm in mod.permissions"
                    :key="perm.key"
                    class="flex items-start justify-between gap-3 px-4 py-2.5"
                >
                    <span class="flex min-w-0 flex-col gap-0.5">
                        <span class="flex flex-wrap items-center gap-1.5 text-sm text-body">
                            <AppIcon
                                v-if="perm.dangerous"
                                name="alert-triangle"
                                :size="14"
                                class="shrink-0 text-warning"
                                aria-hidden="true"
                            />
                            {{ perm.label }}
                            <BaseBadge v-if="sourceOf(perm.key) === 'role'" variant="neutral" no-icon>rolden</BaseBadge>
                            <BaseBadge v-else-if="sourceOf(perm.key) === 'grant'" variant="info" no-icon>kişiye özel +</BaseBadge>
                            <BaseBadge v-else-if="sourceOf(perm.key) === 'revoke'" variant="danger" no-icon>kişiye özel −</BaseBadge>
                        </span>
                        <span v-if="perm.dangerous && perm.warning" class="text-xs text-warning">
                            {{ perm.warning }}
                        </span>
                        <span v-if="cellDisabled(perm.key) && !readonly && !isOn(perm.key)" class="text-xs text-subtle">
                            Sizde olmayan izni veremezsiniz.
                        </span>
                    </span>

                    <BaseSwitch
                        size="sm"
                        :model-value="isOn(perm.key)"
                        :variant="perm.dangerous ? 'danger' : 'primary'"
                        :aria-label="`${mod.label} — ${perm.label}`"
                        :disabled="cellDisabled(perm.key)"
                        @update:model-value="setCell(perm.key, $event)"
                    />
                </li>
            </ul>
        </div>
    </div>
</template>
