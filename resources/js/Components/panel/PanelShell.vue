<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Link, router, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage, type BranchOption } from '@/types/auth';
import { useTheme } from '@/composables/useTheme';
import { useToast } from '@/composables/useToast';
import { useNotifications, type NotificationItem } from '@/composables/useNotifications';
import { formatRelative } from '@/lib/format';
import type { NavItem } from '@/types/nav';
import { defaultNavigation } from '@/config/navigation';
import PanelLayout from '@/Layouts/PanelLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

/**
 * Panel kabuğu: PanelLayout'un şube değiştirici, bildirim ve kullanıcı
 * menüsü yuvalarını gerçek davranışla doldurur. Tüm panel sayfaları
 * bunu kullanır; yinelenen slot kodu olmaz.
 */
defineProps<{
    title?: string;
    /** Immersive (KDS/mutfak) mod: kenar çubuğu masaüstünde varsayılan kapalı,
     *  içerik tam genişlik. Siparişler & Kasa true verir; PanelLayout'a iletilir. */
    immersive?: boolean;
}>();

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));

const { theme, toggleTheme } = useTheme();
const { success, danger } = useToast();

/* ---- Bildirim zili (§8): okunmamış sayısı + liste + okundu işaretleme ---- */
const { items: notifications, unreadCount, markRead, markAllRead } = useNotifications();

async function openNotification(item: NotificationItem): Promise<void> {
    await markRead(item.id);
    if (item.url) {
        router.visit(item.url);
    }
}

/* ---- Menü: TEK KAYNAK → @/config/navigation ----
 *
 * 2026-07-22: Menü İKİ ayrı yerde tanımlıydı — burada yerel bir dizi ve
 * ayrıca `config/navigation.ts`. Gerçekte SADECE bu yerel dizi kullanılıyordu
 * ve içinde yalnız 2 bağlantı vardı; Menü / Masalar / Şubeler / Ayarlar
 * sayfaları yazılmış olmasına rağmen menüden ULAŞILAMIYORDU.
 * İki kaynak birleştirildi: yeni modül eklerken YALNIZ `config/navigation.ts`
 * düzenlenir, burası değişmez.
 */
const nav: NavItem[] = defaultNavigation;

/* ---- Şube değiştirici ---- */
const branches = computed<BranchOption[]>(() => auth.value?.branches ?? []);
// ŞUBE KAPSAMI: switcher yalnız yönetici + çok-şube açık + >1 şubede görünür.
// Kilitli personel/terminal/tek-şube modunda gizli (backend canSwitchBranch).
const canSwitchBranch = computed<boolean>(() => auth.value?.canSwitchBranch === true);
const activeBranchId = ref<number | null>(null);
const currentBranch = computed<BranchOption | null>(() => {
    const id = activeBranchId.value ?? auth.value?.activeBranchId ?? null;
    return branches.value.find((b) => b.id === id) ?? branches.value[0] ?? null;
});

async function selectBranch(branch: BranchOption): Promise<void> {
    if (branch.id === currentBranch.value?.id) return;
    try {
        await api('/api/v1/auth/active-branch', { method: 'POST', body: { branch_id: branch.id } });
        activeBranchId.value = branch.id;
        success('Şube değiştirildi', `${branch.name} şubesi görüntüleniyor.`);
    } catch (e) {
        danger('Şube değiştirilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    }
}

/* ---- Çıkış ---- */
const loggingOut = ref(false);

async function logout(): Promise<void> {
    if (loggingOut.value) return;
    loggingOut.value = true;
    try {
        await api('/api/v1/auth/logout', { method: 'POST' });
    } catch {
        /* oturum zaten düşmüş olabilir; her durumda giriş ekranına dön */
    }
    window.location.href = '/giris';
}

/** Ad-soyaddan avatar baş harfleri. */
const initials = computed(() => {
    const name = auth.value?.user.name ?? '';
    return name
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((p) => p[0]?.toLocaleUpperCase('tr-TR'))
        .join('');
});

/* ---- Sürüm rozetleri: alt bilgide "Site" + "Uygulama (native)" ----
 * Tek kaynak /config/changelog.php + /config/native_changelog.php;
 * burada tam liste değil yalnız güncel sürüm numarası çekilir (hafif uç,
 * bkz. routes/changelog.php). İkisi de /panel/surum-notlari'na bağlanır. */
interface VersionInfo {
    site: { version: string; released_at: string | null };
    native: { status: 'not_released' | 'released'; version: string | null };
}
const versions = ref<VersionInfo | null>(null);
onMounted(async () => {
    try {
        versions.value = await api<VersionInfo>('/api/v1/changelog/version');
    } catch {
        /* rozet süsleyicidir; yüklenemezse sessizce gizli kalır */
    }
});
const nativeVersionLabel = computed(() =>
    versions.value?.native.status === 'released' && versions.value.native.version
        ? `v${versions.value.native.version}`
        : 'yakında',
);
</script>

<template>
    <PanelLayout :title="title" :nav="nav" :immersive="immersive">
        <template #brand>QR Menü</template>

        <!-- Alt bilgi: sürüm rozetleri (Site + Uygulama) + marka bloğu — tek,
             rafine bir blok halinde. İkisi de /panel/surum-notlari'na bağlanır
             (ilgili sekmeyle); marka satırı en altta kalır. -->
        <template #sidebar-footer>
            <div class="flex flex-col gap-1 rounded-lg border border-default bg-surface p-2">
                <Link
                    href="/panel/surum-notlari?sekme=site"
                    class="group flex items-center gap-2 rounded-md px-1.5 py-1.5 transition-colors duration-(--dur-fast) hover:bg-inset"
                    title="Site sürüm notları"
                >
                    <AppIcon name="dashboard" :size="14" class="shrink-0 text-subtle group-hover:text-muted" />
                    <span class="grow truncate text-xs font-medium text-muted group-hover:text-body">Site</span>
                    <BaseBadge variant="primary" no-icon class="shrink-0">
                        {{ versions ? `v${versions.site.version}` : '—' }}
                    </BaseBadge>
                </Link>
                <Link
                    href="/panel/surum-notlari?sekme=native"
                    class="group flex items-center gap-2 rounded-md px-1.5 py-1.5 transition-colors duration-(--dur-fast) hover:bg-inset"
                    title="Uygulama (native) sürüm notları"
                >
                    <AppIcon name="qr-code" :size="14" class="shrink-0 text-subtle group-hover:text-muted" />
                    <span class="grow truncate text-xs font-medium text-muted group-hover:text-body">Uygulama</span>
                    <BaseBadge variant="neutral" no-icon class="shrink-0">
                        {{ versions ? nativeVersionLabel : '—' }}
                    </BaseBadge>
                </Link>

                <div class="my-0.5 border-t border-default" />

                <div class="flex items-center gap-2.5 px-1.5 py-1">
                    <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                        <AppIcon name="store" :size="15" />
                    </span>
                    <div class="flex min-w-0 flex-col">
                        <span v-if="auth?.tenant" class="truncate text-[13px] font-semibold text-body">{{ auth.tenant.name }}</span>
                        <span class="text-[11px] font-medium text-subtle">
                            powered by <span class="font-semibold text-muted">bogahost</span>
                        </span>
                    </div>
                </div>
            </div>
        </template>

        <!-- Şube değiştirici: kiracının aktif şubeleri -->
        <template #branch-switcher>
            <BaseDropdown v-if="canSwitchBranch && branches.length > 1" align="left" menu-label="Şube seçimi">
                <template #trigger="{ toggle, ariaAttrs }">
                    <button
                        type="button"
                        v-bind="ariaAttrs"
                        class="flex h-10 max-w-52 items-center gap-2 rounded-md px-2.5 text-sm font-medium text-body transition-colors duration-(--dur-fast) hover:bg-inset"
                        @click="toggle"
                    >
                        <AppIcon name="store" :size="17" class="text-muted" />
                        <span class="truncate">{{ currentBranch?.name ?? 'Şube' }}</span>
                        <AppIcon v-if="branches.length > 1" name="chevron-down" :size="14" class="text-subtle" />
                    </button>
                </template>
                <DropdownItem
                    v-for="branch in branches"
                    :key="branch.id"
                    :icon="branch.id === currentBranch?.id ? 'check' : 'store'"
                    @select="selectBranch(branch)"
                >
                    <span class="flex flex-col">
                        <span>{{ branch.name }}</span>
                        <span v-if="branch.code" class="text-xs text-subtle">{{ branch.code }}</span>
                    </span>
                </DropdownItem>
            </BaseDropdown>
        </template>

        <!-- Bildirimler: panel-içi zil (§8) — okunmamış sayısı + liste -->
        <template #notifications>
            <BaseDropdown menu-label="Bildirimler">
                <template #trigger="{ toggle, ariaAttrs }">
                    <button
                        type="button"
                        v-bind="ariaAttrs"
                        class="relative flex size-10 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                        :aria-label="unreadCount > 0 ? `Bildirimler (${unreadCount} okunmamış)` : 'Bildirimler'"
                        @click="toggle"
                    >
                        <AppIcon name="bell" :size="18" />
                        <span
                            v-if="unreadCount > 0"
                            class="absolute -right-0.5 -top-0.5 flex min-w-4 items-center justify-center rounded-full bg-danger px-1 text-[10px] font-bold leading-4 text-white"
                        >
                            {{ unreadCount > 99 ? '99+' : unreadCount }}
                        </span>
                    </button>
                </template>
                <div class="flex max-h-[70vh] w-80 flex-col" @click.stop>
                    <div class="flex items-center justify-between border-b border-default px-3 py-2">
                        <span class="text-sm font-semibold text-body">Bildirimler</span>
                        <button
                            v-if="unreadCount > 0"
                            type="button"
                            class="text-xs font-medium text-primary hover:underline"
                            @click="markAllRead"
                        >
                            Tümünü okundu işaretle
                        </button>
                    </div>

                    <div v-if="notifications.length === 0" class="p-2">
                        <EmptyState
                            icon="bell"
                            title="Yeni bildirim yok"
                            description="Sipariş ve sistem bildirimleri burada görünecek."
                        />
                    </div>

                    <ul v-else class="overflow-y-auto">
                        <li v-for="item in notifications" :key="item.id">
                            <button
                                type="button"
                                class="flex w-full items-start gap-2.5 border-b border-default px-3 py-2.5 text-left transition-colors duration-(--dur-fast) hover:bg-inset"
                                :class="!item.read ? 'bg-primary-soft/40' : ''"
                                @click="openNotification(item)"
                            >
                                <span
                                    class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full"
                                    :class="!item.read ? 'bg-primary-soft text-primary' : 'bg-inset text-muted'"
                                >
                                    <AppIcon :name="item.icon" :size="15" />
                                </span>
                                <span class="flex min-w-0 grow flex-col">
                                    <span class="truncate text-[13px] font-semibold text-body">{{ item.title }}</span>
                                    <span v-if="item.body" class="line-clamp-2 text-xs text-muted">{{ item.body }}</span>
                                    <span v-if="item.created_at" class="mt-0.5 text-[11px] text-subtle">
                                        {{ formatRelative(item.created_at) }}
                                    </span>
                                </span>
                                <span v-if="!item.read" class="mt-1.5 size-2 shrink-0 rounded-full bg-primary" aria-hidden="true" />
                            </button>
                        </li>
                    </ul>
                </div>
            </BaseDropdown>
        </template>

        <!-- Kullanıcı menüsü -->
        <template #user-menu>
            <BaseDropdown menu-label="Kullanıcı menüsü">
                <template #trigger="{ toggle, ariaAttrs }">
                    <button
                        type="button"
                        v-bind="ariaAttrs"
                        class="flex size-10 items-center justify-center rounded-md transition-colors duration-(--dur-fast) hover:bg-inset"
                        aria-label="Kullanıcı menüsü"
                        @click="toggle"
                    >
                        <span
                            class="flex size-8 items-center justify-center rounded-full bg-primary-soft text-xs font-semibold text-primary"
                        >
                            {{ initials || '•' }}
                        </span>
                    </button>
                </template>

                <div class="border-b border-default px-3 py-2.5" @click.stop>
                    <p class="truncate text-sm font-medium text-body">{{ auth?.user.name }}</p>
                    <p class="truncate text-xs text-muted">{{ auth?.user.email }}</p>
                </div>
                <DropdownItem icon="user" href="/panel/profil">Profil ve oturumlar</DropdownItem>
                <DropdownItem :icon="theme === 'dark' ? 'sun' : 'moon'" @select="toggleTheme">
                    {{ theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç' }}
                </DropdownItem>
                <DropdownItem icon="logout" danger @select="logout">Çıkış yap</DropdownItem>
            </BaseDropdown>
        </template>

        <!-- Personel taklidi şeridi artık GLOBAL (app.ts → ImpersonationBar);
             PanelShell'siz tam-ekran KDS ekranlarında da görünür. -->
        <slot />
    </PanelLayout>
</template>
