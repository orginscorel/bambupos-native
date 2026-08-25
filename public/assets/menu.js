/* Public QR Menü — hafif vanilla JS (ADR-003; çerçeve yok, build yok).
   Arama/filtre/detay/sepet tamamen istemcide çalışır; sunucuya yalnız
   sipariş/servis POST'u gider (ADR-011: sayfa herkes için aynı, cache korunur).
   Para: HER hesap kuruş-integer (ADR-007); kayan sayı yalnız gösterimde.
   Uçlar window.QRM_CFG'den gelir (tek bağlama noktası: PublicMenuController);
   uç boşsa dürüst "henüz devrede değil" mesajı gösterilir — sahte başarı YOK. */
(function () {
    'use strict';

    var L = window.QRM_L || {};
    var CFG = window.QRM_CFG || { orders: '', service: '' };
    // Sondaki eğik çizgi (/m/{token}/) boş segment verir → dolu son segmenti al.
    var _pathSeg = location.pathname.split('/').filter(Boolean);
    var TOKEN = _pathSeg.length ? _pathSeg[_pathSeg.length - 1] : '';
    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    var dataEl = document.getElementById('qrm-data');
    var DATA = { products: {}, allergens: {}, currency: '₺' };
    try { if (dataEl) DATA = JSON.parse(dataEl.textContent); } catch (e) { /* boş menü */ }

    function t(key, n) { return String(L[key] || key).replace(':n', n); }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function fmt(minor) {
        return '₺ ' + (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    function norm(s) { return String(s || '').toLocaleLowerCase('tr'); }
    // Küçük satır-içi ikon seti (detay modalı). Tek renk currentColor → tema uyar.
    function svg(body, w) { return '<svg class="m-ic" width="' + (w || 14) + '" height="' + (w || 14) + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + body + '</svg>'; }
    var ICN = {
        clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
        flame: svg('<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>'),
        chili: svg('<path d="M6 20c8 0 13-5 13-12 0-1 0-2 1-3-2 0-3 1-4 2"/><path d="M16 7c0-2 1-3 3-3"/>'),
        portion: svg('<path d="M3 11h18"/><path d="M12 11a8 8 0 0 1 8 8H4a8 8 0 0 1 8-8z"/><path d="M12 3v3"/>'),
        leaf: svg('<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10z"/><path d="M2 21c0-3 1.85-5.36 5.08-6"/>'),
        alert: svg('<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>', 16),
        check: svg('<path d="M20 6 9 17l-5-5"/>', 16)
    };
    function $(sel, root) { return (root || document).querySelector(sel); }
    function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

    /* ---------- toast ---------- */
    var toastEl = $('[data-toast]');
    var toastTimer = null;
    function toast(msg, isError) {
        if (!toastEl) return;
        toastEl.textContent = msg;
        toastEl.classList.toggle('is-error', !!isError);
        toastEl.hidden = false;
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { toastEl.hidden = true; }, isError ? 5000 : 2200);
    }

    /* ---------- API soyutlaması (TEK yer) ---------- */
    function apiPost(url, payload, headers) {
        if (!url) return Promise.reject({ notReady: true });
        var h = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
        for (var k in (headers || {})) h[k] = headers[k];
        return fetch(url, { method: 'POST', headers: h, body: JSON.stringify(payload) })
            .then(function (res) {
                // 404 = uç henüz yayınlanmamış → "devrede değil" (dürüst mesaj)
                if (res.status === 404) throw { notReady: true };
                if (!res.ok) throw { status: res.status };
                return res.json().catch(function () { return {}; });
            });
    }
    var Api = {
        /* Sözleşme: routes/orders.php → POST /api/v1/public/orders
           {token, items:[{product_id, variant_id?, qty, option_ids?, note?}]}
           Idempotency-Key: çift dokunma/ağ tekrarı siparişi çoğaltmaz. */
        submitOrder: function (items, idemKey) {
            return apiPost(CFG.orders, { token: TOKEN, items: items },
                idemKey ? { 'Idempotency-Key': idemKey } : null);
        },
        serviceRequest: function (kind) {
            return apiPost(CFG.service, { token: TOKEN, kind: kind });
        }
    };

    /* ---------- alt sayfalar (sheet) ---------- */
    var scrim = $('[data-scrim]');
    var openSheet = null;
    var lastFocus = null;
    function sheet(name) { return $('[data-sheet="' + name + '"]'); }
    function showSheet(name) {
        closeSheet();
        var el = sheet(name);
        if (!el) return null;
        lastFocus = document.activeElement;
        el.hidden = false;
        if (scrim) scrim.hidden = false;
        document.body.classList.add('m-lock');
        openSheet = el;
        var c = $('[data-close]', el);
        if (c) c.focus();
        return el;
    }
    function closeSheet() {
        if (!openSheet) return;
        openSheet.hidden = true;
        if (scrim) scrim.hidden = true;
        document.body.classList.remove('m-lock');
        openSheet = null;
        if (lastFocus && lastFocus.focus) lastFocus.focus();
    }
    if (scrim) scrim.addEventListener('click', closeSheet);
    document.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('[data-close]')) closeSheet();
    });
    document.addEventListener('keydown', function (e) {
        if (!openSheet) return;
        if (e.key === 'Escape') { closeSheet(); return; }
        if (e.key !== 'Tab') return;
        // odak tuzağı: odak sheet içinde döner
        var f = $$('button, input, textarea, a[href], [tabindex]', openSheet).filter(function (el) { return !el.disabled && el.offsetParent !== null; });
        if (!f.length) return;
        var first = f[0], last = f[f.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    });

    /* ---------- kategori şeridi: scroll-spy ---------- */
    var strip = $('[data-catstrip]');
    if (strip) {
        var links = $$('[data-cat-link]', strip);
        var sections = $$('[data-cat-section]');
        var setActive = function (id) {
            links.forEach(function (a) {
                var on = a.getAttribute('data-cat-link') === id;
                a.classList.toggle('is-active', on);
                if (on) {
                    a.setAttribute('aria-current', 'true');
                    a.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'nearest', inline: 'center' });
                } else a.removeAttribute('aria-current');
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
            var io = new IntersectionObserver(function (entries) {
                entries.forEach(function (en) { visible[en.target.getAttribute('data-cat-section')] = en.isIntersecting; });
                for (var i = 0; i < sections.length; i++) {
                    var id = sections[i].getAttribute('data-cat-section');
                    if (visible[id]) { setActive(id); break; }
                }
            }, { rootMargin: '-64px 0px -55% 0px' });
            sections.forEach(function (s) { io.observe(s); });
        }
    }

    /* ---------- arama + filtreler (tamamen istemcide) ---------- */
    var F = { q: '', cats: [], diets: [], al: [], pmin: null, pmax: null };
    var searchInput = $('[data-q]');
    function collectFilters() {
        F.cats = $$('[data-f-cat]:checked').map(function (i) { return +i.value; });
        F.diets = $$('[data-f-diet]:checked').map(function (i) { return +i.value; });
        F.al = $$('[data-f-al]:checked').map(function (i) { return +i.value; });
        var mn = parseInt(($('[data-f-pmin]') || {}).value, 10);
        var mx = parseInt(($('[data-f-pmax]') || {}).value, 10);
        F.pmin = isNaN(mn) ? null : mn * 100; // TL → kuruş
        F.pmax = isNaN(mx) ? null : mx * 100;
        // min > max girilirse sessiz "sonuç yok" yerine değerleri değiştir.
        if (F.pmin != null && F.pmax != null && F.pmin > F.pmax) {
            var _sw = F.pmin; F.pmin = F.pmax; F.pmax = _sw;
        }
    }
    function matches(p, catId) {
        if (F.q && norm(p.n + ' ' + (p.d || '')).indexOf(F.q) === -1) return false;
        if (F.cats.length && F.cats.indexOf(catId) === -1) return false;
        if (F.diets.length && !F.diets.every(function (d) { return p.diet.indexOf(d) !== -1; })) return false;
        if (F.al.length && F.al.some(function (a) { return p.al.indexOf(a) !== -1; })) return false;
        if (F.pmin !== null && p.p < F.pmin) return false;
        if (F.pmax !== null && p.p > F.pmax) return false;
        return true;
    }
    function applyFilters() {
        collectFilters();
        var shown = 0;
        $$('[data-cat-section]').forEach(function (sec) {
            var catId = +sec.getAttribute('data-cat-section');
            var any = false;
            $$('[data-pid]', sec).forEach(function (card) {
                var p = DATA.products[card.getAttribute('data-pid')];
                var ok = !!p && matches(p, catId);
                card.classList.toggle('is-filtered', !ok);
                if (ok) { any = true; shown++; }
            });
            sec.classList.toggle('is-filtered', !any);
        });
        var activeCount = F.cats.length + F.diets.length + F.al.length + (F.pmin !== null ? 1 : 0) + (F.pmax !== null ? 1 : 0);
        var badge = $('[data-filter-badge]');
        if (badge) { badge.hidden = activeCount === 0; badge.textContent = String(activeCount); }
        var nores = $('[data-noresults]');
        if (nores) nores.hidden = shown > 0;
        var cnt = $('[data-filter-count]');
        if (cnt) cnt.textContent = t('filters_apply') + ' (' + shown + ')';
    }
    if (searchInput) {
        var qTimer = null;
        searchInput.addEventListener('input', function () {
            clearTimeout(qTimer);
            qTimer = setTimeout(function () { F.q = norm(searchInput.value.trim()); applyFilters(); }, 150);
        });
    }
    document.addEventListener('change', function (e) {
        var el = e.target;
        if (el.matches && el.matches('[data-f-cat],[data-f-diet],[data-f-al],[data-f-pmin],[data-f-pmax]')) applyFilters();
    });
    $$('[data-clear-filters]').forEach(function (btn) {
        btn.addEventListener('click', function () {
            $$('[data-f-cat]:checked,[data-f-diet]:checked,[data-f-al]:checked').forEach(function (i) { i.checked = false; });
            var mn = $('[data-f-pmin]'), mx = $('[data-f-pmax]');
            if (mn) mn.value = ''; if (mx) mx.value = '';
            if (searchInput) searchInput.value = '';
            F.q = '';
            applyFilters();
            closeSheet();
        });
    });
    var filterBtn = $('[data-open-filter]');
    if (filterBtn) filterBtn.addEventListener('click', function () { showSheet('filter'); applyFilters(); });

    /* ---------- sepet (localStorage; sunucu oturumu YOK) ---------- */
    var CART_KEY = 'qrmenu.cart.v1.' + TOKEN;
    function readCart() {
        try {
            var c = JSON.parse(localStorage.getItem(CART_KEY) || 'null');
            return (c && Array.isArray(c.lines)) ? c : { lines: [] };
        } catch (e) { return { lines: [] }; }
    }
    function writeCart(cart) {
        try { localStorage.setItem(CART_KEY, JSON.stringify(cart)); } catch (e) { /* depolama kapalı */ }
    }
    /* Satır birim fiyatı — kuruş-integer. Sunucudaki OrderService ile BİREBİR
       aynı kural olmalı; aksi halde müşterinin menüde gördüğü tutar ile kesilen
       hesap tutmaz.

       Kural:
         1) Varyant seçiliyse onun fiyatı taban fiyatın YERİNE geçer.
         2) Her seçenek grubunda "ücretsiz adet" (free_limit) varsa: seçilen
            seçenekler fiyata göre BÜYÜKTEN KÜÇÜĞE sıralanır ve ilk `free`
            tanesi ÜCRETSİZ sayılır (müşteri lehine), kalanlar kendi fiyatından
            eklenir.
       2026-07-22: Bu fonksiyon önceden free_limit'i yok sayıyordu — menüde
       "2 sos ücretsiz" yazan üründe müşteriye ücret görünüyordu. Sunucu tarafı
       düzeltilince buraya da uygulandı. */
    function unitPrice(p, vid, optIds) {
        var unit = p.p;
        if (vid != null) {
            for (var i = 0; i < p.v.length; i++) if (p.v[i].i === vid) { unit = p.v[i].p; break; }
        }
        p.g.forEach(function (g) {
            var chosen = [];
            g.o.forEach(function (o) { if (optIds.indexOf(o.i) !== -1) chosen.push(o.p); });
            if (!chosen.length) return;
            chosen.sort(function (a, b) { return b - a; });          // pahalıdan ucuza
            var free = Math.max(0, g.free | 0);
            for (var k = free; k < chosen.length; k++) unit += chosen[k];
        });
        return unit;
    }
    function lineTotals(cart) {
        var count = 0, total = 0, valid = [];
        var dropped = 0;
        cart.lines.forEach(function (ln) {
            var p = DATA.products[ln.pid];
            if (!p) { dropped++; return; }
            ln.unit = unitPrice(p, ln.vid, ln.opts);
            count += ln.qty;
            total += ln.unit * ln.qty;
            valid.push(ln);
        });
        if (dropped) {
            cart.lines = valid;
            writeCart(cart);
            toast(dropped + ' ' + t('cart_line_gone'), true);
        }
        return { count: count, total: total };
    }
    function lineSig(ln) { return ln.pid + '|' + (ln.vid || '') + '|' + ln.opts.slice().sort().join(',') + '|' + (ln.note || ''); }
    function addLine(pid, vid, opts, note, qty) {
        var cart = readCart();
        var ln = { pid: pid, vid: vid, opts: opts, note: note || '', qty: qty };
        var sig = lineSig(ln);
        var found = null;
        cart.lines.forEach(function (x) { if (lineSig(x) === sig) found = x; });
        if (found) found.qty += qty; else cart.lines.push(ln);
        delete cart.idem; // içerik değişti → yeni gönderim yeni Idempotency-Key alır
        writeCart(cart);
        renderBar();
        toast(t('cart_added'));
    }
    var bar = $('[data-cartbar]');
    function renderBar() {
        var s = lineTotals(readCart());
        if (!bar) return;
        bar.hidden = s.count === 0;
        var c = $('[data-cart-count]'), tt = $('[data-cart-total]');
        if (c) c.textContent = String(s.count);
        if (tt) tt.textContent = fmt(s.total);
    }

    /* ---------- ürün detayı ---------- */
    function optName(p, ln) {
        var parts = [];
        if (ln.vid != null) p.v.forEach(function (v) { if (v.i === ln.vid) parts.push(v.n); });
        p.g.forEach(function (g) {
            g.o.forEach(function (o) { if (ln.opts.indexOf(o.i) !== -1) parts.push(o.n); });
        });
        return parts.join(', ');
    }
    function detailHtml(p) {
        var h = '<div class="m-detail">';
        // Kahraman görsel (rozetler görsel üstünde)
        var badges = '';
        if (p.chef) badges += '<span class="m-hbadge m-hbadge--chef">' + t('tag_chef') + '</span>';
        if (p.best) badges += '<span class="m-hbadge m-hbadge--best">' + t('tag_best') + '</span>';
        if (p.new) badges += '<span class="m-hbadge m-hbadge--new">' + t('tag_new') + '</span>';
        if (p.img) {
            h += '<figure class="m-detail__hero">'
               + '<img class="m-detail__img" src="' + esc(p.img) + '" alt="" loading="lazy">'
               + (badges ? '<div class="m-detail__hbadges">' + badges + '</div>' : '')
               + '</figure>';
        } else if (badges) {
            h += '<div class="m-detail__hbadges m-detail__hbadges--flow">' + badges + '</div>';
        }
        // Fiyat (belirgin)
        h += '<div class="m-detail__price">' + fmt(p.p) + (p.op ? ' <s class="m-product__oldprice">' + fmt(p.op) + '</s>' : '') + '</div>';
        // Açıklama
        if (p.d) h += '<p class="m-detail__desc">' + esc(p.d) + '</p>';
        // Meta rozetleri (porsiyon / hazırlık / kalori / acı) — ikonlu çip
        var meta = '';
        if (p.portion) meta += '<span class="m-meta__pill">' + ICN.portion + esc(p.portion) + '</span>';
        if (p.wg != null) meta += '<span class="m-meta__pill">' + ICN.portion + p.wg + ' g</span>';
        if (p.prep != null) meta += '<span class="m-meta__pill">' + ICN.clock + p.prep + ' ' + t('prep') + '</span>';
        if (p.cal != null) meta += '<span class="m-meta__pill">' + ICN.flame + p.cal + ' ' + t('kcal') + '</span>';
        if (p.spicy > 0) meta += '<span class="m-meta__pill m-meta__pill--spicy">' + ICN.chili + t('spicy') + ' ' + Math.min(3, p.spicy) + '/3</span>';
        if (meta) h += '<div class="m-meta">' + meta + '</div>';
        // Diyet rozetleri (ayrı, yeşil, yaprak ikonlu)
        if (p.diet.length) {
            h += '<div class="m-diet"><p class="m-diet__label">' + t('diet_title') + '</p><div class="m-diet__list">'
               + p.diet.map(function (id) {
                   var a = DATA.allergens[id];
                   return a ? '<span class="m-diet__badge">' + ICN.leaf + esc(a.n) + '</span>' : '';
               }).join('') + '</div></div>';
        }
        // Alerjen bölümü: "İçerir" net başlık + rozet/çip (ad + açıklama), erişilebilir kontrast
        if (p.al.length) {
            h += '<section class="m-allergens" aria-label="' + esc(t('allergens_title')) + '">'
               + '<div class="m-allergens__head"><span class="m-allergens__icon">' + ICN.alert + '</span>'
               + '<h3 class="m-allergens__title">' + t('allergens_title') + '</h3></div>'
               + '<ul class="m-allergens__list">'
               + p.al.map(function (id) {
                   var a = DATA.allergens[id];
                   if (!a) return '';
                   return '<li class="m-alg"><span class="m-alg__dot" aria-hidden="true"></span>'
                        + '<span class="m-alg__text"><b class="m-alg__name">' + esc(a.n) + '</b>'
                        + (a.d ? '<span class="m-alg__desc">' + esc(a.d) + '</span>' : '') + '</span></li>';
               }).join('')
               + '</ul></section>';
        } else {
            h += '<section class="m-allergens m-allergens--ok" aria-label="' + esc(t('allergens_title')) + '">'
               + '<div class="m-allergens__head"><span class="m-allergens__icon m-allergens__icon--ok">' + ICN.check + '</span>'
               + '<p class="m-allergens__none">' + t('allergens_none') + '</p></div></section>';
        }
        if (p.prot != null || p.carb != null || p.fat != null) {
            var rows = '';
            if (p.cal != null) rows += '<span class="m-meta__pill">' + t('kcal') + ' ' + p.cal + '</span>';
            if (p.prot != null) rows += '<span class="m-meta__pill">' + t('protein') + ' ' + p.prot + ' g</span>';
            if (p.carb != null) rows += '<span class="m-meta__pill">' + t('carbs') + ' ' + p.carb + ' g</span>';
            if (p.fat != null) rows += '<span class="m-meta__pill">' + t('fat') + ' ' + p.fat + ' g</span>';
            h += '<div class="m-nutri"><p class="m-diet__label">' + t('nutrition') + '</p><div class="m-meta">' + rows + '</div></div>';
        }
        if (p.v.length) {
            h += '<fieldset class="m-group"><legend class="m-group__title">' + t('variant_title') + '</legend>';
            p.v.forEach(function (v, idx) {
                var checked = v.def || (idx === 0 && !p.v.some(function (x) { return x.def; }));
                h += '<label class="m-opt"><input type="radio" name="qrm-variant" value="' + v.i + '"' + (checked ? ' checked' : '') + '>'
                    + '<span class="m-opt__name">' + esc(v.n) + '</span><span class="m-opt__price">' + fmt(v.p) + '</span></label>';
            });
            h += '</fieldset>';
        }
        p.g.forEach(function (g) {
            var single = g.t === 'single' || g.max === 1;
            var hints = [];
            if (g.req) hints.push(t('choose_required'));
            if (g.min > 1) hints.push(t('choose_min', g.min));
            if (g.max != null && g.max > 1) hints.push(t('choose_max', g.max));
            if (g.free && g.free > 0) hints.push(t('free_limit', g.free)); // ":n adedi ücretsiz"
            h += '<fieldset class="m-group" data-group="' + g.i + '" data-req="' + (g.req ? 1 : 0) + '" data-min="' + g.min + '" data-max="' + (g.max == null ? '' : g.max) + '">'
                + '<legend class="m-group__title">' + esc(g.n) + '</legend>'
                + (g.d ? '<p class="m-group__hint">' + esc(g.d) + '</p>' : '')
                + (hints.length ? '<p class="m-group__hint" data-hint>' + hints.join(' · ') + '</p>' : '<p class="m-group__hint" data-hint hidden></p>');
            if (single && !g.req) {
                h += '<label class="m-opt"><input type="radio" name="qrm-g' + g.i + '" value="" checked><span class="m-opt__name">' + t('none_option') + '</span></label>';
            }
            g.o.forEach(function (o, idx) {
                var type = single ? 'radio' : 'checkbox';
                var name = single ? 'qrm-g' + g.i : '';
                var checked = single && g.req && (o.def || (idx === 0 && !g.o.some(function (x) { return x.def; })));
                h += '<label class="m-opt"><input type="' + type + '"' + (name ? ' name="' + name + '"' : '') + ' data-opt value="' + o.i + '"' + (checked ? ' checked' : '') + '>'
                    + '<span class="m-opt__name">' + esc(o.n) + '</span>'
                    + '<span class="m-opt__price">' + (o.p > 0 ? '+' + fmt(o.p) : t('free')) + '</span></label>';
            });
            h += '</fieldset>';
        });
        h += '<div class="m-group m-note"><label class="m-group__title" for="qrm-note">' + t('cart_note') + '</label>'
            + '<textarea id="qrm-note" maxlength="255" placeholder="' + esc(t('cart_note_ph')) + '"></textarea></div>';
        h += '</div>';
        return h;
    }
    function readSelection(body, p) {
        var vid = null;
        var vEl = $('input[name="qrm-variant"]:checked', body);
        if (vEl) vid = +vEl.value;
        var opts = [];
        $$('[data-group]', body).forEach(function (gEl) {
            $$('input:checked', gEl).forEach(function (i) { if (i.value !== '') opts.push(+i.value); });
        });
        var note = ($('#qrm-note', body) || { value: '' }).value.trim();
        return { vid: vid, opts: opts, note: note };
    }
    function validGroups(body) {
        var ok = true;
        $$('[data-group]', body).forEach(function (gEl) {
            var n = $$('input:checked', gEl).filter(function (i) { return i.value !== ''; }).length;
            var req = gEl.getAttribute('data-req') === '1';
            var min = +gEl.getAttribute('data-min') || 0;
            var need = Math.max(req ? 1 : 0, min);
            var bad = n < need;
            var hint = $('[data-hint]', gEl);
            if (hint) hint.classList.toggle('is-error', bad);
            if (bad) ok = false;
            // max: doluysa işaretsiz kutuları kilitle
            var maxAttr = gEl.getAttribute('data-max');
            if (maxAttr !== '') {
                var full = n >= +maxAttr;
                $$('input[type="checkbox"]', gEl).forEach(function (i) { i.disabled = full && !i.checked; });
            }
        });
        return ok;
    }
    function openDetail(pid) {
        var p = DATA.products[pid];
        if (!p) return;
        var el = showSheet('detail');
        if (!el) return;
        $('[data-detail-title]', el).textContent = p.n;
        var body = $('[data-detail-body]', el);
        body.innerHTML = detailHtml(p);
        body.scrollTop = 0;
        var qty = p.minq;
        var foot = $('[data-detail-foot]', el);
        foot.innerHTML = p.out
            ? '<p class="m-cart__msg">' + t(p.outr === 'window' ? 'off_hours' : 'sold_out') + '</p>'
            : '<div class="m-stepper">'
              + '<button type="button" data-dec aria-label="' + esc(t('qty_dec')) + '">−</button>'
              + '<output data-qty aria-live="polite">' + qty + '</output>'
              + '<button type="button" data-inc aria-label="' + esc(t('qty_inc')) + '">+</button></div>'
              + '<button type="button" class="m-btn m-btn--primary" data-confirm-add>'
              + t('add_to_cart') + ' · <span data-line-total></span></button>';
        function refresh() {
            validGroups(body);
            var q = $('[data-qty]', foot);
            if (q) q.textContent = String(qty);
            var dec = $('[data-dec]', foot), inc = $('[data-inc]', foot);
            if (dec) dec.disabled = qty <= p.minq;
            if (inc) inc.disabled = p.maxq != null && qty >= p.maxq;
            var sel = readSelection(body, p);
            var ltEl = $('[data-line-total]', foot);
            if (ltEl) ltEl.textContent = fmt(unitPrice(p, sel.vid, sel.opts) * qty);
        }
        if (!p.out) {
            // NOT: sheet düğümleri kalıcı — dinleyiciler birikmesin diye property ataması
            foot.onclick = (function (e) {
                if (e.target.closest('[data-dec]')) { qty = Math.max(p.minq, qty - 1); refresh(); }
                else if (e.target.closest('[data-inc]')) { var _cap = Math.min(p.maxq == null ? 50 : p.maxq, 50); if (qty < _cap) { qty++; refresh(); } } // sunucu adet üst sınırı = 50
                else if (e.target.closest('[data-confirm-add]')) {
                    if (!validGroups(body)) return;
                    var sel = readSelection(body, p);
                    addLine(+pid, sel.vid, sel.opts, sel.note, qty);
                    closeSheet();
                }
            });
            body.onchange = refresh;
        } else {
            foot.onclick = null;
            body.onchange = null;
        }
        refresh();
    }

    /* ---------- sepet ekranı ---------- */
    function renderCartSheet() {
        var el = sheet('cart');
        if (!el) return;
        var cart = readCart();
        var s = lineTotals(cart);
        var body = $('[data-cart-body]', el);
        var foot = $('[data-cart-foot]', el);
        if (!cart.lines.length) {
            body.innerHTML = '<p class="m-empty">' + t('cart_empty') + '</p>';
            foot.innerHTML = '';
            renderBar();
            return;
        }
        body.innerHTML = cart.lines.map(function (ln, i) {
            var p = DATA.products[ln.pid];
            var extras = optName(p, ln);
            return '<div class="m-line">'
                + '<div class="m-line__body"><p class="m-line__name">' + esc(p.n) + '</p>'
                + (extras ? '<p class="m-line__opts">' + esc(extras) + '</p>' : '')
                + (ln.note ? '<p class="m-line__note">“' + esc(ln.note) + '”</p>' : '')
                + '<p class="m-line__price">' + fmt(ln.unit * ln.qty) + '</p></div>'
                + '<div class="m-stepper">'
                + '<button type="button" data-ln-dec="' + i + '" aria-label="' + esc(t('qty_dec')) + '">−</button>'
                + '<output aria-live="polite">' + ln.qty + '</output>'
                + '<button type="button" data-ln-inc="' + i + '" aria-label="' + esc(t('qty_inc')) + '">+</button></div>'
                + '<button type="button" class="m-line__remove" data-ln-del="' + i + '" aria-label="' + esc(p.n) + ' — ' + esc(t('remove')) + '">'
                + '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg></button>'
                + '</div>';
        }).join('');
        foot.innerHTML = '<p class="m-cart__total"><span>' + t('cart_total') + '</span><span>' + fmt(s.total) + '</span></p>'
            + '<div class="m-cart__msg is-error" data-order-msg hidden></div>'
            + '<button type="button" class="m-btn m-btn--primary" data-order-submit>' + t('cart_submit') + '</button>';
        renderBar();
    }
    document.addEventListener('click', function (e) {
        var el = sheet('cart');
        if (!el || el.hidden) return;
        var tEl = e.target;
        var dec = tEl.closest('[data-ln-dec]'), inc = tEl.closest('[data-ln-inc]'), del = tEl.closest('[data-ln-del]');
        if (!dec && !inc && !del) return;
        var cart = readCart();
        var i = +((dec || inc || del).getAttribute(dec ? 'data-ln-dec' : inc ? 'data-ln-inc' : 'data-ln-del'));
        var ln = cart.lines[i];
        if (!ln) return;
        var p = DATA.products[ln.pid] || { minq: 1, maxq: null };
        if (del) cart.lines.splice(i, 1);
        else if (inc) { if (p.maxq == null || ln.qty < p.maxq) ln.qty++; }
        else { ln.qty--; if (ln.qty < (p.minq || 1)) cart.lines.splice(i, 1); }
        delete cart.idem;
        writeCart(cart);
        renderCartSheet();
    });
    /* Sipariş gönderme: uç yoksa DÜRÜST mesaj (sepet korunur, sahte başarı yok). */
    document.addEventListener('click', function (e) {
        var btn = e.target.closest && e.target.closest('[data-order-submit]');
        if (!btn) return;
        var cart = readCart();
        lineTotals(cart);
        if (!cart.lines.length) return;
        var items = cart.lines.map(function (ln) {
            var it = { product_id: ln.pid, qty: ln.qty };
            if (ln.vid != null) it.variant_id = ln.vid;
            if (ln.opts.length) it.option_ids = ln.opts;
            if (ln.note) it.note = ln.note;
            return it;
        });
        if (!cart.idem) {
            cart.idem = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()) + Math.random();
            writeCart(cart);
        }
        var msg = $('[data-order-msg]');
        btn.disabled = true;
        btn.textContent = t('cart_submitting');
        Api.submitOrder(items, cart.idem).then(function (res) {
            writeCart({ lines: [] });
            renderCartSheet();
            closeSheet();
            toast(t('order_sent'));
            // Sipariş durumu takibini başlat (müşteri "Hazırlanıyor → Hazır" görür).
            if (res && res.order && res.order.public_token) startTracking(res.order);
        }).catch(function (err) {
            btn.disabled = false;
            btn.textContent = t('cart_submit');
            if (msg) {
                msg.hidden = false;
                msg.textContent = err && err.notReady ? t('order_not_ready') : t('order_error');
            }
        });
    });

    /* ---------- servis istekleri (garson / hesap / su) ---------- */
    document.addEventListener('click', function (e) {
        var btn = e.target.closest && e.target.closest('[data-service]');
        if (!btn || btn.disabled) return;
        var kind = btn.getAttribute('data-service');
        var q = { waiter: 'confirm_waiter', bill: 'confirm_bill', water: 'confirm_water' }[kind];
        var confirmMsg = kind === 'sarjmatik' ? t('confirm_sarjmatik') : t(q);
        if (!window.confirm(confirmMsg)) return;
        btn.disabled = true;
        Api.serviceRequest(kind).then(function () {
            toast(t('service_sent'));
        }).catch(function (err) {
            toast(err && err.notReady ? t('api_not_ready') : t('api_error'), true);
        }).then(function () { btn.disabled = false; });
    });

    /* ---------- sipariş durumu takibi (canlı: 10 sn polling) ----------
       Müşteri sipariş verince "Onay bekliyor → Hazırlanıyor → Hazır → Servis"
       kartı gösterilir. Uç hazır: GET {CFG.orders}/{public_token}?token=. Aktif
       token localStorage'da; sayfa yenilense de takip sürer, bitince temizlenir. */
    var OSTATUS_KEY = 'qrmenu.order.v1.' + TOKEN;
    var ostatusEl = $('[data-order-status]');
    var ostatusTimer = null;
    // partially_ready sunucu etiketiyle (OrderStatus::label()) AYNI grupta: "Hazırlanıyor"
    // adımı (1) — Ready/AwaitingService ("Garson & Komi bekliyor") ile değil. Metin/ilerleme
    // çubuğu çelişkisini önlemek için burada da 1.
    var OSTEP = { pending_approval: 0, placed: 1, sent_to_station: 1, accepted: 1, preparing: 1, partially_ready: 1, ready: 2, awaiting_service: 2, served: 3, bill_requested: 3, partially_paid: 3, paid: 3 };
    var ODONE = { served: 1, paid: 1, cancelled: 1, refunded: 1, closed: 1, debt_transferred: 1 };
    // i18n: durum ipuçları lang sözlüğünden (EN/DE'de de doğru dilde).
    var OHINT = {
        pending_approval: 'ostatus_pending',
        ready: 'ostatus_ready',
        awaiting_service: 'ostatus_ready'
    };
    function ostatusUrl(pt) {
        if (!CFG.orders || !pt) return '';
        return CFG.orders.replace(/\/+$/, '') + '/' + encodeURIComponent(pt) + '?token=' + encodeURIComponent(TOKEN);
    }
    function renderOStatus(order) {
        if (!ostatusEl || !order) return;
        var st = order.status || '';
        var step = OSTEP[st]; if (step == null) step = 1;
        var steps = '';
        for (var i = 0; i < 4; i++) steps += '<span class="m-ostatus__step' + (i <= step ? ' is-on' : '') + '"></span>';
        var hint = OHINT[st] ? t(OHINT[st]) : (ODONE[st] ? t('ostatus_done') : t('ostatus_progress'));
        ostatusEl.innerHTML =
            '<div class="m-ostatus__top"><span class="m-ostatus__badge"><span class="m-ostatus__dot"></span>' +
            esc(order.status_label || t('ostatus_title')) + '</span>' +
            '<button type="button" class="m-ostatus__close" data-ostatus-close aria-label="' + esc(t('close')) + '">×</button></div>' +
            '<div class="m-ostatus__steps">' + steps + '</div>' +
            '<div class="m-ostatus__hint">' + esc(hint) + '</div>';
        ostatusEl.hidden = false;
    }
    function stopTracking(clear) {
        if (ostatusTimer) { clearInterval(ostatusTimer); ostatusTimer = null; }
        if (clear) { try { localStorage.removeItem(OSTATUS_KEY); } catch (e) {} }
    }
    var ostatusFails = 0;
    function pollOStatus(pt) {
        var url = ostatusUrl(pt);
        if (!url) return;
        fetch(url, { headers: { 'Accept': 'application/json' } })
            .then(function (r) {
                // Sipariş yoksa/geçersizse (404/410) takibi bitir — bayat token
                // ile sonsuza dek polling yapma (pil/istek israfı).
                if (r.status === 404 || r.status === 410) { stopTracking(true); if (ostatusEl) ostatusEl.hidden = true; return null; }
                return r.ok ? r.json() : null;
            })
            .then(function (d) {
                if (!d || !d.order) { if (++ostatusFails >= 5) { stopTracking(true); } return; }
                ostatusFails = 0;
                renderOStatus(d.order);
                if (ODONE[d.order.status]) {
                    stopTracking(true);
                    setTimeout(function () { if (ostatusEl) ostatusEl.hidden = true; }, 15000);
                }
            })
            .catch(function () { if (++ostatusFails >= 5) { stopTracking(true); } });
    }
    function startTracking(order) {
        if (!order || !order.public_token) return;
        try { localStorage.setItem(OSTATUS_KEY, order.public_token); } catch (e) {}
        renderOStatus(order);
        stopTracking(false);
        ostatusTimer = setInterval(function () { pollOStatus(order.public_token); }, 10000);
        setTimeout(function () { pollOStatus(order.public_token); }, 4000);
    }
    document.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('[data-ostatus-close]')) {
            stopTracking(true);
            if (ostatusEl) ostatusEl.hidden = true;
        }
    });
    (function resumeTracking() {
        var pt = null;
        try { pt = localStorage.getItem(OSTATUS_KEY); } catch (e) {}
        if (pt) { ostatusTimer = setInterval(function () { pollOStatus(pt); }, 10000); pollOStatus(pt); }
    })();

    /* ---------- görsel büyütme (lightbox) ----------
       Kart görselinin tam boyutlusu ZATEN indirilen dosya (~800px WebP) —
       aynı URL, ek istek yok. DOM ilk açılışta kurulur. Rozet (ikon+metin):
       p.act === false → "Satışta değil" (payload bugün pasif ürün taşımaz;
       alan gelirse hazır), p.out → Tükendi/servis dışı, yoksa "Satışta". */
    var lb = null, lbClose = null, lbFocus = null, lbTouchY = null;
    function svgIco(inner, size) {
        size = size || 13;
        return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + inner + '</svg>';
    }
    function buildLightbox() {
        lb = document.createElement('div');
        lb.className = 'm-lightbox';
        lb.hidden = true;
        lb.setAttribute('role', 'dialog');
        lb.setAttribute('aria-modal', 'true');
        lb.innerHTML = '<button type="button" class="m-lightbox__close" data-lb-close aria-label="' + esc(t('close')) + '">'
            + svgIco('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>', 20) + '</button>'
            + '<div class="m-lightbox__stage"><img class="m-lightbox__img" alt=""></div>'
            + '<div class="m-lightbox__info"><p class="m-lightbox__name"></p>'
            + '<p class="m-lightbox__row"><span class="m-lightbox__price"></span><span data-lb-badge></span></p></div>';
        document.body.appendChild(lb);
        lbClose = $('[data-lb-close]', lb);
        lb.addEventListener('click', function (e) {
            // × veya dışarı dokunma kapatır; görsel/bilgi şeridi kapatmaz
            if (e.target.closest('[data-lb-close]')) { closeLightbox(); return; }
            if (!e.target.closest('.m-lightbox__img,.m-lightbox__info')) closeLightbox();
        });
        // aşağı sürükleme = kapat; yalnız tek parmak (pinch'e karışma)
        lb.addEventListener('touchstart', function (e) {
            if (e.touches.length === 1) { lbTouchY = e.touches[0].clientY; lb.classList.add('is-drag'); }
        }, { passive: true });
        lb.addEventListener('touchmove', function (e) {
            if (lbTouchY === null || e.touches.length !== 1) return;
            var dy = e.touches[0].clientY - lbTouchY;
            if (dy > 0) {
                lb.style.transform = 'translateY(' + dy + 'px)';
                lb.style.opacity = String(Math.max(0.4, 1 - dy / 480));
                e.preventDefault();
            }
        }, { passive: false });
        lb.addEventListener('touchend', function (e) {
            if (lbTouchY === null) return;
            var dy = (e.changedTouches[0] ? e.changedTouches[0].clientY : lbTouchY) - lbTouchY;
            lbTouchY = null;
            lb.classList.remove('is-drag');
            if (dy > 90) closeLightbox();
            else { lb.style.transform = ''; lb.style.opacity = ''; }
        });
    }
    function openLightbox(pid) {
        var p = DATA.products[pid];
        if (!p || !p.img) return; // görselsiz ürün: tetiklenmez
        if (!lb) buildLightbox();
        var img = $('.m-lightbox__img', lb);
        img.src = p.img;
        img.alt = p.n;
        lb.setAttribute('aria-label', p.n);
        $('.m-lightbox__name', lb).textContent = p.n;
        $('.m-lightbox__price', lb).textContent = fmt(p.p);
        var no = p.act === false || p.out;
        var key = p.act === false ? 'not_on_sale' : p.out ? (p.outr === 'window' ? 'off_hours' : 'sold_out') : 'on_sale';
        $('[data-lb-badge]', lb).innerHTML = '<span class="m-badge ' + (no ? 'm-badge--no' : 'm-badge--ok') + '">'
            + svgIco(no ? '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>'
                        : '<path d="M21.801 10A10 10 0 1 1 17 3.335"/><path d="m9 11 3 3L22 4"/>')
            + esc(t(key)) + '</span>';
        lb.style.transform = ''; lb.style.opacity = '';
        lb.hidden = false;
        document.body.classList.add('m-lock');
        lbFocus = document.activeElement;
        lbClose.focus();
    }
    function closeLightbox() {
        if (!lb || lb.hidden) return;
        lb.hidden = true;
        lb.style.transform = ''; lb.style.opacity = '';
        if (!openSheet) document.body.classList.remove('m-lock');
        if (lbFocus && lbFocus.focus) lbFocus.focus(); // odak tetikleyiciye döner
        lbFocus = null;
    }
    document.addEventListener('keydown', function (e) {
        if (!lb || lb.hidden) return;
        if (e.key === 'Escape') closeLightbox();
        else if (e.key === 'Tab') { e.preventDefault(); lbClose.focus(); } // tek odak
    });

    /* ---------- kart etkileşimleri ---------- */
    document.addEventListener('click', function (e) {
        var zoom = e.target.closest && e.target.closest('[data-lightbox]');
        if (zoom) { openLightbox(zoom.getAttribute('data-lightbox')); return; }
        var open = e.target.closest && e.target.closest('[data-detail]');
        if (open) { openDetail(open.getAttribute('data-detail')); return; }
        var add = e.target.closest && e.target.closest('[data-add]');
        if (add && !add.disabled) {
            var pid = add.getAttribute('data-add');
            var p = DATA.products[pid];
            if (!p || p.out) return;
            // varyant/zorunlu seçenek varsa detay açılır; yoksa doğrudan eklenir
            if (p.v.length || p.g.length) openDetail(pid);
            else addLine(+pid, null, [], '', p.minq);
        }
        var cartOpen = e.target.closest && e.target.closest('[data-cart-open]');
        if (cartOpen) { renderCartSheet(); showSheet('cart'); }
    });

    renderBar();
    applyFilters();

    /* Diğer katmanlar için küçük genel API (i18n: window.QRM_L, uçlar: QRM_CFG) */
    window.QrMenu = { api: Api, cart: { read: readCart, write: writeCart }, fmt: fmt };
})();
