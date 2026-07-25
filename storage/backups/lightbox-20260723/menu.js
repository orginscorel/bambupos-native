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
    var TOKEN = location.pathname.split('/').pop();
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
        var h = '';
        if (p.img) h += '<img class="m-detail__img" src="' + esc(p.img) + '" alt="" loading="lazy">';
        if (p.d) h += '<p class="m-detail__desc">' + esc(p.d) + '</p>';
        var meta = [];
        if (p.portion) meta.push(esc(p.portion));
        if (p.prep != null) meta.push(p.prep + ' ' + t('prep'));
        if (p.cal != null) meta.push(p.cal + ' ' + t('kcal'));
        if (p.spicy > 0) meta.push(t('spicy') + ' ' + Math.min(3, p.spicy) + '/3');
        if (meta.length) h += '<p class="m-detail__meta"><span>' + meta.join('</span><span>') + '</span></p>';
        h += '<p class="m-detail__price">' + fmt(p.p) + (p.op ? ' <s class="m-product__oldprice">' + fmt(p.op) + '</s>' : '') + '</p>';
        if (p.diet.length) {
            h += '<p class="m-product__tags">' + p.diet.map(function (id) {
                var a = DATA.allergens[id];
                return a ? '<span class="m-tag m-tag--diet">' + esc(a.n) + '</span>' : '';
            }).join('') + '</p>';
        }
        // Alerjenler: ikon tek başına yeterli değil — ad + açıklama birlikte (prompt §10.3)
        h += '<div class="m-allergens"><p class="m-allergens__title">'
            + '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>'
            + t('allergens_title') + '</p>';
        if (p.al.length) {
            h += '<ul>' + p.al.map(function (id) {
                var a = DATA.allergens[id];
                return a ? '<li><b>' + esc(a.n) + '</b>' + (a.d ? ' — <span>' + esc(a.d) + '</span>' : '') + '</li>' : '';
            }).join('') + '</ul>';
        } else {
            h += '<p class="m-allergens li"><span>' + t('allergens_none') + '</span></p>';
        }
        h += '</div>';
        if (p.cal != null || p.prot != null || p.carb != null || p.fat != null) {
            var rows = [];
            if (p.cal != null) rows.push(t('kcal') + ': ' + p.cal);
            if (p.prot != null) rows.push(t('protein') + ': ' + p.prot + ' g');
            if (p.carb != null) rows.push(t('carbs') + ': ' + p.carb + ' g');
            if (p.fat != null) rows.push(t('fat') + ': ' + p.fat + ' g');
            h += '<div class="m-group"><p class="m-group__title">' + t('nutrition') + '</p><p class="m-detail__meta"><span>' + rows.join('</span><span>') + '</span></p></div>';
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
            + '<textarea id="qrm-note" maxlength="300" placeholder="' + esc(t('cart_note_ph')) + '"></textarea></div>';
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
                else if (e.target.closest('[data-inc]')) { if (p.maxq == null || qty < p.maxq) { qty++; refresh(); } }
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
        Api.submitOrder(items, cart.idem).then(function () {
            writeCart({ lines: [] });
            renderCartSheet();
            closeSheet();
            toast(t('order_sent'));
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
        if (!window.confirm(t(q))) return;
        btn.disabled = true;
        Api.serviceRequest(kind).then(function () {
            toast(t('service_sent'));
        }).catch(function (err) {
            toast(err && err.notReady ? t('api_not_ready') : t('api_error'), true);
        }).then(function () { btn.disabled = false; });
    });

    /* ---------- kart etkileşimleri ---------- */
    document.addEventListener('click', function (e) {
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
