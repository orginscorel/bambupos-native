<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { router, usePage } from '@inertiajs/vue3';
import type { NavItem } from '@/types/nav';
import { defaultNavigation } from '@/config/navigation';
import { useFocusTrap } from '@/composables/useFocusTrap';
import { useId } from '@/composables/useId';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * KDS NAV ÇEKMECESİ — tam-ekran KDS ekranlarına (Mutfak/Barista/Komi)
 * navigasyon kaçış-kapısı. KDS içeriği tam-ekran KALIR; bu yalnız SOLDAN
 * kayan bir overlay'dir, kapanınca hiç iz bırakmaz (Teleport). Menü öğeleri
 * PanelLayout ile BİREBİR aynı süzgeçten geçer: izin (auth.permissions) +
 * §12 istasyon-ailesi (auth.stations). Öğeye tıklayınca router.visit ile o
 * sayfaya gider. Para/ciro burada yok — yalnız gezinme.
 */
const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const page = usePage();
const panel = ref<HTMLElement | null>(null);
const titleId = useId('kds-nav-title');
const isOpen = computed(() => props.open);

useFocusTrap(panel, isOpen);

/* PanelLayout süzgecinin AYNISI (kopya): auth yoksa süzme yapılmaz. */
const permissions = computed<string[] | null>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? null;
});
const stations = computed<string[] | null>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { stations?: string[] } | undefined;
    return auth?.stations ?? null;
});

const navItems = computed<NavItem[]>(() => {
    const perms = permissions.value;
    const userStations = stations.value;

    return defaultNavigation.filter((i) => {
        // 1) İzin süzgeci (perms yoksa hiç süzme)
        if (perms && i.permission && !perms.includes(i.permission)) return false;

        // 2) İstasyon-kapsamı: öğe istasyon ailesi tanımlamışsa VE kullanıcı
        // kısıtlıysa, yalnız kesişen aile görünür.
        if (
            i.stations &&
            i.stations.length > 0 &&
            userStations &&
            userStations.length > 0 &&
            !i.stations.some((s) => userStations.includes(s))
        ) {
            return false;
        }

        return true;
    });
});

const currentPath = computed(() => (typeof window !== 'undefined' ? window.location.pathname : ''));
const isActive = (item: NavItem): boolean =>
    item.exact
        ? currentPath.value === item.href
        : currentPath.value === item.href || currentPath.value.startsWith(item.href + '/');

function go(item: NavItem): void {
    emit('close');
    if (isActive(item)) return; // zaten buradayız
    router.visit(item.href);
}

function onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') emit('close');
}

watch(isOpen, (v) => {
    document.body.style.overflow = v ? 'hidden' : '';
    if (v) document.addEventListener('keydown', onKeydown);
    else document.removeEventListener('keydown', onKeydown);
});

onBeforeUnmount(() => {
    document.body.style.overflow = '';
    document.removeEventListener('keydown', onKeydown);
});
</script>

<template>
    <Teleport to="body">
        <Transition
            enter-active-class="transition-opacity duration-(--dur-normal)"
            enter-from-class="opacity-0"
            leave-active-class="transition-opacity duration-(--dur-fast)"
            leave-to-class="opacity-0"
        >
            <div v-if="open" class="fixed inset-0 z-(--z-drawer) bg-overlay" @mousedown.self="emit('close')" />
        </Transition>

        <Transition
            enter-active-class="transition-transform duration-(--dur-slow) ease-out"
            enter-from-class="-translate-x-full"
            leave-active-class="transition-transform duration-(--dur-normal) ease-in"
            leave-to-class="-translate-x-full"
        >
            <aside
                v-if="open"
                ref="panel"
                role="dialog"
                aria-modal="true"
                :aria-labelledby="titleId"
                tabindex="-1"
                class="fixed inset-y-0 left-0 z-(--z-drawer) flex w-full max-w-xs flex-col bg-surface shadow-modal outline-none"
            >
                <header class="flex h-14 items-center gap-2.5 border-b border-default px-4">
                    <span class="flex size-8 items-center justify-center rounded-md bg-primary text-on-primary">
                        <AppIcon name="qr-code" :size="18" />
                    </span>
                    <span :id="titleId" class="grow truncate text-sm font-semibold text-body">Menü</span>
                    <button
                        type="button"
                        class="flex size-9 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                        aria-label="Kapat"
                        @click="emit('close')"
                    >
                        <AppIcon name="x" :size="18" />
                    </button>
                </header>

                <nav class="grow overflow-y-auto p-2" aria-label="Bölümler">
                    <ul class="flex flex-col gap-0.5">
                        <li v-for="item in navItems" :key="item.key">
                            <button
                                type="button"
                                class="flex h-11 w-full items-center gap-3 rounded-md px-3 text-sm font-medium transition-colors duration-(--dur-fast)"
                                :class="
                                    isActive(item)
                                        ? 'bg-primary-soft text-primary'
                                        : 'text-muted hover:bg-inset hover:text-body'
                                "
                                :aria-current="isActive(item) ? 'page' : undefined"
                                @click="go(item)"
                            >
                                <AppIcon :name="item.icon" :size="18" />
                                <span class="grow truncate text-left">{{ item.label }}</span>
                            </button>
                        </li>
                    </ul>
                </nav>
            </aside>
        </Transition>
    </Teleport>
</template>
