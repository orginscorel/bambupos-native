<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import type { LeaveRow, Paginated, ScheduleData, TimeEntryRow } from '../types';
import { LEAVE_TYPE_LABELS } from '../types';
import { fmtTime, ymd } from '../lib';

/**
 * GENEL BAKIŞ (landing) — Vardiya & Mesai modülünün açılış ekranı.
 * Amaç: kullanıcı sekmelerde kaybolmadan bugünün durumunu tek bakışta görsün ve
 * doğru ekrana tek tıkla gitsin. Tüm veriler mevcut salt-okunur uçlardan gelir
 * (yeni backend YOK): /schedule, /time-entries, /leave-requests.
 * Erişim kişi-bazlıdır: staff.view olmayan yalnız kendi verisini görür (uçlar süzer).
 */
const { danger } = useToast();
const page = usePage();

const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});
const canManage = computed(() => permissions.value.includes('staff.manage'));
const canView = computed(() => canManage.value || permissions.value.includes('staff.view'));

const loading = ref(true);
const schedule = ref<ScheduleData | null>(null);
const entries = ref<TimeEntryRow[]>([]);
const pendingLeaves = ref<LeaveRow[]>([]);
const pendingLeaveTotal = ref(0);

const todayD = new Date();
const today = ymd(todayD);
const tomorrow = ymd(new Date(todayD.getTime() + 86400000));

async function load(): Promise<void> {
    loading.value = true;
    try {
        const [sch, ent, lea] = await Promise.all([
            api<ScheduleData>(`/api/v1/shifts/schedule?from=${today}&to=${tomorrow}`),
            api<Paginated<TimeEntryRow>>(`/api/v1/shifts/time-entries?from=${today}&to=${today}`),
            api<Paginated<LeaveRow>>('/api/v1/shifts/leave-requests?status=pending'),
        ]);
        schedule.value = sch;
        entries.value = ent.data;
        pendingLeaves.value = lea.data;
        pendingLeaveTotal.value = lea.total;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Türetilmiş sayaçlar ---- */
const todayShifts = computed(() => schedule.value?.shifts ?? []);
const onShiftCount = computed(() => new Set(todayShifts.value.map((s) => s.user_id)).size);
const openCount = computed(() => entries.value.filter((e) => e.status === 'open').length);
const lateCount = computed(() => entries.value.filter((e) => e.late_min > 0).length);
const warnings = computed(() => (schedule.value?.warnings ?? []).filter((w) => w.date === today));

/** Üst özet kartları — her biri ilgili ekrana götürür. */
const stats = computed(() => [
    {
        key: 'on-shift',
        label: 'Bugün vardiyada',
        value: String(onShiftCount.value),
        hint: onShiftCount.value ? 'Planlı personel' : 'Bugün planlı vardiya yok',
        icon: 'calendar',
        tone: 'info',
        href: '/panel/vardiya?gorunum=takvim',
    },
    {
        key: 'open',
        label: 'Şu an mesaide',
        value: String(openCount.value),
        hint: openCount.value ? 'Açık (çıkışsız) mesai' : 'Açık mesai yok',
        icon: 'coffee',
        tone: 'info',
        href: '/panel/mesai',
    },
    {
        key: 'late',
        label: 'Bugün geç kalan',
        value: String(lateCount.value),
        hint: lateCount.value ? 'Toleransı aşan giriş' : 'Geç kalan yok',
        icon: 'alert-triangle',
        tone: lateCount.value ? 'warning' : 'ok',
        href: '/panel/mesai',
    },
    {
        key: 'leaves',
        label: 'Bekleyen izin',
        value: String(pendingLeaveTotal.value),
        hint: pendingLeaveTotal.value ? (canManage.value ? 'Onay bekliyor' : 'Sonuç bekliyor') : 'Bekleyen talep yok',
        icon: 'inbox',
        tone: pendingLeaveTotal.value ? 'warning' : 'ok',
        href: canManage.value ? '/panel/mesai/talepler' : '/panel/mesai/izinler',
    },
]);

const toneClass = (tone: string): string =>
    tone === 'danger' ? 'text-danger' : tone === 'warning' ? 'text-warning' : tone === 'info' ? 'text-primary' : 'text-success';

/** Hızlı aksiyon butonları (izne göre süzülür). */
const actions = computed(() => {
    const list = [
        { label: 'Plan', desc: 'Vardiya takvimi', icon: 'calendar', href: '/panel/vardiya?gorunum=takvim', show: true },
        { label: 'Giriş / Çıkış', desc: 'PIN ile mesai al', icon: 'qr-code', href: '/panel/mesai/giris-cikis', show: true },
        { label: 'Mesai Kayıtları', desc: 'Giriş/çıkış defteri', icon: 'orders', href: '/panel/mesai', show: true },
        { label: 'Devam Takibi', desc: 'Kişi bazlı rapor', icon: 'chart', href: '/panel/mesai/performans', show: canView.value },
        { label: 'İzinler', desc: 'Talep / kayıt aç', icon: 'inbox', href: '/panel/mesai/izinler', show: true },
        { label: 'Cihazlar & Ayar', desc: 'Kiosk ve kurallar', icon: 'settings', href: '/panel/mesai/ayarlar', show: canManage.value },
    ];
    return list.filter((a) => a.show);
});

/** Bugünkü vardiyalar — başlangıç saatine göre sıralı, ilk 8. */
const todayShiftRows = computed(() =>
    [...todayShifts.value].sort((a, b) => a.starts_at.localeCompare(b.starts_at)).slice(0, 8),
);

function warningLabel(w: { date: string; position: string | null; required: number; planned: number }): string {
    const d = new Date(w.date + 'T00:00:00').toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' });
    return `${d}${w.position ? ' · ' + w.position : ''}: ${w.planned}/${w.required} kişi planlı`;
}
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
                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
                    <Link
                        v-for="a in actions"
                        :key="a.href"
                        :href="a.href"
                        class="flex flex-col gap-1 rounded-md border border-default p-3 transition-colors hover:border-primary hover:bg-inset"
                    >
                        <AppIcon :name="a.icon" :size="18" class="text-primary" />
                        <span class="text-sm font-medium text-body">{{ a.label }}</span>
                        <span class="text-xs text-subtle">{{ a.desc }}</span>
                    </Link>
                </div>
            </BaseCard>

            <!-- Minimum personel uyarısı (varsa) -->
            <div
                v-if="warnings.length"
                class="rounded-md border border-warning-border bg-warning-soft p-3 text-sm text-warning"
                role="alert"
            >
                <p class="flex items-center gap-1.5 font-semibold">
                    <AppIcon name="alert-triangle" :size="16" />
                    Bugün minimum personel uyarısı
                </p>
                <ul class="mt-1 list-inside list-disc space-y-0.5">
                    <li v-for="(w, i) in warnings.slice(0, 4)" :key="i">{{ warningLabel(w) }}</li>
                    <li v-if="warnings.length > 4">… ve {{ warnings.length - 4 }} uyarı daha</li>
                </ul>
            </div>

            <div class="grid gap-4 lg:grid-cols-2">
                <!-- Bugünkü vardiya -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Bugünkü vardiya</h2>
                    </template>
                    <template #actions>
                        <Link href="/panel/vardiya?gorunum=takvim" class="text-xs font-medium text-primary hover:underline">Takvim</Link>
                    </template>
                    <ul v-if="todayShiftRows.length" class="divide-y divide-default text-sm">
                        <li v-for="s in todayShiftRows" :key="s.id" class="flex items-center gap-2 py-2">
                            <span class="font-medium text-body">{{ s.user?.name ?? '—' }}</span>
                            <span v-if="s.position || s.user?.position" class="truncate text-xs text-muted">
                                {{ s.position || s.user?.position }}
                            </span>
                            <span class="ms-auto tabular-nums text-muted">{{ fmtTime(s.starts_at) }}–{{ fmtTime(s.ends_at) }}</span>
                        </li>
                    </ul>
                    <EmptyState v-else icon="calendar" title="Bugün vardiya yok" description="Bugün için planlanmış vardiya bulunmuyor." />
                </BaseCard>

                <!-- Bekleyen izin talepleri -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Bekleyen izin talepleri</h2>
                    </template>
                    <template #actions>
                        <Link
                            :href="canManage ? '/panel/mesai/talepler' : '/panel/mesai/izinler'"
                            class="text-xs font-medium text-primary hover:underline"
                        >
                            Tümü
                        </Link>
                    </template>
                    <ul v-if="pendingLeaves.length" class="divide-y divide-default text-sm">
                        <li v-for="l in pendingLeaves.slice(0, 6)" :key="l.id" class="flex items-center gap-2 py-2">
                            <BaseBadge variant="info" no-icon>Bekliyor</BaseBadge>
                            <span class="font-medium text-body">{{ l.user?.name ?? '—' }}</span>
                            <span class="truncate text-xs text-muted">{{ LEAVE_TYPE_LABELS[l.type] ?? l.type }}</span>
                            <span class="ms-auto whitespace-nowrap text-xs text-muted">
                                {{ new Date(l.starts_on).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) }}
                            </span>
                        </li>
                    </ul>
                    <EmptyState v-else icon="check-circle" title="Bekleyen talep yok" description="Onay bekleyen izin talebi bulunmuyor." />
                </BaseCard>
            </div>
        </template>
    </div>
</template>
