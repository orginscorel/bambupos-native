import '../css/app.css';

import { createApp, h, type DefineComponent } from 'vue';
import { createInertiaApp } from '@inertiajs/vue3';
import ImpersonationBar from '@/Components/ImpersonationBar.vue';

const appName = import.meta.env.VITE_APP_NAME || 'QR Menu';

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
        // App + global impersonation şeridi (KDS gibi PanelShell'siz tam-ekran
        // sayfalarda da "Yöneticiye dön" erişilebilsin diye kökte render edilir).
        createApp({ render: () => [h(App, props), h(ImpersonationBar)] })
            .use(plugin)
            .mount(el);
    },
    progress: {
        color: '#f97316',
    },
});
