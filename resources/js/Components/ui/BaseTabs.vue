<script setup lang="ts">
import { ref } from 'vue';
import { useId } from '@/composables/useId';
import AppIcon from './AppIcon.vue';

export interface TabItem {
    key: string;
    label: string;
    icon?: string;
}

const props = defineProps<{
    tabs: TabItem[];
    modelValue: string;
}>();

const emit = defineEmits<{ 'update:modelValue': [key: string] }>();

const idBase = useId('tabs');
const listRef = ref<HTMLElement | null>(null);

function select(key: string): void {
    emit('update:modelValue', key);
}

/** Roving tabindex: oklar sekmeler arasında gezdirir, Home/End uçlara gider. */
function onKeydown(e: KeyboardEvent): void {
    const idx = props.tabs.findIndex((t) => t.key === props.modelValue);
    let next = -1;
    if (e.key === 'ArrowRight') next = (idx + 1) % props.tabs.length;
    else if (e.key === 'ArrowLeft') next = (idx - 1 + props.tabs.length) % props.tabs.length;
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = props.tabs.length - 1;
    if (next === -1) return;
    e.preventDefault();
    const key = props.tabs[next].key;
    select(key);
    listRef.value?.querySelector<HTMLElement>(`#${idBase}-tab-${key}`)?.focus();
}
</script>

<template>
    <div>
        <div
            ref="listRef"
            role="tablist"
            class="flex gap-1 overflow-x-auto border-b border-default"
            @keydown="onKeydown"
        >
            <button
                v-for="tab in tabs"
                :id="`${idBase}-tab-${tab.key}`"
                :key="tab.key"
                type="button"
                role="tab"
                :aria-selected="modelValue === tab.key ? 'true' : 'false'"
                :aria-controls="`${idBase}-panel-${tab.key}`"
                :tabindex="modelValue === tab.key ? 0 : -1"
                class="-mb-px inline-flex h-10 items-center gap-1.5 border-b-2 px-3 text-sm font-medium whitespace-nowrap transition-colors duration-(--dur-fast)"
                :class="
                    modelValue === tab.key
                        ? 'border-primary text-primary'
                        : 'border-transparent text-muted hover:border-strong hover:text-body'
                "
                @click="select(tab.key)"
            >
                <AppIcon v-if="tab.icon" :name="tab.icon" :size="16" />
                {{ tab.label }}
            </button>
        </div>
        <div
            v-for="tab in tabs"
            v-show="modelValue === tab.key"
            :id="`${idBase}-panel-${tab.key}`"
            :key="tab.key"
            role="tabpanel"
            :aria-labelledby="`${idBase}-tab-${tab.key}`"
            tabindex="0"
            class="pt-4"
        >
            <slot :name="tab.key" />
        </div>
    </div>
</template>
