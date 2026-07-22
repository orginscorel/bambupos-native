<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError, type FieldErrors } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseRadioGroup from '@/Components/ui/BaseRadioGroup.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CatalogShell from '../components/CatalogShell.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import type { AllergenRow } from '../types';

const { success, danger } = useToast();

const loading = ref(true);
const allergens = ref<AllergenRow[]>([]);

const allergenList = computed(() => allergens.value.filter((a) => a.kind === 'allergen'));
const dietList = computed(() => allergens.value.filter((a) => a.kind === 'diet'));

async function load(): Promise<void> {
    loading.value = true;
    try {
        const result = await api<{ allergens: AllergenRow[] }>('/api/v1/catalog/allergens');
        allergens.value = result.allergens;
    } catch (e) {
        danger('Alerjenler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Form (yalnız işletmeye özel satırlar) ---- */
const drawerOpen = ref(false);
const editing = ref<AllergenRow | null>(null);
const saving = ref(false);
const errors = ref<FieldErrors>({});
const err = (f: string): string => errors.value[f]?.[0] ?? '';

const form = ref({
    kind: 'allergen' as 'allergen' | 'diet',
    name: '',
    description: '',
    color: '#f59e0b',
});

function openCreate(): void {
    editing.value = null;
    errors.value = {};
    form.value = { kind: 'allergen', name: '', description: '', color: '#f59e0b' };
    drawerOpen.value = true;
}

function openEdit(allergen: AllergenRow): void {
    editing.value = allergen;
    errors.value = {};
    form.value = {
        kind: allergen.kind,
        name: allergen.name,
        description: allergen.description ?? '',
        color: allergen.color ?? '#f59e0b',
    };
    drawerOpen.value = true;
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};

    const body = {
        kind: form.value.kind,
        name: form.value.name,
        description: form.value.description,
        color: form.value.color || null,
    };

    try {
        if (editing.value) {
            await api(`/api/v1/catalog/allergens/${editing.value.id}`, { method: 'PUT', body });
            success('Kayıt güncellendi');
        } else {
            await api('/api/v1/catalog/allergens', { method: 'POST', body });
            success('Kayıt eklendi');
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

const deleteTarget = ref<AllergenRow | null>(null);
const deleteBusy = ref(false);

async function destroyAllergen(): Promise<void> {
    if (!deleteTarget.value || deleteBusy.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/catalog/allergens/${deleteTarget.value.id}`, { method: 'DELETE' });
        success('Kayıt silindi');
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
    <Head title="Menü — Alerjenler & Diyet" />

    <CatalogShell title="Menü Yönetimi">
        <div class="flex flex-col gap-5">
            <div class="flex flex-wrap items-center gap-2">
                <p class="text-sm text-muted">
                    Standart sözlük (AB 14 alerjeni + diyet etiketleri) hazır gelir ve değiştirilemez;
                    işletmenize özel kayıt ekleyebilirsiniz.
                </p>
                <div class="grow" />
                <BaseButton @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Özel Kayıt Ekle
                </BaseButton>
            </div>

            <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
                <BaseSkeleton v-for="i in 6" :key="i" size-class="h-20 w-full" />
            </div>

            <template v-else>
                <section v-for="(list, kind) in { allergen: allergenList, diet: dietList }" :key="kind">
                    <h2 class="mb-2 text-sm font-semibold text-body">
                        {{ kind === 'allergen' ? 'Alerjenler' : 'Diyet Etiketleri' }}
                    </h2>
                    <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
                        <article
                            v-for="a in list"
                            :key="a.id"
                            class="flex items-start gap-3 rounded-md border border-default bg-surface p-3"
                        >
                            <span
                                class="mt-1 size-3 shrink-0 rounded-full"
                                :style="{ backgroundColor: a.color ?? '#9ca3af' }"
                                aria-hidden="true"
                            />
                            <div class="min-w-0 grow">
                                <p class="flex flex-wrap items-center gap-1.5 text-sm font-medium text-body">
                                    {{ a.name }}
                                    <BaseBadge v-if="a.is_global" variant="neutral" no-icon>Standart</BaseBadge>
                                    <BaseBadge v-else variant="primary" no-icon>İşletmeye özel</BaseBadge>
                                </p>
                                <p class="text-xs text-muted">{{ a.description }}</p>
                                <p class="mt-0.5 text-xs text-subtle">{{ a.products_count ?? 0 }} üründe işaretli</p>
                            </div>
                            <div v-if="!a.is_global" class="flex shrink-0 gap-1">
                                <BaseButton size="sm" variant="ghost" icon-only :label="`${a.name} düzenle`" @click="openEdit(a)">
                                    <AppIcon name="pencil" :size="14" />
                                </BaseButton>
                                <BaseButton size="sm" variant="ghost" icon-only :label="`${a.name} sil`" @click="deleteTarget = a">
                                    <AppIcon name="trash" :size="14" />
                                </BaseButton>
                            </div>
                        </article>
                    </div>
                </section>
            </template>
        </div>

        <BaseDrawer
            :open="drawerOpen"
            :title="editing ? 'Kaydı Düzenle' : 'Özel Kayıt Ekle'"
            @close="drawerOpen = false"
        >
            <div class="flex flex-col gap-4">
                <BaseRadioGroup
                    v-model="form.kind"
                    label="Tür"
                    :options="[
                        { value: 'allergen', label: 'Alerjen', description: 'Ör. işletmeye özel bir içerik uyarısı' },
                        { value: 'diet', label: 'Diyet etiketi', description: 'Ör. \'Ev yapımı\', \'Organik\'' },
                    ]"
                />
                <FormField label="Ad" required :error="err('name')">
                    <BaseInput v-model="form.name" placeholder="Ör. Ev Baharatı Karışımı" />
                </FormField>
                <FormField
                    label="Açıklama"
                    required
                    hint="İkon/renk tek başına yeterli değildir; müşteriye ne anlama geldiği açıklanır."
                    :error="err('description')"
                >
                    <BaseInput v-model="form.description" placeholder="Bu etiketin anlamı" />
                </FormField>
                <FormField label="Renk" :error="err('color')">
                    <input
                        v-model="form.color"
                        type="color"
                        class="h-10 w-14 cursor-pointer rounded-md border border-strong bg-raised"
                        aria-label="Etiket rengi"
                    />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
            </template>
        </BaseDrawer>

        <ConfirmModal
            :open="deleteTarget !== null"
            title="Kaydı sil"
            :message="`&quot;${deleteTarget?.name ?? ''}&quot; silinecek; ürünlerdeki işaretler kaldırılacak.`"
            :busy="deleteBusy"
            @close="deleteTarget = null"
            @confirm="destroyAllergen"
        />
    </CatalogShell>
</template>
