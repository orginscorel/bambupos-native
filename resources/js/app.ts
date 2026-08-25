import '../css/app.css';

import { createApp, h, type DefineComponent } from 'vue';
import { createInertiaApp, router } from '@inertiajs/vue3';
import ImpersonationBar from '@/Components/ImpersonationBar.vue';
import { applyTenantTheme, type TenantTheme } from '@/lib/theme';

const appName = import.meta.env.VITE_APP_NAME || 'QR Menu';

/** Paylaşılan `tenant` prop'undan kiracı panel temasını (marka rengi + font) uygular. */
function applySharedTheme(pageProps: Record<string, unknown> | undefined): void {
    const tenant = pageProps?.tenant as { theme?: TenantTheme | null } | null | undefined;
    applyTenantTheme(tenant?.theme ?? null);
}

createInertiaApp({
    title: (title) => (title ? `${title} - ${appName}` : appName),
    resolve: (name) => {
        const pages = import.meta.glob<DefineComponent>('./Pages/**/*.vue', {
            eager: true,
        });
        const page = pages[`./Pages/${name}.vue`];
        if (!page) {
            throw new Error(`Inertia page not found: ${name}`);
        }
        return page;
    },
    setup({ el, App, props, plugin }) {
        // Kiracı temasını mount'tan ÖNCE uygula (marka rengi + font) → ilk boyada doğru.
        applySharedTheme(props.initialPage.props as Record<string, unknown>);
        // Sonraki gezinmelerde (SPA) tema paylaşımı değişirse (ör. Tema kaydedildi) uygula.
        router.on('success', (event) => applySharedTheme(event.detail.page.props as Record<string, unknown>));

        // App + global impersonation şeridi (KDS gibi PanelShell'siz tam-ekran
        // sayfalarda da "Yöneticiye dön" erişilebilsin diye kökte render edilir).
        createApp({ render: () => [h(App, props), h(ImpersonationBar)] })
            .use(plugin)
            .mount(el);

        // AÇILIŞ EKRANINI KALDIR: uygulama gerçekten çizildikten sonra.
        // Blade'deki #bhx-splash, Vue mount olana kadar beyaz ekran yerine
        // marka ekranı gösterir (kurulu uygulamada "açılmadı" hissini önler).
        const splash = document.getElementById('bhx-splash');
        if (splash) {
            splash.classList.add('bhx-hide');
            window.setTimeout(() => splash.remove(), 350);
        }
    },
    progress: {
        // Sayfa geçişlerinde üstteki ince ilerleme çubuğu — marka rengiyle.
        color: '#5443D2',
        showSpinner: false,
    },
});
