<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError, type FieldErrors } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { usePermissions } from '@/composables/usePermissions';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CatalogShell from '../components/CatalogShell.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import { CHANNEL_LABELS, DAY_LABELS, toHm, type CategoryRow, type MenuRow } from '../types';

const { success, danger } = useToast();

// Arayüz gizleme: catalog.* yönetim izni yoksa yalnız görüntüleme.
const { can } = usePermissions();
const canCreate = computed(() => can('catalog.create'));
const canUpdate = computed(() => can('catalog.update'));
const canDelete = computed(() => can('catalog.delete'));

const loading = ref(true);
const menus = ref<MenuRow[]>([]);
const categories = ref<CategoryRow[]>([]);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const result = await api<{ menus: MenuRow[]; categories: CategoryRow[] }>('/api/v1/catalog/menus');
        menus.value = result.menus;
        categories.value = result.categories;
    } catch (e) {
        danger('Menüler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

const daysText = (menu: MenuRow): string => {
    if (!menu.days || menu.days.length === 0 || menu.days.length === 7) return 'Her gün';
    return menu.days.map((d) => DAY_LABELS[d]).join(', ');
};

const hoursText = (menu: MenuRow): string =>
    menu.start_time && menu.end_time ? `${toHm(menu.start_time)}–${toHm(menu.end_time)}` : 'Gün boyu';

const channelsText = (menu: MenuRow): string => {
    if (!menu.channels || menu.channels.length === 0) return 'Tüm kanallar';
    return menu.channels.map((c) => CHANNEL_LABELS[c] ?? c).join(', ');
};

/* ---- Form ---- */
const drawerOpen = ref(false);
const editing = ref<MenuRow | null>(null);
const saving = ref(false);
const errors = ref<FieldErrors>({});
const err = (f: string): string => errors.value[f]?.[0] ?? '';

const form = ref({
    name: '',
    description: '',
    days: [] as number[],
    start_time: '',
    end_time: '',
    channels: [] as string[],
    is_active: true,
    category_ids: [] as number[],
});

const rootCategories = computed(() => categories.value.filter((c) => c.parent_id === null));

function openCreate(): void {
    editing.value = null;
    errors.value = {};
    form.value = { name: '', description: '', days: [], start_time: '', end_time: '', channels: [], is_active: true, category_ids: [] };
    drawerOpen.value = true;
}

function openEdit(menu: MenuRow): void {
    editing.value = menu;
    errors.value = {};
    form.value = {
        name: menu.name,
        description: menu.description ?? '',
        days: menu.days ? [...menu.days] : [],
        start_time: toHm(menu.start_time),
        end_time: toHm(menu.end_time),
        channels: menu.channels ? [...menu.channels] : [],
        is_active: menu.is_active,
        category_ids: menu.categories.map((c) => c.id),
    };
    drawerOpen.value = true;
}

function toggleDay(day: number): void {
    form.value.days = form.value.days.includes(day)
        ? form.value.days.filter((d) => d !== day)
        : [...form.value.days, day];
}

function toggleChannel(key: string): void {
    form.value.channels = form.value.channels.includes(key)
        ? form.value.channels.filter((c) => c !== key)
        : [...form.value.channels, key];
}

function toggleCategory(id: number): void {
    form.value.category_ids = form.value.category_ids.includes(id)
        ? form.value.category_ids.filter((c) => c !== id)
        : [...form.value.category_ids, id];
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};

    const body = {
        name: form.value.name,
        description: form.value.description || null,
        days: form.value.days.length > 0 ? form.value.days : null,
        start_time: form.value.start_time || null,
        end_time: form.value.end_time || null,
        channels: form.value.channels.length > 0 ? form.value.channels : null,
        is_active: form.value.is_active,
        category_ids: form.value.category_ids,
    };

    try {
        if (editing.value) {
            await api(`/api/v1/catalog/menus/${editing.value.id}`, { method: 'PUT', body });
            success('Menü güncellendi');
        } else {
            await api('/api/v1/catalog/menus', { method: 'POST', body });
            success('Menü oluşturuldu');
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

const deleteTarget = ref<MenuRow | null>(null);
const deleteBusy = ref(false);

async function destroyMenu(): Promise<void> {
    if (!deleteTarget.value || deleteBusy.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/catalog/menus/${deleteTarget.value.id}`, { method: 'DELETE' });
        success('Menü silindi');
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
    <Head title="Menü — Menü Planlama" />

    <CatalogShell title="Menü Yönetimi">
        <div class="flex flex-col gap-4">
            <div class="flex flex-wrap items-center gap-2">
                <p class="text-sm text-muted">
                    Kahvaltı, öğle, akşam gibi menüler tanımlayın; gün, saat ve kanal kurallarıyla hangi
                    kategorilerin görüneceğini planlayın.
                </p>
                <div class="grow" />
                <BaseButton v-if="canCreate" @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Yeni Menü
                </BaseButton>
            </div>

            <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
                <BaseSkeleton v-for="i in 4" :key="i" size-class="h-32 w-full" />
            </div>

            <EmptyState
                v-else-if="menus.length === 0"
                icon="inbox"
                title="Henüz menü planı yok"
                description="Ör. 07:00–12:00 arası geçerli bir 'Kahvaltı Menüsü' oluşturun."
            >
                <template v-if="canCreate" #action>
                    <BaseButton @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Yeni Menü
                    </BaseButton>
                </template>
            </EmptyState>

            <div v-else class="grid gap-3 sm:grid-cols-2">
                <article
                    v-for="menu in menus"
                    :key="menu.id"
                    class="flex flex-col gap-2 rounded-md border border-default bg-surface p-4"
                >
                    <header class="flex items-start justify-between gap-2">
                        <div>
                            <h3 class="flex items-center gap-2 font-medium text-body">
                                {{ menu.name }}
                                <BaseBadge v-if="!menu.is_active" variant="neutral">Pasif</BaseBadge>
                            </h3>
                            <p v-if="menu.description" class="text-xs text-muted">{{ menu.description }}</p>
                        </div>
                        <div v-if="canUpdate || canDelete" class="flex gap-1">
                            <BaseButton v-if="canUpdate" size="sm" variant="ghost" icon-only :label="`${menu.name} düzenle`" @click="openEdit(menu)">
                                <AppIcon name="pencil" :size="15" />
                            </BaseButton>
                            <BaseButton v-if="canDelete" size="sm" variant="ghost" icon-only :label="`${menu.name} sil`" @click="deleteTarget = menu">
                                <AppIcon name="trash" :size="15" />
                            </BaseButton>
                        </div>
                    </header>
                    <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
                        <dt class="text-subtle">Günler</dt>
                        <dd class="text-body">{{ daysText(menu) }}</dd>
                        <dt class="text-subtle">Saatler</dt>
                        <dd class="text-body">{{ hoursText(menu) }}</dd>
                        <dt class="text-subtle">Kanallar</dt>
                        <dd class="text-body">{{ channelsText(menu) }}</dd>
                    </dl>
                    <div class="flex flex-wrap gap-1.5 border-t border-default pt-2">
                        <span
                            v-for="category in menu.categories"
                            :key="category.id"
                            class="rounded-full border border-default bg-surface-alt px-2.5 py-1 text-xs text-body"
                        >
                            {{ category.name }}
                        </span>
                        <span v-if="menu.categories.length === 0" class="text-xs text-subtle">Kategori atanmadı</span>
                    </div>
                </article>
            </div>
        </div>

        <BaseDrawer
            :open="drawerOpen"
            :title="editing ? 'Menüyü Düzenle' : 'Yeni Menü'"
            width-class="sm:max-w-lg"
            @close="drawerOpen = false"
        >
            <div class="flex flex-col gap-4">
                <FormField label="Menü adı" required :error="err('name')">
                    <BaseInput v-model="form.name" placeholder="Ör. Kahvaltı Menüsü" />
                </FormField>
                <FormField label="Açıklama" :error="err('description')">
                    <BaseInput v-model="form.description" />
                </FormField>

                <div>
                    <p class="mb-1.5 text-sm font-medium text-body">Günler <span class="font-normal text-muted">(hiçbiri seçilmezse her gün)</span></p>
                    <div class="flex flex-wrap gap-1.5">
                        <button
                            v-for="(label, day) in DAY_LABELS"
                            :key="day"
                            type="button"
                            class="rounded-md border px-3 py-1.5 text-sm transition-colors duration-(--dur-fast)"
                            :class="form.days.includes(Number(day))
                                ? 'border-primary bg-primary-soft font-medium text-primary'
                                : 'border-default bg-surface-alt text-body hover:border-strong'"
                            :aria-pressed="form.days.includes(Number(day))"
                            @click="toggleDay(Number(day))"
                        >
                            {{ label }}
                        </button>
                    </div>
                    <p v-if="err('days')" class="mt-1 text-xs font-medium text-danger">{{ err('days') }}</p>
                </div>

                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Başlangıç saati" hint="Boşsa gün boyu" :error="err('start_time')">
                        <BaseInput v-model="form.start_time" type="time" />
                    </FormField>
                    <FormField label="Bitiş saati" :error="err('end_time')">
                        <BaseInput v-model="form.end_time" type="time" />
                    </FormField>
                </div>

                <div>
                    <p class="mb-1 text-sm font-medium text-body">Kanallar <span class="font-normal text-muted">(hiçbiri seçilmezse tümü)</span></p>
                    <div class="flex flex-wrap gap-x-6">
                        <BaseCheckbox
                            v-for="(label, key) in CHANNEL_LABELS"
                            :key="key"
                            :model-value="form.channels.includes(key)"
                            :label="label"
                            @update:model-value="toggleChannel(key)"
                        />
                    </div>
                </div>

                <div>
                    <p class="mb-1 text-sm font-medium text-body">Bu menüde görünecek kategoriler</p>
                    <p v-if="rootCategories.length === 0" class="text-sm text-subtle">Önce kategori oluşturun.</p>
                    <div class="flex flex-col">
                        <BaseCheckbox
                            v-for="category in rootCategories"
                            :key="category.id"
                            :model-value="form.category_ids.includes(category.id)"
                            :label="category.name"
                            @update:model-value="toggleCategory(category.id)"
                        />
                    </div>
                </div>

                <BaseCheckbox v-model="form.is_active" label="Aktif" />
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
            </template>
        </BaseDrawer>

        <ConfirmModal
            :open="deleteTarget !== null"
            title="Menüyü sil"
            :message="`&quot;${deleteTarget?.name ?? ''}&quot; menü planı silinecek; kategori ve ürünler silinmez.`"
            :busy="deleteBusy"
            @close="deleteTarget = null"
            @confirm="destroyMenu"
        />
    </CatalogShell>
</template>
