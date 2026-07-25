/* Public QR Menü — hafif vanilla JS (ADR-003; çerçeve yok, build yok).
   Görevleri: kategori şeridi scroll-spy + yumuşak kaydırma, sepet iskeleti.
   Sepet tamamen istemci tarafında tutulur (ADR-011: cache'li sayfada
   sunucu durumu yok); sipariş POST'u sonraki fazın işi. */
(function () {
    'use strict';

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    /* ---------- kategori şeridi ---------- */
    var strip = document.querySelector('[data-catstrip]');
    if (strip) {
        var links = Array.prototype.slice.call(strip.querySelectorAll('[data-cat-link]'));
        var sections = Array.prototype.slice.call(document.querySelectorAll('[data-cat-section]'));

        var setActive = function (id) {
            links.forEach(function (a) {
                var on = a.getAttribute('data-cat-link') === id;
                a.classList.toggle('is-active', on);
                if (on) {
                    a.setAttribute('aria-current', 'true');
                    a.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'nearest', inline: 'center' });
                } else {
                    a.removeAttribute('aria-current');
                }
            });
        };

        links.forEach(function (a) {
            a.addEventListener('click', function (e) {
                var target = document.getElementById('kategori-' + a.getAttribute('data-cat-link'));
                if (!target) return;
                e.preventDefault();
                target.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'start' });
                setActive(a.getAttribute('data-cat-link'));
            });
        });

        if ('IntersectionObserver' in window && sections.length) {
            var visible = {};
            var io = new IntersectionObserver(
                function (entries) {
                    entries.forEach(function (en) {
                        visible[en.target.getAttribute('data-cat-section')] = en.isIntersecting;
                    });
                    for (var i = 0; i < sections.length; i++) {
                        var id = sections[i].getAttribute('data-cat-section');
                        if (visible[id]) { setActive(id); break; }
                    }
                },
                { rootMargin: '-64px 0px -55% 0px' }
            );
            sections.forEach(function (s) { io.observe(s); });
        }
    }

    /* ---------- sepet iskeleti (kuruş-integer, ADR-007) ---------- */
    var CART_KEY = 'qrmenu.cart';

    function readCart() {
        try { return JSON.parse(sessionStorage.getItem(CART_KEY) || '{}'); } catch (e) { return {}; }
    }
    function writeCart(cart) {
        try { sessionStorage.setItem(CART_KEY, JSON.stringify(cart)); } catch (e) { /* dolu/kapalı depolama */ }
    }
    function formatMinor(minor) {
        return '₺ ' + (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    var bar = document.querySelector('[data-cartbar]');
    var elCount = document.querySelector('[data-cart-count]');
    var elTotal = document.querySelector('[data-cart-total]');

    function render() {
        var cart = readCart();
        var count = 0;
        var total = 0;
        Object.keys(cart).forEach(function (id) {
            count += cart[id].qty;
            total += cart[id].qty * cart[id].priceMinor;
        });
        if (bar) {
            bar.hidden = count === 0;
            if (elCount) elCount.textContent = String(count);
            if (elTotal) elTotal.textContent = formatMinor(total);
        }
    }

    document.addEventListener('click', function (e) {
        var btn = e.target instanceof Element ? e.target.closest('[data-add-item]') : null;
        if (!btn || btn.disabled) return;
        var id = btn.getAttribute('data-item-id');
        var cart = readCart();
        if (!cart[id]) {
            cart[id] = {
                name: btn.getAttribute('data-item-name'),
                priceMinor: parseInt(btn.getAttribute('data-item-price-minor'), 10) || 0,
                qty: 0
            };
        }
        cart[id].qty += 1;
        writeCart(cart);
        render();
    });

    /* Sonraki fazlar için küçük genel API */
    window.QrMenuCart = { read: readCart, write: writeCart, render: render, formatMinor: formatMinor };

    render();
})();
