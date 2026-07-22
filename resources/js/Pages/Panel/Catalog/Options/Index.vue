<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError, type FieldErrors } from '@/lib/http';
import { formatCurrencyMinor } from '@/lib/format';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseRadioGroup from '@/Components/ui/BaseRadioGroup.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CatalogShell from '../components/CatalogShell.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import PriceInput from '../components/PriceInput.vue';
import type { OptionGroupRow, OptionRow } from '../types';

const { success, danger } = useToast();

const loading = ref(true);
const groups = ref<OptionGroupRow[]>([]);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const result = await api<{ option_groups: OptionGroupRow[] }>('/api/v1/catalog/option-groups');
        groups.value = result.option_groups;
    } catch (e) {
        danger('Seçenek grupları yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Form ---- */
const drawerOpen = ref(false);
const editing = ref<OptionGroupRow | null>(null);
const saving = ref(false);
const errors = ref<FieldErrors>({});
const err = (f: string): string => errors.value[f]?.[0] ?? '';

const form = ref({
    name: '',
    description: '',
    selection_type: 'multiple' as 'single' | 'multiple',
    is_required: false,
    min_select: '0' as string | number,
    max_select: '' as string | number,
    free_limit: '0' as string | number,
    is_active: true,
});
const options = ref<OptionRow[]>([]);

function openCreate(): void {
    editing.value = null;
    errors.value = {};
    form.value = {
        name: '', description: '', selection_type: 'multiple',
        is_required: false, min_select: '0', max_select: '', free_limit: '0', is_active: true,
    };
    options.value = [{ name: '', price_minor: 0, is_active: true }];
    drawerOpen.value = true;
}

function openEdit(group: OptionGroupRow): void {
    editing.value = group;
    errors.value = {};
    form.value = {
        name: group.name,
        description: group.description ?? '',
        selection_type: group.selection_type,
        is_required: group.is_required,
        min_select: String(group.min_select),
        max_select: group.max_select === null ? '' : String(group.max_select),
        free_limit: String(group.free_limit),
        is_active: group.is_active,
    };
    options.value = group.options.map((o) => ({
        id: o.id, name: o.name, price_minor: o.price_minor, is_default: o.is_default, is_active: o.is_active ?? true,
    }));
    drawerOpen.value = true;
}

function addOption(): void {
    options.value.push({ name: '', price_minor: 0, is_active: true });
}

function removeOption(index: number): void {
    options.value.splice(index, 1);
}

const numOr = (v: string | number, fallback: number | null): number | null => {
    if (v === '' || v === null || v === undefined) return fallback;
    const n = Number(v);
    return Number.isNaN(n) ? fallback : n;
};

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};

    const body = {
        name: form.value.name,
        description: form.value.description || null,
        selection_type: form.value.selection_type,
        is_required: form.value.is_required,
        min_select: numOr(form.value.min_select, 0),
        max_select: numOr(form.value.max_select, null),
        free_limit: numOr(form.value.free_limit, 0),
        is_active: form.value.is_active,
        options: options.value
            .filter((o) => o.name.trim() !== '')
            .map((o) => ({
                id: o.id ?? null,
                name: o.name,
                price_minor: o.price_minor ?? 0,
                is_default: o.is_default ?? false,
                is_active: o.is_active ?? true,
            })),
    };

    try {
        if (editing.value) {
            await api(`/api/v1/catalog/option-groups/${editing.value.id}`, { method: 'PUT', body });
            success('Seçenek grubu güncellendi');
        } else {
            await api('/api/v1/catalog/option-groups', { method: 'POST', body });
            success('Seçenek grubu oluşturuldu');
        }
        drawerOpen.value = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            errors.value = e.errors;
            danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        saving.value = false;
    }
}

const deleteTarget = ref<OptionGroupRow | null>(null);
const deleteBusy = ref(false);

async function destroyGroup(): Promise<void> {
    if (!deleteTarget.value || deleteBusy.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/catalog/option-groups/${deleteTarget.value.id}`, { method: 'DELETE' });
        success('Seçenek grubu silindi');
        deleteTarget.value = null;
        await load();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        deleteBusy.value = false;
    }
}
</script>

<template>
    <Head title="Menü — Seçenek Grupları" />

    <CatalogShell title="Menü Yönetimi">
        <div class="flex flex-col gap-4">
            <div class="flex flex-wrap items-center gap-2">
                <p class="text-sm text-muted">
                    Seçenek grupları ürünlere bağlanır: soslar, ekstra malzemeler, süt tercihi gibi.
                </p>
                <div class="grow" />
                <BaseButton @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Yeni Grup
                </BaseButton>
            </div>

            <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
                <BaseSkeleton v-for="i in 4" :key="i" size-class="h-32 w-full" />
            </div>

            <EmptyState
                v-else-if="groups.length === 0"
                icon="inbox"
                title="Henüz seçenek grubu yok"
                description="Ör. 'Soslar' veya 'Süt Tercihi' grubu oluşturup ürünlere bağlayın."
            >
                <template #action>
                    <BaseButton @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Yeni Grup
                    </BaseButton>
                </template>
            </EmptyState>

            <div v-else class="grid gap-3 sm:grid-cols-2">
                <article
                    v-for="group in groups"
                    :key="group.id"
                    class="flex flex-col gap-2 rounded-md border border-default bg-surface p-4"
                >
                    <header class="flex items-start justify-between gap-2">
                        <div class="flex flex-col gap-1">
                            <h3 class="font-medium text-body">{{ group.name }}</h3>
                            <div class="flex flex-wrap gap-1">
                                <BaseBadge :variant="group.is_required ? 'warning' : 'neutral'">
                                    {{ group.is_required ? 'Zorunlu' : 'Opsiyonel' }}
                                </BaseBadge>
                                <BaseBadge variant="neutral" no-icon>
                                    {{ group.selection_type === 'single' ? 'Tek seçim' : 'Çoklu seçim' }}
                                </BaseBadge>
                                <BaseBadge v-if="group.max_select" variant="neutral" no-icon>En fazla {{ group.max_select }}</BaseBadge>
                                <BaseBadge v-if="group.free_limit > 0" variant="success" no-icon>{{ group.free_limit }} ücretsiz</BaseBadge>
                                <BaseBadge v-if="!group.is_active" variant="neutral">Pasif</BaseBadge>
                            </div>
                        </div>
                        <div class="flex gap-1">
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${group.name} düzenle`" @click="openEdit(group)">
                                <AppIcon name="pencil" :size="15" />
                            </BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${group.name} sil`" @click="deleteTarget = group">
                                <AppIcon name="trash" :size="15" />
                            </BaseButton>
                        </div>
                    </header>
                    <ul class="flex flex-wrap gap-1.5">
                        <li
                            v-for="option in group.options"
                            :key="option.id"
                            class="rounded-full border border-default bg-surface-alt px-2.5 py-1 text-xs text-body"
                        >
                            {{ option.name }}
                            <span v-if="option.price_minor" class="text-muted">+{{ formatCurrencyMinor(option.price_minor) }}</span>
                        </li>
                    </ul>
                    <p class="text-xs text-subtle">{{ group.products_count ?? 0 }} üründe kullanılıyor</p>
                </article>
            </div>
        </div>

        <BaseDrawer
            :open="drawerOpen"
            :title="editing ? 'Grubu Düzenle' : 'Yeni Seçenek Grubu'"
            width-class="sm:max-w-lg"
            @close="drawerOpen = false"
        >
            <div class="flex flex-col gap-4">
                <FormField label="Grup adı" required :error="err('name')">
                    <BaseInput v-model="form.name" placeholder="Ör. Soslar" />
                </FormField>
                <FormField label="Açıklama" :error="err('description')">
                    <BaseInput v-model="form.description" placeholder="Müşteriye gösterilecek açıklama" />
                </FormField>

                <BaseRadioGroup
                    v-model="form.selection_type"
                    label="Seçim türü"
                    :options="[
                        { value: 'multiple', label: 'Çoklu seçim', description: 'Birden fazla seçenek işaretlenebilir' },
                        { value: 'single', label: 'Tek seçim', description: 'Yalnız bir seçenek işaretlenebilir' },
                    ]"
                />

                <BaseCheckbox v-model="form.is_required" label="Zorunlu" description="Müşteri en az bir seçim yapmadan ürünü ekleyemez." />

                <div class="grid grid-cols-3 gap-3">
                    <FormField label="En az seçim" :error="err('min_select')">
                        <BaseInput v-model="form.min_select" inputmode="numeric" :disabled="form.selection_type === 'single'" />
                    </FormField>
                    <FormField label="En fazla seçim" hint="Boşsa sınırsız" :error="err('max_select')">
                        <BaseInput v-model="form.max_select" inputmode="numeric" :disabled="form.selection_type === 'single'" />
                    </FormField>
                    <FormField label="Ücretsiz adet" hint="İlk N seçim ücretsiz" :error="err('free_limit')">
                        <BaseInput v-model="form.free_limit" inputmode="numeric" />
                    </FormField>
                </div>

                <BaseCheckbox v-model="form.is_active" label="Aktif" />

                <div class="border-t border-default pt-3">
                    <div class="mb-2 flex items-center justify-between">
                        <h3 class="text-sm font-semibold text-body">Seçenekler</h3>
                        <BaseButton size="sm" variant="secondary" @click="addOption">
                            <AppIcon name="plus" :size="14" />
                            Seçenek ekle
                        </BaseButton>
                    </div>
                    <p v-if="err('options')" class="mb-2 text-xs font-medium text-danger">{{ err('options') }}</p>
                    <div class="flex flex-col gap-2">
                        <div
                            v-for="(option, index) in options"
                            :key="option.id ?? `new-${index}`"
                            class="flex items-center gap-2 rounded-md border border-default bg-surface-alt p-2"
                        >
                            <input
                                v-model="option.name"
                                type="text"
                                placeholder="Seçenek adı"
                                :aria-label="`Seçenek ${index + 1} adı`"
                                class="h-9 min-w-0 grow rounded-md border border-strong bg-raised px-2.5 text-sm text-body placeholder:text-subtle focus:ring-ring-brand focus:ring-2 focus:outline-none"
                            />
                            <div class="w-32 shrink-0">
                                <PriceInput v-model="option.price_minor" placeholder="Ek ücret" />
                            </div>
                            <BaseButton size="sm" variant="ghost" icon-only :label="`Seçenek ${index + 1} sil`" @click="removeOption(index)">
                                <AppIcon name="trash" :size="14" />
                            </BaseButton>
                        </div>
                    </div>
                </div>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
            </template>
        </BaseDrawer>

        <ConfirmModal
            :open="deleteTarget !== null"
            title="Seçenek grubunu sil"
            :message="`&quot;${deleteTarget?.name ?? ''}&quot; ve içindeki seçenekler silinecek; ürün bağlantıları kaldırılacak.`"
            :busy="deleteBusy"
            @close="deleteTarget = null"
            @confirm="destroyGroup"
        />
    </CatalogShell>
</template>
