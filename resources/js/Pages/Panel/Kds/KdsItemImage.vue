<script setup lang="ts">
/**
 * Kalem görseli — mutfağın "ne hazırlayacağını görerek" anlaması için.
 * Destekleyici öğedir: ana metni (masa/ürün adı) asla küçültmez, yalnız
 * yanında durur. Görsel yoksa/yüklenemezse zarif nötr yer tutucu (ikon)
 * gösterilir — kırık-görsel simgesi YOK.
 */
import { computed, ref, watch } from 'vue';
import { useLightbox } from '@/composables/useLightbox';
import KdsIcon from './KdsIcon.vue';

const props = withDefaults(
    defineProps<{ src: string | null; alt: string; size?: 'md' | 'lg'; zoomable?: boolean }>(),
    { size: 'md', zoomable: true },
);

const failed = ref(false);
watch(
    () => props.src,
    () => (failed.value = false),
);

const dims = props.size === 'lg' ? 'size-16' : 'size-14';

const { open } = useLightbox();
const canZoom = computed(() => props.zoomable && !!props.src && !failed.value);

function onClick(e: Event): void {
    if (!canZoom.value) return;
    e.stopPropagation(); // satır tıklamasını (kabul/ekle vb.) tetikleme
    open(props.src, props.alt);
}
</script>

<template>
    <component
        :is="canZoom ? 'button' : 'div'"
        :type="canZoom ? 'button' : undefined"
        class="block shrink-0 appearance-none overflow-hidden rounded-lg border border-default bg-inset p-0 leading-none"
        :class="[dims, canZoom ? 'cursor-zoom-in' : '']"
        :aria-label="canZoom ? `${alt} — büyüt` : undefined"
        @click="onClick"
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
    </component>
</template>
