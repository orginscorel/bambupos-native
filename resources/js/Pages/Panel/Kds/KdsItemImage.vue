<script setup lang="ts">
/**
 * Kalem görseli — mutfağın "ne hazırlayacağını görerek" anlaması için.
 * Destekleyici öğedir: ana metni (masa/ürün adı) asla küçültmez, yalnız
 * yanında durur. Görsel yoksa/yüklenemezse zarif nötr yer tutucu (ikon)
 * gösterilir — kırık-görsel simgesi YOK.
 */
import { ref, watch } from 'vue';
import KdsIcon from './KdsIcon.vue';

const props = withDefaults(defineProps<{ src: string | null; alt: string; size?: 'md' | 'lg' }>(), {
    size: 'md',
});

const failed = ref(false);
watch(
    () => props.src,
    () => (failed.value = false),
);

const dims = props.size === 'lg' ? 'size-16' : 'size-14';
</script>

<template>
    <div
        class="shrink-0 overflow-hidden rounded-lg border border-default bg-inset"
        :class="dims"
    >
        <img
            v-if="src && !failed"
            :src="src"
            :alt="alt"
            loading="lazy"
            class="size-full object-cover"
            @error="failed = true"
        />
        <div v-else class="flex size-full items-center justify-center text-subtle">
            <KdsIcon name="tray" :size="props.size === 'lg' ? 22 : 18" />
        </div>
    </div>
</template>
