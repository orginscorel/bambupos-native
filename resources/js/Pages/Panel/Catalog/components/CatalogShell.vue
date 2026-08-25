<script setup lang="ts">
import { computed, ref } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';

/**
 * Katalog bölümü kabuğu: PanelShell + katalog alt gezinmesi.
 * Alt sekmeler yalnız gerçekten var olan sayfalara gider.
 */
const props = defineProps<{ title: string }>();

/* Müşteri menüsünü önizle: boş masa token'ıyla /m/{token}?preview=1 (sipariş oluşmaz). */
const { danger } = useToast();
const previewBusy = ref(false);
async function openPreview(): Promise<void> {
    if (previewBusy.value) return;
    previewBusy.value = true;
    try {
        const res = await api<{ url: string }>('/api/v1/catalog/preview-url');
        window.open(res.url, '_blank', 'noopener');
    } catch (e) {
        danger('Önizleme açılamadı', e instanceof ApiError ? e.displayMessage : 'Önce bir masa oluşturun.');
    } finally {
        previewBusy.value = false;
    }
}

const page = usePage();
const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});

const tabs = [
    { key: 'products', label: 'Ürünler', href: '/panel/menu' },
    { key: 'categories', label: 'Kategoriler', href: '/panel/menu/kategoriler' },
    { key: 'options', label: 'Seçenek Grupları', href: '/panel/menu/secenekler' },
    { key: 'allergens', label: 'Alerjenler & Diyet', href: '/panel/menu/alerjenler' },
    { key: 'menus', label: 'Menü Planlama', href: '/panel/menu/menuler' },
];

const currentPath = typeof window !== 'undefined' ? window.location.pathname : '';
const isActive = (href: string) =>
    href === '/panel/menu'
        ? currentPath === '/panel/menu' || currentPath.startsWith('/panel/menu/urunler')
        : currentPath === href;
</script>

<template>
    <!-- TAM KAPLAMA: katalog sekmeleri SABİT şeritte kalır (uzun ürün
         listelerinde yukarı kaçmaz), yalnız içerik kendi içinde kayar.
         Kasa/Siparişler ekranlarıyla aynı düzen dili. -->
    <PanelShell :title="props.title" flush canvas>
        <div class="shrink-0 bg-raised px-4 sm:px-6">
            <div class="flex items-center justify-between gap-3 border-b border-default">
                <nav class="flex gap-1 overflow-x-auto" aria-label="Katalog bölümleri">
                    <Link
                        v-for="tab in tabs"
                        :key="tab.key"
                        :href="tab.href"
                        class="-mb-px inline-flex h-10 items-center border-b-2 px-3 text-sm font-medium whitespace-nowrap transition-colors duration-(--dur-fast)"
                        :class="
                            isActive(tab.href)
                                ? 'border-primary text-primary'
                                : 'border-transparent text-muted hover:border-strong hover:text-body'
                        "
                        :aria-current="isActive(tab.href) ? 'page' : undefined"
                    >
                        {{ tab.label }}
                    </Link>
                </nav>
                <BaseButton
                    size="sm"
                    variant="secondary"
                    class="mb-1 shrink-0"
                    :loading="previewBusy"
                    @click="openPreview"
                >
                    <AppIcon name="qr-code" :size="15" />
                    <span class="hidden sm:inline">Müşteri menüsünü önizle</span>
                    <span class="sm:hidden">Önizle</span>
                </BaseButton>
            </div>
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
            <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
                <slot :permissions="permissions" />
            </div>
        </div>
    </PanelShell>
</template>
