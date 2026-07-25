<script setup lang="ts">
import { computed, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage, type BranchOption } from '@/types/auth';
import { useTheme } from '@/composables/useTheme';
import { useToast } from '@/composables/useToast';
import type { NavItem } from '@/types/nav';
import PanelLayout from '@/Layouts/PanelLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

/**
 * Panel kabuğu: PanelLayout'un şube değiştirici, bildirim ve kullanıcı
 * menüsü yuvalarını gerçek davranışla doldurur. Tüm panel sayfaları
 * bunu kullanır; yinelenen slot kodu olmaz.
 */
defineProps<{ title?: string }>();

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));

const { theme, toggleTheme } = useTheme();
const { success, danger } = useToast();

/* ---- Menü: yalnız gerçekten var olan sayfalar (ölü bağlantı yok) ---- */
const nav: NavItem[] = [
    { key: 'dashboard', label: 'Panel', icon: 'dashboard', href: '/panel', exact: true, mobile: true },
    { key: 'profile', label: 'Hesabım', icon: 'user', href: '/panel/profil', mobile: true },
];

/* ---- Şube değiştirici ---- */
const branches = computed<BranchOption[]>(() => auth.value?.branches ?? []);
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
</script>

<template>
    <PanelLayout :title="title" :nav="nav">
        <template #brand>QR Menü</template>

        <template #sidebar-footer>
            <div class="flex flex-col gap-0.5">
                <span v-if="auth?.tenant" class="truncate font-medium text-muted">{{ auth.tenant.name }}</span>
                <span>powered by bogahost</span>
            </div>
        </template>

        <!-- Şube değiştirici: kiracının aktif şubeleri -->
        <template #branch-switcher>
            <BaseDropdown v-if="branches.length > 0" align="left" menu-label="Şube seçimi">
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

        <!-- Bildirimler: gerçek durum — henüz bildirim yok -->
        <template #notifications>
            <BaseDropdown menu-label="Bildirimler">
                <template #trigger="{ toggle, ariaAttrs }">
                    <button
                        type="button"
                        v-bind="ariaAttrs"
                        class="flex size-10 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                        aria-label="Bildirimler"
                        @click="toggle"
                    >
                        <AppIcon name="bell" :size="18" />
                    </button>
                </template>
                <div class="w-64" @click.stop>
                    <EmptyState
                        icon="bell"
                        title="Yeni bildirim yok"
                        description="Sipariş ve sistem bildirimleri burada görünecek."
                    />
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

        <slot />
    </PanelLayout>
</template>
