<script setup lang="ts">
/**
 * Entegrasyonlar merkezi — TAKILABİLİR ÇERÇEVE. İşletme her dış entegrasyonu
 * (ödeme / teslimat platformu / e-fatura / muhasebe) tek yerden AÇAR/KAPATIR
 * ve yapılandırır. Aktifse sistem uyum sağlar, pasifse çerçeve sessizdir.
 * Gizli alanlar (API anahtarı vb.) maskeli döner; password input ile girilir.
 *
 * İç modüller (Teslimat/Prim) özellik anahtarıyla açılır (Ayarlar › Eklentiler);
 * o bölüm ve bağlantı korunur. API: GET/POST /api/v1/integrations.
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { usePermissions } from '@/composables/usePermissions';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';

/* ----------------------------- Tipler ----------------------------- */

type Category = 'payment' | 'delivery' | 'invoice' | 'accounting';
type Status = 'active' | 'unconfigured' | 'off';

interface ConfigField {
    key: string;
    label: string;
    secret: boolean;
}

interface Integration {
    key: string;
    name: string;
    category: Category;
    description: string;
    config_fields: ConfigField[];
    is_enabled: boolean;
    configured: boolean;
    status: Status;
    config: Record<string, string>;
}

/* ----------------------------- İç modüller (feature-flag) ----------------------------- */

const page = usePage();
const features = computed<Record<string, boolean>>(
    () => ((page.props as Record<string, unknown>).auth as { features?: Record<string, boolean> } | undefined)?.features ?? {},
);

/* Bu sayfa `integrations.manage` ile açılır, ama aşağıdaki iki link
 * (POS/Yazarkasa kurulum sihirbazı + Ayarlar › Eklentiler) hedef rotaları
 * FARKLI bir izin (`settings.manage`) ister. Yalnız-entegrasyon yetkili bir
 * personel bu izne sahip olmayabilir; linkler görünür kalırsa tıklayınca
 * 403 alır. `settings.manage` yoksa gizlenir (403 tuzağı olmasın). */
const { can } = usePermissions();
const canManageSettings = computed(() => can('settings.manage'));

const internal = computed(() => [
    {
        key: 'delivery',
        name: 'Teslimat / Paket',
        desc: 'Paket siparişlerde adres, kurye atama ve teslim durumu takibi.',
        icon: 'truck',
        on: Boolean(features.value.delivery),
    },
    {
        key: 'commission',
        name: 'Prim / Komisyon',
        desc: 'Satış-bazlı prim şeması, hedef takibi ve prim raporu.',
        icon: 'wallet',
        on: Boolean(features.value.commission),
    },
]);

/* ----------------------------- Dış entegrasyonlar ----------------------------- */

const { success, danger } = useToast();

const loading = ref(true);
const loadFailed = ref(false);
const integrations = ref<Integration[]>([]);
/** Anlık aç/kapa isteği süren anahtarlar (çift tık engeli). */
const busy = reactive<Record<string, boolean>>({});

const CATEGORY_META: Record<Category, { label: string; icon: string }> = {
    payment: { label: 'Ödeme', icon: 'wallet' },
    delivery: { label: 'Teslimat platformları', icon: 'truck' },
    invoice: { label: 'Fatura', icon: 'orders' },
    accounting: { label: 'Muhasebe', icon: 'chart' },
};
const CATEGORY_ORDER: Category[] = ['payment', 'delivery', 'invoice', 'accounting'];

/** Kategoriye özel ikon rozeti tonu (görsel ayrım). */
const CATEGORY_TINT: Record<Category, string> = {
    payment: 'bg-(--color-success-soft) text-(--color-success)',
    delivery: 'bg-(--color-warning-soft) text-(--color-warning)',
    invoice: 'bg-(--color-info-soft) text-(--color-info)',
    accounting: 'bg-primary-soft text-primary',
};

const grouped = computed(() =>
    CATEGORY_ORDER.map((cat) => ({
        category: cat,
        meta: CATEGORY_META[cat],
        items: integrations.value.filter((i) => i.category === cat),
    })).filter((g) => g.items.length > 0),
);

function badge(status: Status): { label: string; cls: string } {
    if (status === 'active') return { label: 'Aktif', cls: 'bg-(--color-success-soft) text-(--color-success)' };
    if (status === 'unconfigured') return { label: 'Yapılandırılmadı', cls: 'bg-(--color-warning-soft) text-(--color-warning)' };
    return { label: 'Kapalı', cls: 'bg-inset text-muted' };
}

async function load(): Promise<void> {
    loading.value = true;
    loadFailed.value = false;
    try {
        const data = await api<{ integrations: Integration[] }>('/api/v1/integrations');
        integrations.value = data.integrations;
    } catch {
        loadFailed.value = true;
    } finally {
        loading.value = false;
    }
}

async function toggle(item: Integration, next: boolean): Promise<void> {
    if (busy[item.key]) return;
    busy[item.key] = true;

    const previous = item.is_enabled;
    item.is_enabled = next; // iyimser güncelleme
    try {
        const data = await api<{ integration: Integration }>('/api/v1/integrations/toggle', {
            method: 'POST',
            body: { key: item.key, is_enabled: next },
        });
        replace(data.integration);
        success(next ? `${item.name} açıldı.` : `${item.name} kapatıldı.`);
    } catch (e) {
        item.is_enabled = previous; // geri al
        danger(e instanceof ApiError ? e.displayMessage : 'İşlem tamamlanamadı.');
    } finally {
        busy[item.key] = false;
    }
}

function replace(updated: Integration): void {
    const idx = integrations.value.findIndex((i) => i.key === updated.key);
    if (idx !== -1) integrations.value[idx] = updated;
}

/* ----------------------------- Yapılandırma modalı ----------------------------- */

const configOpen = ref(false);
const configTarget = ref<Integration | null>(null);
const configForm = reactive<Record<string, string>>({});
const saving = ref(false);

function openConfig(item: Integration): void {
    configTarget.value = item;
    // Formu sıfırla: açık alanlar mevcut değerle; GİZLİ alanlar boş (maske
    // asla forma yazılmaz — boş bırakılırsa sunucu mevcut değeri korur).
    Object.keys(configForm).forEach((k) => delete configForm[k]);
    for (const field of item.config_fields) {
        configForm[field.key] = field.secret ? '' : (item.config[field.key] ?? '');
    }
    configOpen.value = true;
}

/** Gizli alan zaten kayıtlıysa (sunucu maske gönderdiyse) ipucu göster. */
function secretSaved(item: Integration, field: ConfigField): boolean {
    return field.secret && Boolean(item.config[field.key]);
}

async function saveConfig(): Promise<void> {
    const item = configTarget.value;
    if (!item || saving.value) return;
    saving.value = true;
    try {
        const data = await api<{ integration: Integration }>('/api/v1/integrations/config', {
            method: 'POST',
            body: { key: item.key, config: { ...configForm } },
        });
        replace(data.integration);
        success(`${item.name} yapılandırması kaydedildi.`);
        configOpen.value = false;
    } catch (e) {
        danger(e instanceof ApiError ? e.displayMessage : 'Kaydedilemedi.');
    } finally {
        saving.value = false;
    }
}

onMounted(load);
</script>

<template>
    <Head title="Entegrasyonlar" />

    <PanelShell title="Entegrasyonlar" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <div class="mx-auto flex w-full max-w-4xl flex-col gap-6">
            <div class="flex flex-col gap-1.5">
                <h1 class="text-2xl font-semibold text-body">Entegrasyonlar</h1>
                <p class="max-w-2xl text-[15px] leading-relaxed text-muted">
                    Ödeme, teslimat platformu, e-fatura ve muhasebe bağlantılarını buradan
                    açıp yapılandırın. Aktif ettiğinizde sistem entegrasyona uyum sağlar;
                    kapalıyken hiçbir yeri etkilemez.
                </p>
            </div>

            <!-- POS / Yazarkasa kurulum sihirbazı (marka-bağımsız entegratör) — HERO.
                 Hedef rota `settings.manage` ister; o izne sahip olmayan
                 (yalnız `integrations.manage`) personelde 403 tuzağı olmasın diye gizli. -->
            <Link
                v-if="canManageSettings"
                href="/panel/entegrasyonlar/pos"
                class="group relative overflow-hidden rounded-2xl border border-primary/30 bg-gradient-to-br from-primary-soft/70 to-surface px-5 py-5 shadow-card transition-all hover:-translate-y-0.5 hover:shadow-lg"
            >
                <AppIcon name="wallet" :size="150" class="pointer-events-none absolute -right-6 -bottom-8 text-primary/10" />
                <div class="relative flex items-center justify-between gap-4">
                    <div class="flex items-center gap-4">
                        <span class="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-primary text-on-primary shadow-md">
                            <AppIcon name="wallet" :size="28" />
                        </span>
                        <div class="flex flex-col gap-1">
                            <div class="flex flex-wrap items-center gap-2">
                                <span class="text-lg font-bold text-body">POS / Yazarkasa Entegrasyonu</span>
                                <span class="rounded-full bg-primary px-2 py-0.5 text-[11px] font-bold text-on-primary">Entegratör</span>
                            </div>
                            <span class="max-w-xl text-sm leading-relaxed text-muted">
                                YN-POS / ÖKC, banka sanal POS veya ödeme kuruluşu — <strong class="text-body">markadan bağımsız</strong>,
                                hepsine uyumlu. Cihazınızı seçip bağlayın; kasa, terminal ve kiosk bu altyapıdan geçer.
                            </span>
                        </div>
                    </div>
                    <span class="hidden shrink-0 items-center gap-1 rounded-full border border-primary/40 bg-surface px-3 py-1.5 text-sm font-semibold text-primary transition-colors group-hover:bg-primary group-hover:text-on-primary sm:inline-flex">
                        Kur / Bağla <AppIcon name="chevron-right" :size="16" />
                    </span>
                </div>
            </Link>

            <!-- İç modüller (feature-flag) -->
            <section>
                <h2 class="mb-1 text-sm font-semibold text-body">Kullanılabilir modüller</h2>
                <p class="mb-3 text-xs text-muted">
                    <template v-if="canManageSettings">
                        Bu modüller sistemin içindedir;
                        <Link href="/panel/ayarlar/eklentiler" class="text-primary underline">Ayarlar › Eklentiler</Link>'den açıp kapatabilirsiniz.
                    </template>
                    <template v-else>
                        Bu modüller sistemin içindedir; açıp kapatma yetkisi Ayarlar bölümündedir.
                    </template>
                </p>
                <div class="grid gap-3 sm:grid-cols-2">
                    <div v-for="it in internal" :key="it.key" class="flex items-start gap-3 rounded-xl border border-default bg-raised p-4">
                        <span class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary-soft text-primary">
                            <AppIcon :name="it.icon" :size="20" />
                        </span>
                        <div class="min-w-0 flex-1">
                            <div class="flex items-center justify-between gap-2">
                                <p class="font-semibold text-body">{{ it.name }}</p>
                                <span
                                    class="rounded-full px-2 py-0.5 text-[11px] font-bold"
                                    :class="it.on ? 'bg-(--color-success-soft) text-(--color-success)' : 'bg-inset text-muted'"
                                >{{ it.on ? 'Aktif' : 'Kapalı' }}</span>
                            </div>
                            <p class="mt-0.5 text-xs text-muted">{{ it.desc }}</p>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Yükleniyor -->
            <template v-if="loading">
                <BaseCard><BaseSkeleton class="h-24" /></BaseCard>
                <BaseCard><BaseSkeleton class="h-24" /></BaseCard>
            </template>

            <!-- Hata -->
            <BaseCard v-else-if="loadFailed" class="text-center">
                <p class="text-sm text-muted">Entegrasyonlar yüklenemedi.</p>
                <button type="button" class="mt-3 text-sm font-medium text-primary hover:underline" @click="load">Yeniden dene</button>
            </BaseCard>

            <!-- Dış entegrasyonlar (kategoriye göre) -->
            <template v-else>
                <section v-for="grp in grouped" :key="grp.category">
                    <h2 class="mb-3 flex items-center gap-2 text-sm font-semibold text-body">
                        <AppIcon :name="grp.meta.icon" :size="16" class="text-muted" />
                        {{ grp.meta.label }}
                    </h2>
                    <BaseCard class="p-0">
                        <ul class="divide-y divide-(--ui-border)">
                            <li v-for="it in grp.items" :key="it.key" class="flex items-start justify-between gap-4 px-4 py-4 sm:px-6">
                                <div class="flex min-w-0 flex-1 items-start gap-3">
                                    <span class="mt-0.5 flex size-10 shrink-0 items-center justify-center rounded-xl" :class="CATEGORY_TINT[grp.category]">
                                        <AppIcon :name="grp.meta.icon" :size="20" />
                                    </span>
                                    <div class="min-w-0 flex flex-col gap-0.5">
                                        <div class="flex items-center gap-2">
                                            <span class="text-[15px] font-semibold text-body">{{ it.name }}</span>
                                            <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" :class="badge(it.status).cls">{{ badge(it.status).label }}</span>
                                        </div>
                                        <span class="text-sm leading-relaxed text-muted">{{ it.description }}</span>
                                        <div v-if="it.config_fields.length" class="mt-1.5">
                                            <button
                                                type="button"
                                                class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                                                @click="openConfig(it)"
                                            >
                                                <AppIcon name="settings" :size="14" />
                                                Yapılandır
                                            </button>
                                        </div>
                                    </div>
                                </div>
                                <BaseSwitch
                                    :model-value="it.is_enabled"
                                    :busy="busy[it.key]"
                                    :aria-label="`${it.name} entegrasyonunu aç/kapat`"
                                    @update:model-value="toggle(it, $event)"
                                />
                            </li>
                        </ul>
                    </BaseCard>
                </section>
            </template>

            <p class="text-center text-xs text-subtle">
                API anahtarları şifreli saklanır ve panelde maskelenir. Yeni bir entegrasyon
                talebiniz varsa ekiple paylaşın.
            </p>
        </div>

        <!-- Yapılandırma modalı -->
        <BaseModal :open="configOpen" :title="configTarget ? `${configTarget.name} yapılandırması` : 'Yapılandırma'" @close="configOpen = false">
            <form v-if="configTarget" class="flex flex-col gap-4" @submit.prevent="saveConfig">
                <p class="text-sm text-muted">{{ configTarget.description }}</p>
                <div v-for="field in configTarget.config_fields" :key="field.key" class="flex flex-col gap-1">
                    <label class="text-sm font-medium text-body">{{ field.label }}</label>
                    <BaseInput
                        v-model="configForm[field.key]"
                        :type="field.secret ? 'password' : 'text'"
                        :autocomplete="field.secret ? 'new-password' : 'off'"
                        :placeholder="secretSaved(configTarget, field) ? 'Kayıtlı — değiştirmek için yeni değer girin' : ''"
                    />
                    <span v-if="secretSaved(configTarget, field)" class="text-[11px] text-subtle">Bu alan kayıtlı; boş bırakırsanız değişmez.</span>
                </div>
            </form>
            <template #footer>
                <BaseButton variant="ghost" type="button" @click="configOpen = false">Vazgeç</BaseButton>
                <BaseButton variant="primary" type="button" :loading="saving" @click="saveConfig">Kaydet</BaseButton>
            </template>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
