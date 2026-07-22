<script setup lang="ts">
import { Head } from '@inertiajs/vue3';

defineProps<{
    laravelVersion: string;
    phpVersion: string;
}>();
</script>

<template>
    <Head title="Hoş Geldiniz" />
    <div class="flex min-h-screen items-center justify-center bg-neutral-950 text-neutral-100">
        <div class="mx-4 w-full max-w-lg rounded-2xl border border-neutral-800 bg-neutral-900 p-10 text-center shadow-xl">
            <div class="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-orange-500/15 text-3xl">
                🍽️
            </div>
            <h1 class="text-3xl font-bold tracking-tight">QR Menü Platformu</h1>
            <p class="mt-3 text-neutral-400">
                Restoran Yönetim Platformu iskeleti çalışıyor.
            </p>
            <div class="mt-8 flex items-center justify-center gap-3 text-xs text-neutral-500">
                <span class="rounded-full border border-neutral-800 px-3 py-1">Laravel {{ laravelVersion }}</span>
                <span class="rounded-full border border-neutral-800 px-3 py-1">PHP {{ phpVersion }}</span>
                <span class="rounded-full border border-neutral-800 px-3 py-1">Vue 3 + Inertia</span>
            </div>
        </div>
    </div>
</template>
