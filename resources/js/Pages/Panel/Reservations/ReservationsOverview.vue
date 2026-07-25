<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import { fetchReservations, isoDate, type ReservationRow, type WaitlistRow } from './reservations';

/**
 * GENEL BAKIŞ (landing) — rezervasyon modülünün açılış ekranı.
 * Amaç: kullanıcı sekmelerde kaybolmadan günün durumunu tek bakışta görsün ve
 * doğru ekrana tek tıkla gitsin. Tüm veriler mevcut salt-okunur uçlardan gelir
 * (yeni backend YOK): /api/v1/reservations (bugün) + /api/v1/reservations/waitlist.
 *
 * "Yeni rezervasyon" oluşturma çekmecesi Index.vue'da olduğundan `create` olayı
 * yukarı yayılır; gezinme aksiyonları <Link> ile yapılır.
 */
const emit = defineEmits<{ create: [] }>();

/** Aktif ekranda "yönetebilir" izni yoksa oluştur butonu gizlenir. */
const props = defineProps<{ canCreate: boolean }>();

const { danger } = useToast();
const loading = ref(true);
const rows = ref<ReservationRow[]>([]);
const waitlistOpen = ref(0);

const today = isoDate(new Date());

/** Sonlanmış (artık beklenmeyen) durumlar. */
const TERMINAL = ['cancelled', 'completed', 'no_show'];
const PENDING = ['requested', 'pending'];

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        params.set('from', today);
        params.set('to', today);
        params.set('per_page', '300');

        const [res, wl] = await Promise.all([
            fetchReservations(params),
            api<{ waitlist: WaitlistRow[]; open_count: number }>('/api/v1/reservations/waitlist'),
        ]);
        rows.value = res.data;
        waitlistOpen.value = wl.open_count;
    } catch (e) {
        danger('Genel bakış yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/** Bugün hâlâ beklenen (sonlanmamış) rezervasyonlar, saate göre. */
const expected = computed(() =>
    rows.value
        .filter((r) => !TERMINAL.includes(r.status))
        .sort((a, b) => a.reserved_time.localeCompare(b.reserved_time)),
);
const pending = computed(() => rows.value.filter((r) => PENDING.includes(r.status)));
const noShowToday = computed(() => rows.value.filter((r) => r.status === 'no_show').length);

/** Üst özet kartları — her biri ilgili ekrana götürür. */
const stats = computed(() => [
    {
        key: 'today',
        label: 'Bugün beklenen',
        value: String(expected.value.length),
        hint: expected.value.length ? 'Takvimde görüntüle' : 'Bugün rezervasyon yok',
        icon: 'calendar',
        tone: 'info',
        href: '/panel/rezervasyonlar?gorunum=takvim',
    },
    {
        key: 'pending',
        label: 'Onay bekleyen',
        value: String(pending.value.length),
        hint: pending.value.length ? 'Onay/red gerekiyor' : 'Bekleyen yok',
        icon: 'bell',
        tone: pending.value.length ? 'warning' : 'ok',
        href: '/panel/rezervasyonlar?gorunum=takvim',
    },
    {
        key: 'waitlist',
        label: 'Bekleme listesi',
        value: String(waitlistOpen.value),
        hint: waitlistOpen.value ? 'Sırada bekleyen misafir' : 'Sıra boş',
        icon: 'inbox',
        tone: waitlistOpen.value ? 'warning' : 'ok',
        href: '/panel/rezervasyonlar/bekleme-listesi',
    },
    {
        key: 'noshow',
        label: 'Bugün no-show',
        value: String(noShowToday.value),
        hint: noShowToday.value ? 'Gelmeyen misafir' : 'Gelmeyen yok',
        icon: 'alert-triangle',
        tone: noShowToday.value ? 'danger' : 'ok',
        href: '/panel/rezervasyonlar/no-show',
    },
]);

const toneClass = (tone: string): string =>
    tone === 'danger' ? 'text-danger' : tone === 'warning' ? 'text-warning' : tone === 'info' ? 'text-primary' : 'text-success';
</script>

<template>
    <div class="flex flex-col gap-4">
        <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>

        <template v-else>
            <!-- Özet kartları (tıklanınca ilgili ekrana gider) -->
            <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <Link
                    v-for="s in stats"
                    :key="s.key"
                    :href="s.href"
                    class="group rounded-lg border border-default bg-raised p-4 shadow-card transition-colors hover:border-primary"
                >
                    <div class="flex items-center justify-between">
                        <p class="text-xs font-medium text-muted uppercase">{{ s.label }}</p>
                        <AppIcon :name="s.icon" :size="16" :class="toneClass(s.tone)" />
                    </div>
                    <p class="mt-2 text-2xl font-semibold tabular-nums" :class="toneClass(s.tone)">{{ s.value }}</p>
                    <p class="mt-0.5 text-xs text-subtle">{{ s.hint }}</p>
                </Link>
            </div>

            <!-- Hızlı işlemler -->
            <BaseCard title="Hızlı işlemler">
                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                    <button
                        v-if="props.canCreate"
                        type="button"
                        class="flex flex-col gap-1 rounded-md border border-default p-3 text-left transition-colors hover:border-primary hover:bg-inset"
                        @click="emit('create')"
                    >
                        <AppIcon name="plus" :size="18" class="text-primary" />
                        <span class="text-sm font-medium text-body">Yeni rezervasyon</span>
                        <span class="text-xs text-subtle">Misafir için yer aç</span>
                    </button>
                    <Link
                        href="/panel/rezervasyonlar?gorunum=takvim"
                        class="flex flex-col gap-1 rounded-md border border-default p-3 transition-colors hover:border-primary hover:bg-inset"
                    >
                        <AppIcon name="calendar" :size="18" class="text-primary" />
                        <span class="text-sm font-medium text-body">Takvim ve Liste</span>
                        <span class="text-xs text-subtle">Gün / hafta görünümü</span>
                    </Link>
                    <Link
                        href="/panel/rezervasyonlar/bekleme-listesi"
                        class="flex flex-col gap-1 rounded-md border border-default p-3 transition-colors hover:border-primary hover:bg-inset"
                    >
                        <AppIcon name="inbox" :size="18" class="text-primary" />
                        <span class="text-sm font-medium text-body">Bekleme listesi</span>
                        <span class="text-xs text-subtle">Sıradaki misafirler</span>
                    </Link>
                </div>
            </BaseCard>

            <div class="grid gap-4 lg:grid-cols-2">
                <!-- Sıradaki rezervasyonlar -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Bugün sıradaki rezervasyonlar</h2>
                    </template>
                    <template #actions>
                        <Link href="/panel/rezervasyonlar?gorunum=takvim" class="text-xs font-medium text-primary hover:underline">Takvim</Link>
                    </template>
                    <ul v-if="expected.length" class="divide-y divide-default text-sm">
                        <li v-for="r in expected.slice(0, 6)" :key="r.id" class="flex items-center gap-2 py-2">
                            <span class="w-12 shrink-0 text-base font-semibold tabular-nums text-body">{{ r.reserved_time }}</span>
                            <span class="min-w-0 grow truncate font-medium">{{ r.customer_name }}</span>
                            <span class="shrink-0 text-muted">{{ r.party_size }} kişi</span>
                            <BaseBadge :variant="r.status_variant" no-icon>{{ r.status_label }}</BaseBadge>
                        </li>
                    </ul>
                    <EmptyState v-else icon="calendar" title="Bugün rezervasyon yok" description="Bugün için beklenen rezervasyon bulunmuyor." />
                </BaseCard>

                <!-- Onay bekleyenler -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Onay bekleyenler</h2>
                    </template>
                    <template #actions>
                        <Link href="/panel/rezervasyonlar?gorunum=takvim" class="text-xs font-medium text-primary hover:underline">Yönet</Link>
                    </template>
                    <ul v-if="pending.length" class="divide-y divide-default text-sm">
                        <li v-for="r in pending.slice(0, 6)" :key="r.id" class="flex items-center gap-2 py-2">
                            <span class="w-12 shrink-0 text-base font-semibold tabular-nums text-body">{{ r.reserved_time }}</span>
                            <span class="min-w-0 grow truncate font-medium">{{ r.customer_name }}</span>
                            <span class="shrink-0 text-muted">{{ r.party_size }} kişi</span>
                            <BaseBadge variant="warning" no-icon>{{ r.status_label }}</BaseBadge>
                        </li>
                    </ul>
                    <EmptyState v-else icon="check-circle" title="Onay bekleyen yok" description="Tüm bugünkü rezervasyonlar onay durumunu geçmiş." />
                </BaseCard>
            </div>
        </template>
    </div>
</template>
