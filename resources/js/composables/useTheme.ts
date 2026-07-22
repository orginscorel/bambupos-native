import { ref, readonly } from 'vue';

export type Theme = 'light' | 'dark';

const theme = ref<Theme>(
    typeof document !== 'undefined' && document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light',
);

function apply(t: Theme): void {
    theme.value = t;
    document.documentElement.dataset.theme = t;
    try {
        localStorage.setItem('theme', t);
    } catch {
        /* gizli mod vb. */
    }
}

/** Panel teması: <html data-theme> üzerinden; ilk değer app.blade.php betiğinden gelir. */
export function useTheme() {
    return {
        theme: readonly(theme),
        setTheme: apply,
        toggleTheme: () => apply(theme.value === 'dark' ? 'light' : 'dark'),
    };
}
