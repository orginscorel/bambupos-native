<script setup lang="ts">
import { ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import PanelLayout from '@/Layouts/PanelLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseRadioGroup from '@/Components/ui/BaseRadioGroup.vue';
import FormField from '@/Components/ui/FormField.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BasePagination from '@/Components/ui/BasePagination.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import StatusPill from '@/Components/ui/StatusPill.vue';
import MetricTile from '@/Components/ui/MetricTile.vue';
import SegmentedControl from '@/Components/ui/SegmentedControl.vue';
import NumberStepper from '@/Components/ui/NumberStepper.vue';
import BottomSheet from '@/Components/ui/BottomSheet.vue';
import Tooltip from '@/Components/ui/Tooltip.vue';
import { useToast } from '@/composables/useToast';

const { success, warning, danger, info } = useToast();

// --- örnek veriler ---
const colorGroups = [
    {
        name: 'Marka skalası (--brand-*, kiracı bazında değiştirilebilir)',
        items: ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900'].map((s) => ({
            label: `brand-${s}`,
            varName: `--brand-${s}`,
        })),
    },
    {
        name: 'Semantik: etkileşim',
        items: [
            'ui-primary', 'ui-primary-hover', 'ui-primary-active', 'ui-primary-soft', 'ui-accent', 'ui-link', 'ui-focus-ring',
        ].map((v) => ({ label: v, varName: `--${v}` })),
    },
    {
        name: 'Semantik: yüzey ve metin',
        items: [
            'ui-surface', 'ui-surface-alt', 'ui-surface-raised', 'ui-surface-inset', 'ui-border', 'ui-border-strong',
            'ui-text', 'ui-text-muted', 'ui-text-subtle',
        ].map((v) => ({ label: v, varName: `--${v}` })),
    },
    {
        name: 'Semantik: durum',
        items: ['ui-success', 'ui-warning', 'ui-danger', 'ui-info'].map((v) => ({ label: v, varName: `--${v}` })),
    },
];

const typeScale = [
    { cls: 'text-xs', label: 'text-xs — 12px · yardımcı metin, tablo başlığı' },
    { cls: 'text-sm', label: 'text-sm — 14px · form, tablo, buton' },
    { cls: 'text-base', label: 'text-base — 16px · gövde (public menü)' },
    { cls: 'text-lg font-semibold', label: 'text-lg — 18px · bölüm başlığı' },
    { cls: 'text-xl font-semibold', label: 'text-xl — 20px · sayfa başlığı' },
    { cls: 'text-2xl font-bold', label: 'text-2xl — 24px · panel istatistik' },
    { cls: 'text-3xl font-bold', label: 'text-3xl — 30px · vurgu sayı' },
];

const spacing = [1, 2, 3, 4, 6, 8, 12, 16];
const radii = ['xs', 'sm', 'md', 'lg', 'xl'];
const shadows = ['card', 'dropdown', 'modal'];
const zLayers = [
    ['--z-sticky', '20', 'yapışkan çubuklar, kenar menü'],
    ['--z-dropdown', '30', 'açılır menüler'],
    ['--z-drawer', '40', 'çekmece (drawer)'],
    ['--z-modal', '50', 'modal'],
    ['--z-toast', '60', 'toast bildirimleri'],
];
const durations = [
    ['--dur-fast', '120ms', 'hover, renk geçişleri'],
    ['--dur-normal', '200ms', 'açılır öğeler, tema geçişi'],
    ['--dur-slow', '300ms', 'drawer kayması'],
];

const inputVal = ref('');
const selectVal = ref('');
const checkVal = ref(true);
const radioVal = ref<string | number>('salon');
const searchVal = ref('');
const tab = ref('a');
const modalOpen = ref(false);
const drawerOpen = ref(false);
const page = ref(3);
const btnLoading = ref(false);

// --- Faz 1 yeni bileşen durumları ---
const segView = ref<string | number>('today');
const segMode = ref<string | number>('list');
const qty = ref(2);
const qtyBounded = ref(10);
const sheetOpen = ref(false);

const columns: TableColumn[] = [
    { key: 'no', label: 'Sipariş' },
    { key: 'table', label: 'Masa' },
    { key: 'items', label: 'Ürün', align: 'right' },
    { key: 'total', label: 'Tutar', align: 'right' },
    { key: 'status', label: 'Durum' },
];
const rows = [
    { id: 1, no: '#1042', table: 'Bahçe 4', items: 3, total: '₺ 486,00', status: 'new' },
    { id: 2, no: '#1041', table: 'Salon 2', items: 5, total: '₺ 1.240,50', status: 'preparing' },
    { id: 3, no: '#1040', table: 'Teras 1', items: 2, total: '₺ 310,00', status: 'ready' },
    { id: 4, no: '#1039', table: 'Salon 7', items: 4, total: '₺ 725,00', status: 'delivered' },
    { id: 5, no: '#1038', table: 'Bahçe 2', items: 1, total: '₺ 95,00', status: 'cancelled' },
];
const statusMeta: Record<string, { label: string; variant: 'info' | 'warning' | 'success' | 'neutral' | 'danger' }> = {
    new: { label: 'Yeni', variant: 'info' },
    preparing: { label: 'Hazırlanıyor', variant: 'warning' },
    ready: { label: 'Hazır', variant: 'success' },
    delivered: { label: 'Teslim edildi', variant: 'neutral' },
    cancelled: { label: 'İptal', variant: 'danger' },
};

function demoLoading(): void {
    btnLoading.value = true;
    window.setTimeout(() => (btnLoading.value = false), 1500);
}
</script>

<template>
    <Head title="Tasarım Sistemi" />
    <PanelLayout title="Tasarım Sistemi" :notification-count="3">
        <div class="mx-auto flex max-w-5xl flex-col gap-8">
            <!-- Giriş -->
            <div>
                <h1 class="text-xl font-semibold text-body">Tasarım Sistemi</h1>
                <p class="mt-1 max-w-2xl text-sm text-muted">
                    Faz 1 temel: token'lar ve bileşenler. Renkler CSS değişkenleri üzerinden gelir; kiracı teması ileride
                    <code class="rounded-xs bg-inset px-1 py-0.5 text-xs">--brand-*</code> /
                    <code class="rounded-xs bg-inset px-1 py-0.5 text-xs">--ui-*</code>
                    değişkenlerini ezerek uygulanır — yeniden build gerekmez. Sağ üstteki ay/güneş düğmesi açık/koyu temayı değiştirir.
                    Public menü kabuğu için: <a href="/tasarim/menu" class="font-medium text-link underline underline-offset-2">/tasarim/menu</a>
                </p>
            </div>

            <!-- Renkler -->
            <BaseCard title="Renk token'ları">
                <div class="flex flex-col gap-5">
                    <div v-for="group in colorGroups" :key="group.name">
                        <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">{{ group.name }}</h3>
                        <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-5">
                            <div
                                v-for="c in group.items"
                                :key="c.varName"
                                class="flex items-center gap-2 rounded-md border border-default p-1.5"
                            >
                                <span
                                    class="size-8 shrink-0 rounded-sm border border-default"
                                    :style="{ backgroundColor: `var(${c.varName})` }"
                                />
                                <code class="truncate text-[11px] text-muted">{{ c.label }}</code>
                            </div>
                        </div>
                    </div>
                    <p class="flex items-start gap-1.5 text-xs text-muted">
                        <AppIcon name="info" :size="14" class="mt-0.5 shrink-0 text-info" />
                        WCAG AA: birincil eylem rengi (brand-700, beyaz metinle 5.18:1) ölçülerek seçildi; brand-500/600
                        beyaz metinle AA'yı geçmediğinden yalnız dekor/ikon/odak halkasında kullanılır. Tüm ölçümler
                        app.css başındaki blokta.
                    </p>
                </div>
            </BaseCard>

            <!-- Tipografi + yapı token'ları -->
            <div class="grid gap-6 lg:grid-cols-2">
                <BaseCard title="Tipografi ölçeği (sistem yazı ailesi)">
                    <ul class="flex flex-col gap-2.5">
                        <li v-for="t in typeScale" :key="t.cls" :class="t.cls" class="text-body">{{ t.label }}</li>
                    </ul>
                </BaseCard>
                <BaseCard title="Boşluk · köşe · gölge">
                    <div class="flex flex-col gap-5">
                        <div>
                            <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Boşluk (4px ızgara)</h3>
                            <div class="flex items-end gap-1.5">
                                <div
                                    v-for="s in spacing"
                                    :key="s"
                                    class="flex flex-col items-center gap-1 text-[10px] text-subtle"
                                >
                                    <span class="w-4 rounded-xs bg-accent" :style="{ height: `${s * 4}px` }" />
                                    {{ s }}
                                </div>
                            </div>
                        </div>
                        <div>
                            <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Köşe yarıçapı</h3>
                            <div class="flex flex-wrap gap-2">
                                <span
                                    v-for="r in radii"
                                    :key="r"
                                    class="flex size-14 items-center justify-center border border-strong bg-inset text-[10px] text-muted"
                                    :style="{ borderRadius: `var(--radius-${r})` }"
                                >
                                    {{ r }}
                                </span>
                            </div>
                        </div>
                        <div>
                            <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Gölgeler</h3>
                            <div class="flex flex-wrap gap-3">
                                <span
                                    v-for="s in shadows"
                                    :key="s"
                                    class="flex h-14 w-24 items-center justify-center rounded-md bg-raised text-[10px] text-muted"
                                    :style="{ boxShadow: `var(--shadow-${s})` }"
                                >
                                    {{ s }}
                                </span>
                            </div>
                        </div>
                    </div>
                </BaseCard>
            </div>

            <div class="grid gap-6 lg:grid-cols-2">
                <BaseCard title="Z-index katmanları">
                    <ul class="flex flex-col gap-1.5 text-sm">
                        <li v-for="[v, val, desc] in zLayers" :key="v" class="flex items-center gap-2">
                            <code class="w-28 shrink-0 rounded-xs bg-inset px-1.5 py-0.5 text-xs">{{ v }}</code>
                            <span class="w-8 text-muted">{{ val }}</span>
                            <span class="text-muted">{{ desc }}</span>
                        </li>
                    </ul>
                </BaseCard>
                <BaseCard title="Geçiş süreleri">
                    <ul class="flex flex-col gap-1.5 text-sm">
                        <li v-for="[v, val, desc] in durations" :key="v" class="flex items-center gap-2">
                            <code class="w-28 shrink-0 rounded-xs bg-inset px-1.5 py-0.5 text-xs">{{ v }}</code>
                            <span class="w-14 text-muted">{{ val }}</span>
                            <span class="text-muted">{{ desc }}</span>
                        </li>
                    </ul>
                    <p class="mt-3 flex items-start gap-1.5 text-xs text-muted">
                        <AppIcon name="info" :size="14" class="mt-0.5 shrink-0 text-info" />
                        <span><code>prefers-reduced-motion</code> tercihinde tüm animasyon ve geçişler kapanır.</span>
                    </p>
                </BaseCard>
            </div>

            <!-- Butonlar -->
            <BaseCard title="Butonlar">
                <div class="flex flex-col gap-4">
                    <div class="flex flex-wrap items-center gap-2">
                        <BaseButton>Birincil</BaseButton>
                        <BaseButton variant="secondary">İkincil</BaseButton>
                        <BaseButton variant="danger">Tehlikeli</BaseButton>
                        <BaseButton variant="ghost">Sade</BaseButton>
                    </div>
                    <div class="flex flex-wrap items-center gap-2">
                        <BaseButton size="sm">Küçük</BaseButton>
                        <BaseButton size="md">Orta</BaseButton>
                        <BaseButton size="lg">Büyük (mobil dokunma ≥44px)</BaseButton>
                    </div>
                    <div class="flex flex-wrap items-center gap-2">
                        <BaseButton :loading="btnLoading" @click="demoLoading">
                            {{ btnLoading ? 'Kaydediliyor…' : 'Yükleniyor durumu' }}
                        </BaseButton>
                        <BaseButton disabled>Pasif</BaseButton>
                        <BaseButton variant="secondary" icon-only label="Yeni ekle">
                            <AppIcon name="plus" :size="18" />
                        </BaseButton>
                        <BaseButton variant="secondary">
                            <AppIcon name="plus" :size="16" />
                            İkonlu
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Form -->
            <BaseCard title="Form öğeleri">
                <div class="grid gap-5 sm:grid-cols-2">
                    <FormField label="Ürün adı" hint="Menüde görünecek ad" required>
                        <BaseInput v-model="inputVal" placeholder="Örn. Mercimek çorbası" />
                    </FormField>
                    <FormField label="Kategori" error="Bu alan zorunludur">
                        <BaseSelect
                            v-model="selectVal"
                            placeholder="Seçin…"
                            :options="[
                                { value: 'soup', label: 'Çorbalar' },
                                { value: 'main', label: 'Ana yemekler' },
                                { value: 'dessert', label: 'Tatlılar' },
                            ]"
                        />
                    </FormField>
                    <div>
                        <BaseCheckbox v-model="checkVal" label="Menüde göster" description="Kapatılırsa ürün müşteriye görünmez" />
                        <BaseCheckbox label="Stok takibi" disabled />
                    </div>
                    <BaseRadioGroup
                        v-model="radioVal"
                        label="Servis alanı"
                        :options="[
                            { value: 'salon', label: 'Salon' },
                            { value: 'garden', label: 'Bahçe', description: 'Yalnız yaz sezonu' },
                            { value: 'takeaway', label: 'Paket', disabled: true },
                        ]"
                    />
                    <div class="sm:col-span-2">
                        <SearchInput v-model="searchVal" placeholder="Ürün, kategori veya masa ara…" label="Genel arama" />
                    </div>
                </div>
            </BaseCard>

            <!-- Rozetler -->
            <BaseCard title="Rozet / durum etiketi (ikon + metin: durum yalnız renkle anlatılmaz)">
                <div class="flex flex-wrap items-center gap-2">
                    <BaseBadge>Varsayılan</BaseBadge>
                    <BaseBadge variant="primary">Marka</BaseBadge>
                    <BaseBadge variant="success">Hazır</BaseBadge>
                    <BaseBadge variant="warning">Hazırlanıyor</BaseBadge>
                    <BaseBadge variant="danger">İptal</BaseBadge>
                    <BaseBadge variant="info">Yeni</BaseBadge>
                </div>
            </BaseCard>

            <!-- Tablo -->
            <BaseCard title="Tablo (duyarlı — dar ekranda kendi içinde kayar)" flush>
                <DataTable :columns="columns" :rows="rows" caption="Örnek sipariş listesi">
                    <template #cell-status="{ value }">
                        <BaseBadge :variant="statusMeta[String(value)].variant">
                            {{ statusMeta[String(value)].label }}
                        </BaseBadge>
                    </template>
                </DataTable>
                <template #footer>
                    <BasePagination v-model:page="page" :last-page="12" :total="58" />
                </template>
            </BaseCard>

            <!-- Sekmeler -->
            <BaseCard title="Sekmeler (klavye: ←/→, Home, End)">
                <BaseTabs
                    v-model="tab"
                    :tabs="[
                        { key: 'a', label: 'Genel', icon: 'settings' },
                        { key: 'b', label: 'Çeviriler' },
                        { key: 'c', label: 'Görseller' },
                    ]"
                >
                    <template #a><p class="text-sm text-muted">Genel ayarlar içeriği.</p></template>
                    <template #b><p class="text-sm text-muted">Çeviri içeriği (TR/EN/…).</p></template>
                    <template #c><p class="text-sm text-muted">Görsel yükleme alanı.</p></template>
                </BaseTabs>
            </BaseCard>

            <!-- Katmanlar -->
            <BaseCard title="Modal · Drawer · Açılır menü · Toast">
                <div class="flex flex-wrap items-center gap-2">
                    <BaseButton variant="secondary" @click="modalOpen = true">Modal aç</BaseButton>
                    <BaseButton variant="secondary" @click="drawerOpen = true">Drawer aç (sağdan)</BaseButton>
                    <BaseDropdown menu-label="Örnek işlemler">
                        <template #trigger="{ toggle, ariaAttrs }">
                            <BaseButton variant="secondary" v-bind="ariaAttrs" @click="toggle">
                                Açılır menü
                                <AppIcon name="chevron-down" :size="14" />
                            </BaseButton>
                        </template>
                        <DropdownItem icon="pencil">Düzenle</DropdownItem>
                        <DropdownItem icon="qr-code">QR kodu yenile</DropdownItem>
                        <DropdownItem icon="trash" danger>Sil</DropdownItem>
                    </BaseDropdown>
                    <BaseButton variant="secondary" @click="success('Kaydedildi', 'Ürün menüye eklendi.')">Toast: başarı</BaseButton>
                    <BaseButton variant="secondary" @click="warning('Stok azalıyor', 'Ayran için 5 adet kaldı.')">Toast: uyarı</BaseButton>
                    <BaseButton variant="secondary" @click="danger('Kaydedilemedi', 'Sunucuya ulaşılamadı.')">Toast: hata</BaseButton>
                    <BaseButton variant="secondary" @click="info('Yeni sipariş', 'Bahçe 4 masasından.')">Toast: bilgi</BaseButton>
                </div>
            </BaseCard>

            <!-- Boş durum + iskelet -->
            <div class="grid gap-6 lg:grid-cols-2">
                <BaseCard title="Boş durum" flush>
                    <EmptyState
                        title="Henüz sipariş yok"
                        description="QR kod okutulduğunda gelen siparişler burada listelenecek."
                    >
                        <template #action>
                            <BaseButton size="sm">
                                <AppIcon name="qr-code" :size="16" />
                                QR kodları yazdır
                            </BaseButton>
                        </template>
                    </EmptyState>
                </BaseCard>
                <BaseCard title="İskelet yükleme">
                    <div class="flex items-center gap-3">
                        <BaseSkeleton variant="circle" />
                        <div class="flex grow flex-col gap-2">
                            <BaseSkeleton size-class="h-4 w-1/2" />
                            <BaseSkeleton size-class="h-3 w-3/4" />
                        </div>
                    </div>
                    <BaseSkeleton variant="rect" size-class="mt-4 h-24 w-full" />
                </BaseCard>
            </div>

            <!-- Faz 1 — yeni bileşenler -->
            <div class="pt-2">
                <h2 class="text-lg font-semibold text-body">Faz 1 — yeni bileşenler</h2>
                <p class="mt-1 text-sm text-muted">
                    Domain durumları, KPI, seçim ve dokunma odaklı kontroller. Tümü token tabanlı; durum yalnız renkle
                    değil ikon + metin ile de kodlanır.
                </p>
            </div>

            <!-- StatusPill -->
            <BaseCard title="StatusPill — domain durum rozeti (sipariş / masa / stok)">
                <div class="flex flex-col gap-4">
                    <div>
                        <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Sipariş durumları</h3>
                        <div class="flex flex-wrap items-center gap-2">
                            <StatusPill kind="order-new" label="Yeni" />
                            <StatusPill kind="order-preparing" label="Hazırlanıyor" />
                            <StatusPill kind="order-ready" label="Hazır" />
                            <StatusPill kind="order-served" label="Serviste" />
                        </div>
                    </div>
                    <div>
                        <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Masa & stok</h3>
                        <div class="flex flex-wrap items-center gap-2">
                            <StatusPill kind="table-empty" label="Boş" />
                            <StatusPill kind="table-occupied" label="Dolu" />
                            <StatusPill kind="table-delayed" label="Gecikti" />
                            <StatusPill kind="stock-critical" label="Kritik stok" />
                        </div>
                    </div>
                    <div>
                        <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Genel durum</h3>
                        <div class="flex flex-wrap items-center gap-2">
                            <StatusPill kind="success" label="Onaylandı" />
                            <StatusPill kind="warning" label="Uyarı" />
                            <StatusPill kind="danger" label="Hata" />
                            <StatusPill kind="info" label="Bilgi" />
                        </div>
                    </div>
                    <div>
                        <h3 class="mb-2 text-xs font-semibold tracking-wide text-muted uppercase">Boy (sm) · dot varyantı</h3>
                        <div class="flex flex-wrap items-center gap-2">
                            <StatusPill kind="order-new" label="Yeni" size="sm" />
                            <StatusPill kind="order-preparing" label="Hazırlanıyor" size="sm" />
                            <StatusPill kind="order-ready" label="Hazır" dot />
                            <StatusPill kind="table-occupied" label="Dolu" dot size="sm" />
                        </div>
                    </div>
                </div>
            </BaseCard>

            <!-- MetricTile -->
            <BaseCard title="MetricTile — KPI kutusu (sayı baskın, tabular; delta ok + renk)">
                <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <MetricTile
                        label="Günlük ciro"
                        :value="'₺ 12.480'"
                        icon="wallet"
                        accent="brand"
                        :delta="{ value: 8.2, direction: 'up' }"
                        hint="düne göre"
                    />
                    <MetricTile
                        label="Sipariş"
                        :value="146"
                        unit="adet"
                        icon="orders"
                        accent="info"
                        :delta="{ value: 3.1, direction: 'down' }"
                        hint="düne göre"
                    />
                    <MetricTile
                        label="Ortalama servis"
                        :value="'14:20'"
                        icon="clock"
                        accent="warning"
                        :delta="{ value: 0, direction: 'flat' }"
                        hint="hedefte"
                    />
                    <MetricTile
                        label="Kritik stok"
                        :value="5"
                        unit="ürün"
                        icon="package"
                        accent="danger"
                    />
                </div>
            </BaseCard>

            <!-- SegmentedControl -->
            <BaseCard title="SegmentedControl — tek seçim (klavye: ←/→, Home/End; ≥44px)">
                <div class="flex flex-col gap-4">
                    <SegmentedControl
                        v-model="segView"
                        aria-label="Dönem"
                        :options="[
                            { value: 'today', label: 'Bugün' },
                            { value: 'week', label: 'Hafta' },
                            { value: 'month', label: 'Ay' },
                        ]"
                    />
                    <SegmentedControl
                        v-model="segMode"
                        aria-label="Görünüm"
                        :options="[
                            { value: 'list', label: 'Liste', icon: 'orders' },
                            { value: 'grid', label: 'Izgara', icon: 'dashboard' },
                            { value: 'map', label: 'Kroki', icon: 'store' },
                        ]"
                    />
                    <p class="text-xs text-muted">Seçili: <code class="rounded-xs bg-inset px-1 py-0.5">{{ segView }}</code> · <code class="rounded-xs bg-inset px-1 py-0.5">{{ segMode }}</code></p>
                </div>
            </BaseCard>

            <!-- NumberStepper -->
            <BaseCard title="NumberStepper — POS adet ( − [n] + ; büyük dokunma, tabular, sınırda pasif)">
                <div class="flex flex-wrap items-center gap-8">
                    <div class="flex flex-col items-start gap-2">
                        <span class="text-xs font-medium text-muted">Serbest (min 0)</span>
                        <NumberStepper v-model="qty" aria-label="Ürün adedi" :min="0" />
                        <span class="text-xs text-subtle">Değer: {{ qty }}</span>
                    </div>
                    <div class="flex flex-col items-start gap-2">
                        <span class="text-xs font-medium text-muted">Sınırlı (10–20, adım 2)</span>
                        <NumberStepper v-model="qtyBounded" aria-label="Porsiyon" :min="10" :max="20" :step="2" />
                        <span class="text-xs text-subtle">Değer: {{ qtyBounded }} (sınırda buton pasif)</span>
                    </div>
                    <div class="flex flex-col items-start gap-2">
                        <span class="text-xs font-medium text-muted">Kompakt (md)</span>
                        <NumberStepper v-model="qty" aria-label="Adet küçük" :min="0" size="md" />
                    </div>
                </div>
            </BaseCard>

            <!-- BottomSheet + Tooltip -->
            <BaseCard title="BottomSheet — mobil/tablet alt sayfa (aşağı-swipe / backdrop / Esc kapatır)">
                <div class="flex flex-col gap-3">
                    <BaseButton variant="secondary" @click="sheetOpen = true">Alt sayfayı aç</BaseButton>
                    <p class="flex items-start gap-1.5 text-xs text-muted">
                        <AppIcon name="info" :size="14" class="mt-0.5 shrink-0 text-info" />
                        Tutamaçtan aşağı sürükleyerek de kapatabilirsiniz. safe-area-inset-bottom + odak tuzağı uygulanır.
                    </p>
                </div>
            </BaseCard>

            <BaseCard title="Tooltip — hover/odak ipucu (klavye erişimli, role=tooltip)">
                <div class="flex flex-wrap items-center gap-6">
                    <Tooltip content="QR kodunu yeniden üretir" placement="top">
                        <template #default="{ ariaDescribedby }">
                            <BaseButton variant="secondary" :aria-describedby="ariaDescribedby">
                                <AppIcon name="qr-code" :size="16" />
                                Üst
                            </BaseButton>
                        </template>
                    </Tooltip>
                    <Tooltip content="Ürünü menüden gizler" placement="bottom">
                        <template #default="{ ariaDescribedby }">
                            <BaseButton variant="secondary" :aria-describedby="ariaDescribedby">Alt</BaseButton>
                        </template>
                    </Tooltip>
                    <Tooltip content="Sola yaslı ipucu" placement="left">
                        <template #default="{ ariaDescribedby }">
                            <BaseButton variant="secondary" :aria-describedby="ariaDescribedby">Sol</BaseButton>
                        </template>
                    </Tooltip>
                    <Tooltip content="Sağa yaslı ipucu" placement="right">
                        <template #default="{ ariaDescribedby }">
                            <BaseButton variant="ghost" icon-only label="Bilgi" :aria-describedby="ariaDescribedby">
                                <AppIcon name="info" :size="18" />
                            </BaseButton>
                        </template>
                    </Tooltip>
                    <span class="text-xs text-muted">Sekme (Tab) ile odaklanınca da görünür.</span>
                </div>
            </BaseCard>
        </div>

        <BaseModal :open="modalOpen" title="Örnek modal" @close="modalOpen = false">
            <p class="text-sm text-muted">
                Odak modal içinde tutulur (Tab döngüsü), Esc veya arka plana tıklama kapatır; kapanınca odak
                tetikleyen düğmeye döner. Mobilde alttan, masaüstünde ortadan açılır.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="modalOpen = false">Vazgeç</BaseButton>
                <BaseButton @click="modalOpen = false">Onayla</BaseButton>
            </template>
        </BaseModal>

        <BaseDrawer :open="drawerOpen" title="Örnek drawer" @close="drawerOpen = false">
            <p class="text-sm text-muted">
                Sağdan açılan panel; sipariş detayı, ürün düzenleme gibi bağlam işleri için. Mobilde tam genişliğe düşer.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="drawerOpen = false">Kapat</BaseButton>
                <BaseButton @click="drawerOpen = false">Kaydet</BaseButton>
            </template>
        </BaseDrawer>

        <BottomSheet v-model="sheetOpen" title="Örnek alt sayfa">
            <p class="text-sm text-muted">
                Alttan yukarı kayarak açılır; tutamaçtan aşağı sürükleyerek, arka plana tıklayarak veya Esc ile kapanır.
                Odak sayfa içinde tutulur ve safe-area-inset-bottom uygulanır — mobil/tablet bağlam işlemleri için.
            </p>
            <div class="mt-4 flex flex-col gap-2">
                <StatusPill kind="order-new" label="Bahçe 4 · yeni sipariş" />
                <StatusPill kind="order-preparing" label="Salon 2 · hazırlanıyor" />
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="sheetOpen = false">Vazgeç</BaseButton>
                <BaseButton @click="sheetOpen = false">Onayla</BaseButton>
            </template>
        </BottomSheet>
    </PanelLayout>
</template>
