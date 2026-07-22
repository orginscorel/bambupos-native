<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError, type FieldErrors } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CatalogShell from '../components/CatalogShell.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import { useDragSort } from '../components/useDragSort';
import { toHm, type CategoryRow } from '../types';

const { success, danger } = useToast();

const loading = ref(true);
const categories = ref<CategoryRow[]>([]);

/** Kök kategoriler sıralı; altları ebeveyninin altında girintili. */
const roots = computed(() => categories.value.filter((c) => c.parent_id === null));
const childrenOf = (id: number) => categories.value.filter((c) => c.parent_id === id);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const result = await api<{ categories: CategoryRow[] }>('/api/v1/catalog/categories');
        categories.value = result.categories;
    } catch (e) {
        danger('Kategoriler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Sürükle-bırak (kök seviyesi) ---- */
const rootList = computed({
    get: () => roots.value,
    set: (items: CategoryRow[]) => {
        const childs = categories.value.filter((c) => c.parent_id !== null);
        categories.value = [...items, ...childs];
    },
});

const drag = useDragSort(
    () => rootList.value,
    (items) => (rootList.value = items),
    (ids) => {
        void api('/api/v1/catalog/categories/reorder', { method: 'POST', body: { ids } })
            .then(() => success('Sıralama kaydedildi'))
            .catch((e) => danger('Sıralama kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Tekrar deneyin.'));
    },
);

/* ---- Form (drawer) ---- */
const drawerOpen = ref(false);
const editing = ref<CategoryRow | null>(null);
const saving = ref(false);
const errors = ref<FieldErrors>({});
const err = (f: string): string => errors.value[f]?.[0] ?? '';

const form = ref({
    name: '',
    description: '',
    parent_id: '' as string,
    color: '',
    available_from: '',
    available_until: '',
    is_active: true,
});

const parentOptions = computed(() => [
    { value: '', label: '— Ana kategori —' },
    ...roots.value
        .filter((c) => c.id !== editing.value?.id)
        .map((c) => ({ value: String(c.id), label: c.name })),
]);

function openCreate(): void {
    editing.value = null;
    errors.value = {};
    form.value = { name: '', description: '', parent_id: '', color: '', available_from: '', available_until: '', is_active: true };
    drawerOpen.value = true;
}

function openEdit(category: CategoryRow): void {
    editing.value = category;
    errors.value = {};
    form.value = {
        name: category.name,
        description: category.description ?? '',
        parent_id: category.parent_id ? String(category.parent_id) : '',
        color: category.color ?? '',
        available_from: toHm(category.available_from),
        available_until: toHm(category.available_until),
        is_active: category.is_active,
    };
    drawerOpen.value = true;
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};

    const body = {
        name: form.value.name,
        description: form.value.description || null,
        parent_id: form.value.parent_id ? Number(form.value.parent_id) : null,
        color: form.value.color || null,
        available_from: form.value.available_from || null,
        available_until: form.value.available_until || null,
        is_active: form.value.is_active,
    };

    try {
        if (editing.value) {
            await api(`/api/v1/catalog/categories/${editing.value.id}`, { method: 'PUT', body });
            success('Kategori güncellendi');
        } else {
            await api('/api/v1/catalog/categories', { method: 'POST', body });
            success('Kategori oluşturuldu');
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

/* ---- Silme ---- */
const deleteTarget = ref<CategoryRow | null>(null);
const deleteBusy = ref(false);

async function destroyCategory(): Promise<void> {
    if (!deleteTarget.value || deleteBusy.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/catalog/categories/${deleteTarget.value.id}`, { method: 'DELETE' });
        success('Kategori silindi');
        deleteTarget.value = null;
        await load();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        deleteBusy.value = false;
    }
}

const serviceHours = (c: CategoryRow): string =>
    c.available_from && c.available_until ? `${toHm(c.available_from)}–${toHm(c.available_until)}` : '';
</script>

<template>
    <Head title="Menü — Kategoriler" />

    <CatalogShell title="Menü Yönetimi">
        <div class="flex flex-col gap-4">
            <div class="flex flex-wrap items-center gap-2">
                <p class="text-sm text-muted">Kategorileri sürükleyerek menü sırasını değiştirebilirsiniz.</p>
                <div class="grow" />
                <BaseButton @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Yeni Kategori
                </BaseButton>
            </div>

            <div v-if="loading" class="flex flex-col gap-2">
                <BaseSkeleton v-for="i in 5" :key="i" size-class="h-14 w-full" />
            </div>

            <EmptyState
                v-else-if="categories.length === 0"
                icon="inbox"
                title="Henüz kategori yok"
                description="Menünüzü düzenlemek için ilk kategoriyi oluşturun."
            >
                <template #action>
                    <BaseButton @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Yeni Kategori
                    </BaseButton>
                </template>
            </EmptyState>

            <ul v-else class="flex flex-col gap-2">
                <li
                    v-for="(category, index) in roots"
                    :key="category.id"
                    :draggable="true"
                    :class="drag.dragIndex.value === index ? 'opacity-60' : ''"
                    @dragstart="drag.onDragStart(index, $event)"
                    @dragover="drag.onDragOver(index, $event)"
                    @drop="drag.onDrop($event)"
                    @dragend="drag.onDragEnd()"
                >
                    <div class="flex items-center gap-3 rounded-md border border-default bg-surface p-3">
                        <span class="cursor-grab text-subtle" aria-hidden="true"><AppIcon name="menu" :size="16" /></span>
                        <span
                            class="size-3 shrink-0 rounded-full"
                            :style="{ backgroundColor: category.color ?? '#9ca3af' }"
                            aria-hidden="true"
                        />
                        <div class="flex min-w-0 grow flex-col">
                            <span class="flex flex-wrap items-center gap-2">
                                <span class="font-medium text-body">{{ category.name }}</span>
                                <BaseBadge v-if="!category.is_active" variant="neutral">Pasif</BaseBadge>
                                <BaseBadge v-if="serviceHours(category)" variant="info" no-icon>{{ serviceHours(category) }}</BaseBadge>
                            </span>
                            <span class="truncate text-xs text-muted">
                                {{ category.products_count ?? 0 }} ürün<template v-if="category.description"> · {{ category.description }}</template>
                            </span>
                        </div>
                        <BaseButton size="sm" variant="ghost" icon-only :label="`${category.name} düzenle`" @click="openEdit(category)">
                            <AppIcon name="pencil" :size="15" />
                        </BaseButton>
                        <BaseButton size="sm" variant="ghost" icon-only :label="`${category.name} sil`" @click="deleteTarget = category">
                            <AppIcon name="trash" :size="15" />
                        </BaseButton>
                    </div>

                    <!-- Alt kategoriler -->
                    <ul v-if="childrenOf(category.id).length" class="mt-1 ml-8 flex flex-col gap-1">
                        <li
                            v-for="child in childrenOf(category.id)"
                            :key="child.id"
                            class="flex items-center gap-3 rounded-md border border-default bg-surface-alt p-2.5"
                        >
                            <AppIcon name="chevron-right" :size="14" class="text-subtle" />
                            <div class="flex min-w-0 grow flex-col">
                                <span class="flex items-center gap-2 text-sm font-medium text-body">
                                    {{ child.name }}
                                    <BaseBadge v-if="!child.is_active" variant="neutral">Pasif</BaseBadge>
                                </span>
                                <span class="text-xs text-muted">{{ child.products_count ?? 0 }} ürün</span>
                            </div>
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${child.name} düzenle`" @click="openEdit(child)">
                                <AppIcon name="pencil" :size="15" />
                            </BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${child.name} sil`" @click="deleteTarget = child">
                                <AppIcon name="trash" :size="15" />
                            </BaseButton>
                        </li>
                    </ul>
                </li>
            </ul>
        </div>

        <!-- Ekle/Düzenle drawer -->
        <BaseDrawer :open="drawerOpen" :title="editing ? 'Kategoriyi Düzenle' : 'Yeni Kategori'" @close="drawerOpen = false">
            <div class="flex flex-col gap-4">
                <FormField label="Kategori adı" required :error="err('name')">
                    <BaseInput v-model="form.name" placeholder="Ör. Ana Yemekler" />
                </FormField>
                <FormField label="Açıklama" :error="err('description')">
                    <BaseInput v-model="form.description" placeholder="Menüde görünen kısa açıklama" />
                </FormField>
                <FormField label="Üst kategori" hint="Boşsa ana kategori olur" :error="err('parent_id')">
                    <BaseSelect v-model="form.parent_id" :options="parentOptions" />
                </FormField>
                <FormField label="Renk" hint="Menüde kategori vurgusu" :error="err('color')">
                    <div class="flex items-center gap-2">
                        <input
                            v-model="form.color"
                            type="color"
                            class="h-10 w-14 cursor-pointer rounded-md border border-strong bg-raised"
                            aria-label="Kategori rengi"
                        />
                        <BaseButton v-if="form.color" size="sm" variant="ghost" @click="form.color = ''">Rengi kaldır</BaseButton>
                    </div>
                </FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Servis başlangıcı" hint="Boşsa gün boyu" :error="err('available_from')">
                        <BaseInput v-model="form.available_from" type="time" />
                    </FormField>
                    <FormField label="Servis bitişi" :error="err('available_until')">
                        <BaseInput v-model="form.available_until" type="time" />
                    </FormField>
                </div>
                <BaseSwitch v-model="form.is_active" label="Aktif" description="Pasif kategoriler menüde görünmez." />
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
            </template>
        </BaseDrawer>

        <ConfirmModal
            :open="deleteTarget !== null"
            title="Kategoriyi sil"
            :message="`&quot;${deleteTarget?.name ?? ''}&quot; silinecek. İçinde ürün varsa önce taşımanız istenir.`"
            :busy="deleteBusy"
            @close="deleteTarget = null"
            @confirm="destroyCategory"
        />
    </CatalogShell>
</template>
