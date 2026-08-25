/* ============================================================
   Kiosk istemcisi (Faz 8) — build'siz vanilla JS durum makinesi.

   GÜVENLİK / GİZLİLİK (§18 — 2026-08-04 itibarıyla daraltılmış sözleşme):
   - TÜM müşteri SİPARİŞ/SEPET/KİŞİSEL verisi (sepet, isim, not, seçimler,
     ödeme durumu) yalnız bu dosyanın S nesnesindedir — kalıcı depolamaya
     ASLA yazılmaz. Oturum deposu / belge çerezi / gömülü veritabanı HİÇ
     kullanılmaz.
   - TEK istisna: device_lock özelliği (§13/ADR-008 deseni, varsayılan
     KAPALI) açıkken, bu kiosk ekranını sunan cihazı tanımlamak için
     PII-OLMAYAN, opak, sunucu-üretimli bir "cihaz-bağlama token'ı"
     (`bbpos_kiosk_device`) yerel depoda tutulabilir — bkz. aşağıdaki blok.
     Bu token müşteriyle değil CİHAZLA ilişkilidir; sepet/isim/not/sipariş
     içeriği barındırmaz ve müşteriden müşteriye hiçbir iz taşımaz.
   - Bekçi test (KioskScreenTest): oturum deposu/çerez/gömülü veritabanının
     hiç kullanılmadığını VE yerel depolamanın yalnız bu tek anahtarla,
     müşteri verisi taşımadan kullanıldığını doğrular.
   - Sıfırlama = location.reload(): bellek (S) tamamen boşalır; bir sonraki
     müşteri öncekinin HİÇBİR SİPARİŞ/SEPET/KİŞİSEL verisini göremez (cihaz
     kimliği kasıtlı olarak kalır — cihazın kendisi değişmedi).
   - Zaman aşımı: idle sn dokunulmazsa uyarı; warn sn içinde yanıt yoksa
     sıfırlama. Ödeme doğrulanırken sayaç DURUR (para çekilmiş olabilir).

   DÜRÜSTLÜK (§22):
   - Çevrimdışıyken gönderim engellenir, şerit gösterilir.
   - Ödeme yalnız sunucunun döndürdüğü doğrulanmış sonuca göre başarılı
     sayılır; belirsizlikte "personele başvurun" denir, asla sahte başarı yok.
   ============================================================ */
(function () {
    'use strict';

    var D = JSON.parse(document.getElementById('kiosk-data').textContent);

    /* ---------------- Cihaz kilidi kimliği (§18 uyumlu) ----------------
       device_lock özelliği AÇIKSA: bu kiosk bağlantısını İLK açan cihaza
       kilitlemek için opak bir "cihaz kimliği" localStorage'da tutulur.
       DİKKAT: bu MÜŞTERİ VERİSİ DEĞİL (sepet/isim değil) — o veriler hâlâ
       yalnız JS belleğinde; reload hepsini siler, cihaz kimliği kalır (§18
       gizlilik amacı korunur: müşteriden müşteriye iz taşınmaz). Özellik
       kapalıyken sunucu kimlik üretmez/istemez → tek satır bile çalışmaz.
       Kimlik: (1) ?dt= claim linki (yönetici ön-yetkili), (2) localStorage. */
    var DEVICE_KEY = 'bbpos_kiosk_device';
    var deviceToken = null;
    try {
        var _claim = new URLSearchParams(location.search).get('dt');
        if (_claim) { localStorage.setItem(DEVICE_KEY, _claim); }
        deviceToken = localStorage.getItem(DEVICE_KEY);
    } catch (e) { deviceToken = null; } // localStorage engelliyse sessizce geç
    function saveDeviceToken(tok) {
        deviceToken = tok;
        try { localStorage.setItem(DEVICE_KEY, tok); } catch (e) {}
    }
    function showDeviceLocked(msg) {
        var o = document.getElementById('k-devlock');
        if (!o) { return; }
        var m = document.getElementById('k-devlock-msg');
        if (m && msg) { m.textContent = msg; }
        o.style.display = 'flex'; // [hidden]/display:none başlangıcını ez
    }

    /* ---------------- i18n (yalnız arayüz metinleri; ürün adları katalogtan gelir) ---------------- */
    var I18N = {
        tr: {
            offline: 'İnternet bağlantısı yok. Sipariş ve ödeme şu an alınamıyor.',
            tap_to_start: 'Sipariş vermek için dokunun', self_service: 'Self-servis sipariş ekranı',
            back: 'Geri', back_menu: 'Menüye dön', back_cart: 'Sepete dön',
            how_to_eat: 'Siparişinizi nasıl alırsınız?',
            dine_in: 'Masada servis', dine_in_sub: 'Masanıza getirelim',
            takeaway: 'Gel-al', takeaway_sub: 'Tezgâhtan teslim alın',
            package: 'Paket', package_sub: 'Paketleyelim',
            pick_table: 'Masanızı seçin', start_over: 'Baştan başla',
            search_ph: 'Ürün ara…', cart: 'Sepet', featured: 'Öne çıkanlar',
            no_result: 'Aramanızla eşleşen ürün yok.', your_cart: 'Sepetiniz',
            cart_empty: 'Sepetiniz boş.', total: 'Toplam', continue: 'Devam et',
            order_summary: 'Sipariş özeti',
            your_name: 'Adınız (isteğe bağlı — sıra anonsu için)',
            order_note: 'Sipariş notu (isteğe bağlı)',
            confirm_pay: 'Onayla ve öde', confirm_send: 'Siparişi gönder',
            pay_title: 'Kartınızı POS cihazına okutun',
            pay_sending: 'Sipariş gönderiliyor…', pay_wait: 'Ödeme doğrulanıyor, lütfen bekleyin…',
            pay_fail_title: 'Ödeme alınamadı',
            pay_unknown: 'Ödeme durumu doğrulanamadı. Kartınızdan çekim yapılmış olabilir — lütfen personele başvurun.',
            order_received: 'Siparişiniz alındı', order_no: 'Sipariş No',
            pay_at_counter: 'Lütfen kasada ödeyiniz.', new_order: 'Yeni sipariş',
            still_there: 'Orada mısınız?', idle_msg: 'İşlem yapılmazsa ekran sıfırlanacak:',
            im_here: 'Devam ediyorum', restart_q: 'Baştan başlansın mı?',
            restart_msg: 'Sepetiniz ve girdiğiniz bilgiler silinecek.',
            cancel: 'Vazgeç', yes_restart: 'Evet, sıfırla', a11y: 'Kolay okuma',
            add: 'Sepete ekle', sold_out: 'Tükendi', off_hours: 'Servis saati dışı',
            free_note: 'ilk {n} seçim ücretsiz', required: 'zorunlu',
            choose_min: 'En az {n} seçim yapın', choose_max: 'En fazla {n} seçilebilir',
            item_note_ph: 'Kalem notu (isteğe bağlı)',
            badge_new: 'Yeni', badge_chef: 'Şef önerisi', badge_best: 'Çok satan',
            err_generic: 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
            err_offline: 'İnternet bağlantısı yok. Bağlantı gelince tekrar deneyin.',
            table: 'Masa', paid_with_card: 'Kart ile ödendi', auth_code: 'Onay kodu'
        },
        en: {
            offline: 'No internet connection. Ordering and payment are unavailable.',
            tap_to_start: 'Touch to start your order', self_service: 'Self-service ordering screen',
            back: 'Back', back_menu: 'Back to menu', back_cart: 'Back to cart',
            how_to_eat: 'How would you like your order?',
            dine_in: 'Table service', dine_in_sub: 'We bring it to your table',
            takeaway: 'Pick-up', takeaway_sub: 'Collect at the counter',
            package: 'Takeaway box', package_sub: 'Packed to go',
            pick_table: 'Choose your table', start_over: 'Start over',
            search_ph: 'Search products…', cart: 'Cart', featured: 'Featured',
            no_result: 'No products match your search.', your_cart: 'Your cart',
            cart_empty: 'Your cart is empty.', total: 'Total', continue: 'Continue',
            order_summary: 'Order summary',
            your_name: 'Your name (optional — for call-out)',
            order_note: 'Order note (optional)',
            confirm_pay: 'Confirm & pay', confirm_send: 'Send order',
            pay_title: 'Tap your card on the POS terminal',
            pay_sending: 'Sending your order…', pay_wait: 'Verifying payment, please wait…',
            pay_fail_title: 'Payment failed',
            pay_unknown: 'Payment could not be verified. Your card may have been charged — please contact staff.',
            order_received: 'Order received', order_no: 'Order No',
            pay_at_counter: 'Please pay at the counter.', new_order: 'New order',
            still_there: 'Are you still there?', idle_msg: 'The screen will reset in:',
            im_here: 'I\'m here', restart_q: 'Start over?',
            restart_msg: 'Your cart and details will be cleared.',
            cancel: 'Cancel', yes_restart: 'Yes, reset', a11y: 'Easy reading',
            add: 'Add to cart', sold_out: 'Sold out', off_hours: 'Not served now',
            free_note: 'first {n} free', required: 'required',
            choose_min: 'Choose at least {n}', choose_max: 'Up to {n} allowed',
            item_note_ph: 'Item note (optional)',
            badge_new: 'New', badge_chef: 'Chef\'s pick', badge_best: 'Bestseller',
            err_generic: 'The request failed. Please try again.',
            err_offline: 'No internet connection. Try again when back online.',
            table: 'Table', paid_with_card: 'Paid by card', auth_code: 'Auth code'
        }
    };

    /* ---------------- Durum (yalnız bellek — §18) ---------------- */
    var S = {
        lang: 'tr',
        screen: 'attract',
        orderType: null,
        tableId: null,
        tableLabel: null,
        cart: [],           // {uid, productId, variantId, qty, note, optionIds[]}
        activeCat: null,
        search: '',
        modal: null,        // {product, variantId, optionIds, qty, note}
        submitting: false,
        paymentRef: null,
        pollLeft: 0,
        receipt: null
    };

    var byId = {};
    D.menu.products.forEach(function (p) { byId[p.id] = p; });

    /* ---------------- Yardımcılar ---------------- */
    function $(sel) { return document.querySelector(sel); }
    function $all(sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); }
    function t(key, vars) {
        var s = (I18N[S.lang] && I18N[S.lang][key]) || I18N.tr[key] || key;
        if (vars) { Object.keys(vars).forEach(function (k) { s = s.replace('{' + k + '}', vars[k]); }); }
        return s;
    }
    function money(minor) {
        return (minor / 100).toLocaleString(S.lang === 'tr' ? 'tr-TR' : 'en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ' + D.currency;
    }
    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) { n.className = cls; }
        if (text !== undefined && text !== null) { n.textContent = text; }
        return n;
    }
    function newUid() { return 'c' + Math.random().toString(36).slice(2, 10); }

    /* ---------------- Ekran geçişleri ---------------- */
    function show(screen) {
        S.screen = screen;
        $all('[data-screen]').forEach(function (s) { s.hidden = s.getAttribute('data-screen') !== screen; });
        $('#k-app').setAttribute('data-state', screen);
    }

    function applyLang() {
        $all('[data-i18n]').forEach(function (n) { n.textContent = t(n.getAttribute('data-i18n')); });
        $all('[data-i18n-ph]').forEach(function (n) { n.placeholder = t(n.getAttribute('data-i18n-ph')); });
        $all('[data-action="lang"]').forEach(function (b) { b.classList.toggle('is-active', b.getAttribute('data-lang') === S.lang); });
        document.documentElement.lang = S.lang;
        renderCartBadge();
        renderSubmitLabel();
    }

    /* ---------------- Menü çizimi ---------------- */
    function renderCats() {
        var wrap = $('#k-cats');
        wrap.textContent = '';
        D.menu.categories.forEach(function (c) {
            var b = el('button', S.activeCat === c.id ? 'is-active' : '', c.name);
            b.type = 'button';
            b.addEventListener('click', function () { S.activeCat = c.id; S.search = ''; $('#k-search').value = ''; renderCats(); renderGrid(); });
            wrap.appendChild(b);
        });
    }

    function productCard(p, compact) {
        var card = el('button', 'k-card' + (p.sold_out ? ' is-out' : ''));
        card.type = 'button';
        if (p.image) {
            var img = document.createElement('img');
            img.className = 'k-card__img'; img.loading = 'lazy'; img.alt = ''; img.src = p.image;
            card.appendChild(img);
        } else {
            card.appendChild(el('div', 'k-card__imgph', '🍽'));
        }
        var body = el('div', 'k-card__body');
        var badges = el('div', 'k-card__badges');
        if (p.is_new) { badges.appendChild(el('span', 'k-badge', t('badge_new'))); }
        if (p.is_chef_pick) { badges.appendChild(el('span', 'k-badge', t('badge_chef'))); }
        if (p.is_bestseller) { badges.appendChild(el('span', 'k-badge', t('badge_best'))); }
        if (badges.childNodes.length) { body.appendChild(badges); }
        body.appendChild(el('div', 'k-card__name', p.name));
        var price = el('div', 'k-card__price');
        if (p.sold_out) {
            price.textContent = p.out_reason === 'stock' ? t('sold_out') : t('off_hours');
        } else {
            if (p.old_price_minor) { price.appendChild(el('span', 'k-card__old', money(p.old_price_minor))); }
            price.appendChild(document.createTextNode(money(p.price_minor)));
        }
        body.appendChild(price);
        card.appendChild(body);
        if (!p.sold_out) { card.addEventListener('click', function () { openProduct(p); }); }
        return card;
    }

    function renderGrid() {
        var grid = $('#k-grid');
        grid.textContent = '';
        var q = S.search.trim().toLocaleLowerCase('tr');
        var list = D.menu.products.filter(function (p) {
            if (q !== '') {
                return (p.name + ' ' + (p.description || '')).toLocaleLowerCase('tr').indexOf(q) !== -1;
            }
            return S.activeCat === null || p.category_id === S.activeCat;
        });
        list.forEach(function (p) { grid.appendChild(productCard(p)); });
        $('#k-noresult').hidden = list.length !== 0;

        // Öne çıkanlar yalnız aramasız ilk kategoride
        var showFeat = q === '' && D.menu.featured.length > 0;
        $('#k-featured').hidden = !showFeat;
        if (showFeat) {
            var row = $('#k-featured-row');
            row.textContent = '';
            D.menu.featured.forEach(function (id) { if (byId[id]) { row.appendChild(productCard(byId[id], true)); } });
        }
    }

    // Masa kartı ikonu (yemek masası — SVG, inline, tema rengini miras alır).
    var TABLE_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
        + '<path d="M3 8h18"/><path d="M6 8v10"/><path d="M18 8v10"/><path d="M6 13h12"/></svg>';

    function renderTables() {
        var wrap = $('#k-tables');
        wrap.textContent = '';
        D.tables.forEach(function (tb) {
            var b = el('button', 'k-tablecard');
            b.type = 'button';

            var ic = el('span', 'k-tablecard__icon');
            ic.innerHTML = TABLE_ICON;
            b.appendChild(ic);

            // Sunucu etiketi "İsim · No" olabilir; sondaki "· No" ismi zaten
            // içeriyorsa mükerrer görünmesin diye ismi temel al, sarkan ayraç
            // bırakma. İsim yoksa numara büyük gösterilir.
            var parts = String(tb.label).split(' · ');
            var name = parts[0].trim();
            var num = parts.length > 1 ? parts[parts.length - 1].trim() : '';
            var primary = name || num || tb.label;

            b.appendChild(el('span', 'k-tablecard__eyebrow', S.lang === 'tr' ? 'Masa' : 'Table'));
            b.appendChild(el('span', 'k-tablecard__no', primary));

            b.addEventListener('click', function () {
                S.tableId = tb.id; S.tableLabel = tb.label;
                enterMenu();
            });
            wrap.appendChild(b);
        });
    }

    /* ---------------- Ürün modalı ---------------- */
    function openProduct(p) {
        var defVariant = null;
        (p.variants || []).forEach(function (v) { if (v.is_default) { defVariant = v.id; } });
        if (defVariant === null && p.variants && p.variants.length) { defVariant = p.variants[0].id; }

        var defOpts = [];
        (p.option_groups || []).forEach(function (g) {
            g.options.forEach(function (o) { if (o.is_default) { defOpts.push(o.id); } });
        });

        S.modal = { product: p, variantId: defVariant, optionIds: defOpts, qty: p.min_qty || 1, note: '' };
        renderProductModal();
        $('#k-product-modal').hidden = false;
    }

    function modalUnitPrice() {
        var m = S.modal, p = m.product;
        var unit = p.price_minor;
        (p.variants || []).forEach(function (v) { if (v.id === m.variantId) { unit = v.price_minor; } });

        var optTotal = 0;
        (p.option_groups || []).forEach(function (g) {
            var sel = g.options.filter(function (o) { return m.optionIds.indexOf(o.id) !== -1; });
            // Sunucu kuralının aynısı: en pahalı free_limit seçenek ücretsiz.
            sel.sort(function (a, b) { return b.price_minor - a.price_minor; });
            sel.forEach(function (o, i) { if (i >= (g.free_limit || 0)) { optTotal += o.price_minor; } });
        });

        return unit + optTotal;
    }

    function renderProductModal() {
        var m = S.modal, p = m.product;
        var body = $('#k-pm-body');
        body.textContent = '';

        if (p.image) {
            var img = document.createElement('img');
            img.className = 'k-pm__img'; img.alt = p.name; img.src = p.image;
            body.appendChild(img);
        }
        body.appendChild(el('h2', 'k-pm__name', p.name));
        if (p.description) { body.appendChild(el('p', 'k-pm__desc', p.description)); }

        var tags = el('div', 'k-pm__tags');
        (p.allergen_ids || []).concat(p.diet_ids || []).forEach(function (id) {
            var a = D.menu.allergens[String(id)];
            if (a) { tags.appendChild(el('span', 'k-badge', a.name)); }
        });
        if (p.calories) { tags.appendChild(el('span', 'k-badge', p.calories + ' kcal')); }
        if (tags.childNodes.length) { body.appendChild(tags); }

        // Varyantlar
        if (p.variants && p.variants.length) {
            var vg = el('div', 'k-pm__group');
            var vh = el('h3', '', '');
            vh.appendChild(document.createTextNode(S.lang === 'tr' ? 'Boyut / Seçim' : 'Size / Choice'));
            vg.appendChild(vh);
            var vWrap = el('div', 'k-pm__opts');
            p.variants.forEach(function (v) {
                var lab = el('label', 'k-opt');
                var inp = document.createElement('input');
                inp.type = 'radio'; inp.name = 'k-variant'; inp.checked = m.variantId === v.id;
                inp.addEventListener('change', function () { m.variantId = v.id; refreshModalPrice(); });
                lab.appendChild(inp);
                lab.appendChild(el('span', 'k-opt__name', v.name));
                lab.appendChild(el('span', 'k-opt__price', money(v.price_minor)));
                vWrap.appendChild(lab);
            });
            vg.appendChild(vWrap);
            body.appendChild(vg);
        }

        // Seçenek grupları
        (p.option_groups || []).forEach(function (g) {
            var gw = el('div', 'k-pm__group');
            gw.setAttribute('data-group', g.id);
            var h = el('h3', '', '');
            h.appendChild(document.createTextNode(g.name));
            var notes = [];
            if (g.required) { notes.push(t('required')); }
            if (g.free_limit > 0) { notes.push(t('free_note', { n: g.free_limit })); }
            if (g.max !== null && g.type !== 'single') { notes.push(t('choose_max', { n: g.max })); }
            if (notes.length) { h.appendChild(el('small', '', ' · ' + notes.join(' · '))); }
            gw.appendChild(h);

            var single = g.type === 'single';
            var wrap = el('div', 'k-pm__opts');
            g.options.forEach(function (o) {
                var lab = el('label', 'k-opt');
                var inp = document.createElement('input');
                inp.type = single ? 'radio' : 'checkbox';
                if (single) { inp.name = 'k-grp-' + g.id; }
                inp.checked = m.optionIds.indexOf(o.id) !== -1;
                inp.addEventListener('change', function () {
                    if (single) {
                        g.options.forEach(function (other) {
                            var i = m.optionIds.indexOf(other.id);
                            if (i !== -1) { m.optionIds.splice(i, 1); }
                        });
                        if (inp.checked) { m.optionIds.push(o.id); }
                    } else {
                        var idx = m.optionIds.indexOf(o.id);
                        if (inp.checked && idx === -1) {
                            var selCount = g.options.filter(function (x) { return m.optionIds.indexOf(x.id) !== -1; }).length;
                            if (g.max !== null && selCount >= g.max) { inp.checked = false; return; }
                            m.optionIds.push(o.id);
                        } else if (!inp.checked && idx !== -1) {
                            m.optionIds.splice(idx, 1);
                        }
                    }
                    refreshModalPrice();
                });
                lab.appendChild(inp);
                lab.appendChild(el('span', 'k-opt__name', o.name));
                lab.appendChild(el('span', 'k-opt__price', o.price_minor > 0 ? '+' + money(o.price_minor) : ''));
                wrap.appendChild(lab);
            });
            gw.appendChild(wrap);
            body.appendChild(gw);
        });

        // Kalem notu
        var noteWrap = el('label', 'k-field k-pm__note');
        noteWrap.appendChild(el('span', '', t('item_note_ph')));
        var noteInp = document.createElement('input');
        noteInp.type = 'text'; noteInp.maxLength = 255;
        noteInp.addEventListener('input', function () { m.note = noteInp.value; });
        noteWrap.appendChild(noteInp);
        body.appendChild(noteWrap);

        body.appendChild(el('p', 'k-pm__err', ''));

        $('#k-pm-qty').textContent = String(m.qty);
        refreshModalPrice();
    }

    function refreshModalPrice() {
        var m = S.modal;
        $('#k-pm-add').textContent = t('add') + ' · ' + money(modalUnitPrice() * m.qty);
    }

    function validateModal() {
        var m = S.modal, p = m.product;
        var err = '';
        (p.option_groups || []).forEach(function (g) {
            var count = g.options.filter(function (o) { return m.optionIds.indexOf(o.id) !== -1; }).length;
            var min = g.required ? Math.max(1, g.min || 0) : (g.min || 0);
            if (g.required && count < min && err === '') {
                err = g.name + ': ' + t('choose_min', { n: min });
            }
        });
        $('#k-pm-body .k-pm__err').textContent = err;
        return err === '';
    }

    /* ---------------- Sepet ---------------- */
    function cartLine(item) {
        var p = byId[item.productId];
        if (!p) { return null; }
        var unit = p.price_minor;
        var name = p.name;
        (p.variants || []).forEach(function (v) { if (v.id === item.variantId) { unit = v.price_minor; name += ' (' + v.name + ')'; } });
        var optTotal = 0;
        var optNames = [];
        (p.option_groups || []).forEach(function (g) {
            var sel = g.options.filter(function (o) { return item.optionIds.indexOf(o.id) !== -1; });
            sel.sort(function (a, b) { return b.price_minor - a.price_minor; });
            sel.forEach(function (o, i) {
                optNames.push(o.name);
                if (i >= (g.free_limit || 0)) { optTotal += o.price_minor; }
            });
        });
        return { name: name, optNames: optNames, lineTotal: (unit + optTotal) * item.qty };
    }

    function cartTotal() {
        return S.cart.reduce(function (sum, item) {
            var line = cartLine(item);
            return sum + (line ? line.lineTotal : 0);
        }, 0);
    }

    function renderCartBadge() {
        var count = S.cart.reduce(function (n, i) { return n + i.qty; }, 0);
        var badge = $('#k-cartcount');
        badge.hidden = count === 0;
        badge.textContent = String(count);
    }

    function renderCart() {
        var wrap = $('#k-cartlist');
        wrap.textContent = '';
        S.cart.forEach(function (item) {
            var line = cartLine(item);
            if (!line) { return; }
            var row = el('div', 'k-cartrow');
            var info = el('div', 'k-cartrow__info');
            info.appendChild(el('div', 'k-cartrow__name', line.name));
            if (line.optNames.length) { info.appendChild(el('div', 'k-cartrow__opts', line.optNames.join(', '))); }
            if (item.note) { info.appendChild(el('div', 'k-cartrow__opts', '✎ ' + item.note)); }
            row.appendChild(info);

            var qty = el('div', 'k-qty');
            var dec = el('button', 'k-qty__btn', '−'); dec.type = 'button';
            dec.addEventListener('click', function () {
                var p = byId[item.productId];
                var min = (p && p.min_qty) || 1;
                if (item.qty - 1 < min) { removeItem(item.uid); } else { item.qty -= 1; renderCart(); renderCartBadge(); }
            });
            var val = el('span', 'k-qty__val', String(item.qty));
            var inc = el('button', 'k-qty__btn', '+'); inc.type = 'button';
            inc.addEventListener('click', function () {
                var p = byId[item.productId];
                var max = (p && p.max_qty) || 50;
                if (item.qty < Math.min(max, 50)) { item.qty += 1; renderCart(); renderCartBadge(); }
            });
            qty.appendChild(dec); qty.appendChild(val); qty.appendChild(inc);
            row.appendChild(qty);

            row.appendChild(el('div', 'k-cartrow__price', money(line.lineTotal)));

            var del = el('button', 'k-cartrow__del', '🗑'); del.type = 'button';
            del.setAttribute('aria-label', 'Sil');
            del.addEventListener('click', function () { removeItem(item.uid); });
            row.appendChild(del);

            wrap.appendChild(row);
        });

        $('#k-cartempty').hidden = S.cart.length !== 0;
        $('#k-cartnext').disabled = S.cart.length === 0;
        $('#k-carttotal').textContent = money(cartTotal());
    }

    function removeItem(uid) {
        S.cart = S.cart.filter(function (i) { return i.uid !== uid; });
        renderCart();
        renderCartBadge();
    }

    /* ---------------- Özet ---------------- */
    function renderSubmitLabel() {
        var btn = $('#k-submit');
        if (btn) { btn.textContent = D.payment_mode === 'kiosk_pos' ? t('confirm_pay') : t('confirm_send'); }
    }

    function renderSummary() {
        var meta = $('#k-summary-meta');
        meta.textContent = '';
        meta.appendChild(el('span', 'k-badge', t(S.orderType)));
        if (S.orderType === 'dine_in' && S.tableLabel) {
            meta.appendChild(el('span', 'k-badge', t('table') + ': ' + S.tableLabel));
        }

        var items = $('#k-summary-items');
        items.textContent = '';
        S.cart.forEach(function (item) {
            var line = cartLine(item);
            if (!line) { return; }
            var row = el('div', 'k-sumrow');
            row.appendChild(el('span', '', item.qty + ' × ' + line.name + (line.optNames.length ? ' (' + line.optNames.join(', ') + ')' : '')));
            row.appendChild(el('strong', '', money(line.lineTotal)));
            items.appendChild(row);
        });

        $('#k-sumtotal').textContent = money(cartTotal());
        renderSubmitLabel();
    }

    /* ---------------- Sipariş gönderimi + ödeme ---------------- */
    function post(path, body) {
        return fetch(path, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
            body: JSON.stringify(body)
        }).then(function (res) {
            return res.json().catch(function () { return {}; }).then(function (json) {
                return { status: res.status, json: json };
            });
        });
    }

    function submitOrder() {
        if (S.submitting) { return; }
        if (!navigator.onLine) { showPayError(t('err_offline'), true); return; }

        S.submitting = true;
        show('payment');
        setPayState('sending');

        var payload = {
            token: D.token,
            device_token: deviceToken,
            order_type: S.orderType,
            table_id: S.orderType === 'dine_in' ? S.tableId : null,
            customer_name: $('#k-name').value.trim() || null,
            note: $('#k-note').value.trim() || null,
            items: S.cart.map(function (i) {
                return {
                    product_id: i.productId,
                    variant_id: i.variantId,
                    qty: i.qty,
                    note: i.note || null,
                    option_ids: i.optionIds
                };
            })
        };

        // Idempotency: bu gönderim denemesinin tek anahtarı (çift dokunma /
        // ağ tekrarı siparişi ve tahsilatı ÇOĞALTMAZ; yeni deneme yeni anahtar).
        var idemKey = 'kiosk-' + Date.now() + '-' + Math.random().toString(36).slice(2, 10);

        fetch(D.endpoints.order, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Idempotency-Key': idemKey
            },
            body: JSON.stringify(payload)
        }).then(function (res) {
            return res.json().catch(function () { return {}; }).then(function (json) {
                handleOrderResponse(res.status, json);
            });
        }).catch(function () {
            // Ağ koptu: sipariş gitmiş olabilir de olmayabilir de — DÜRÜST ol.
            S.submitting = false;
            showPayError(navigator.onLine ? t('err_generic') : t('err_offline'), true);
        });
    }

    function handleOrderResponse(status, json) {
        S.submitting = false;

        // Cihaz kilidi: bu bağlantı başka cihaza kilitli → engelleyici kilit ekranı.
        if (status === 403 && json && json.result === 'locked_device') {
            showDeviceLocked(json.message);
            return;
        }

        // Panel-kilitli cihaz (KioskOrderController::resolveDeviceOrFail 'locked'
        // durumu → 423): jenerik "tekrar dene" dalına düşürüp aynı hatayı tekrar
        // üretmek yerine sayfa yeniden yüklenir — sunucu /kiosk/{token}'ı tekrar
        // çözer ve kendini 15sn'de bir yoklayan kiosk.locked ekranını döner (kilit
        // kalkınca otomatik kiosk ekranına geri döner). Kullanıcı aktif "tekrar
        // dene" döngüsüne girmez, pasifçe bekler.
        if (status === 423) {
            hardReset();
            return;
        }

        if (json && (json.result === 'paid' || json.result === 'placed_pay_at_counter')) {
            showReceipt(json.receipt);
            return;
        }

        if (status === 202 && json && json.result === 'payment_pending') {
            S.paymentRef = json.reference;
            S.pollLeft = D.timing.poll_max;
            setPayState('pending');
            pollPayment();
            return;
        }

        // Dürüst hata: 402 (kart reddi), 422 (doğrulama), 429, 5xx…
        showPayError((json && json.message) ? json.message : t('err_generic'), true);
    }

    function pollPayment() {
        if (S.pollLeft <= 0) {
            // Belirsizlik dürüstçe söylenir; ASLA başarı varsayılmaz (§22).
            showPayError(t('pay_unknown'), false);
            return;
        }
        S.pollLeft -= 1;

        post(D.endpoints.payment_query, { token: D.token, reference: S.paymentRef })
            .then(function (r) {
                if (r.json && (r.json.result === 'paid')) { showReceipt(r.json.receipt); return; }
                if (r.status === 402) { showPayError((r.json && r.json.message) || t('pay_fail_title'), true); return; }
                // hâlâ pending / ağ belirsizliği → tekrar dene
                setTimeout(pollPayment, D.timing.poll * 1000);
            })
            .catch(function () { setTimeout(pollPayment, D.timing.poll * 1000); });
    }

    function setPayState(state) {
        var scr = $('[data-screen="payment"]');
        scr.classList.remove('is-error');
        $('#k-pay-actions').hidden = true;
        if (state === 'sending') {
            $('#k-pay-title').textContent = D.payment_mode === 'kiosk_pos' ? t('pay_title') : t('pay_sending');
            $('#k-pay-msg').textContent = t('pay_sending');
        } else if (state === 'pending') {
            $('#k-pay-title').textContent = t('pay_title');
            $('#k-pay-msg').textContent = t('pay_wait');
        }
    }

    function showPayError(message, canRetry) {
        show('payment');
        var scr = $('[data-screen="payment"]');
        scr.classList.add('is-error');
        $('#k-pay-title').textContent = t('pay_fail_title');
        $('#k-pay-msg').textContent = message;
        var actions = $('#k-pay-actions');
        actions.hidden = false;
        actions.querySelector('[data-action="pay-back"]').hidden = !canRetry;
    }

    /* ---------------- Fiş ---------------- */
    var receiptTimer = null;

    function showReceipt(receipt) {
        S.receipt = receipt;
        show('receipt');

        $('#k-rc-no').textContent = '#' + receipt.order_no;
        $('#k-rc-counter').hidden = !receipt.pay_at_counter;

        var items = $('#k-rc-items');
        items.textContent = '';
        (receipt.items || []).forEach(function (i) {
            var row = el('div', 'k-sumrow');
            row.appendChild(el('span', '', i.qty + ' × ' + i.name + (i.options && i.options.length ? ' (' + i.options.join(', ') + ')' : '')));
            row.appendChild(el('strong', '', money(i.line_total_minor)));
            items.appendChild(row);
        });
        $('#k-rc-total').textContent = money(receipt.total_minor);

        var pay = $('#k-rc-pay');
        if (receipt.payment && receipt.paid) {
            pay.hidden = false;
            pay.textContent = t('paid_with_card')
                + (receipt.payment.auth_code ? ' · ' + t('auth_code') + ': ' + receipt.payment.auth_code : '')
                + ' · ' + receipt.payment.reference;
        } else {
            pay.hidden = true;
        }

        // Fiş ekranı kendini sıfırlar — sonraki müşteri fişi de göremez (§18).
        var left = D.timing.receipt;
        $('#k-rc-count').textContent = String(left);
        clearInterval(receiptTimer);
        receiptTimer = setInterval(function () {
            left -= 1;
            $('#k-rc-count').textContent = String(left);
            if (left <= 0) { hardReset(); }
        }, 1000);
    }

    /* ---------------- SIFIRLAMA (§18) ---------------- */
    function hardReset() {
        // Tam sayfa yeniden yükleme: JS belleği, form alanları, sepet, isim —
        // her şey yok olur. Sunucuda oturum yoktur, saklanacak bir şey kalmaz.
        location.reload();
    }

    /* ---------------- Zaman aşımı (§18) ---------------- */
    var idleTimer = null, warnTimer = null, warnInterval = null;

    function idleArmed() {
        // Karşılamada sayaç gerekmez; ödeme doğrulanırken sıfırlama YAPILMAZ
        // (kart çekilmiş olabilir — fiş/hata ekranı beklenir).
        return S.screen !== 'attract' && S.screen !== 'payment';
    }

    function resetIdle() {
        clearTimeout(idleTimer); clearTimeout(warnTimer); clearInterval(warnInterval);
        $('#k-idle-modal').hidden = true;
        if (!idleArmed()) { return; }
        idleTimer = setTimeout(showIdleWarning, D.timing.idle * 1000);
    }

    function showIdleWarning() {
        if (!idleArmed()) { return; }
        var left = D.timing.warn;
        $('#k-idle-count').textContent = String(left);
        $('#k-idle-modal').hidden = false;
        warnInterval = setInterval(function () {
            left -= 1;
            $('#k-idle-count').textContent = String(left);
            if (left <= 0) { hardReset(); }
        }, 1000);
    }

    ['pointerdown', 'keydown', 'touchstart'].forEach(function (evt) {
        document.addEventListener(evt, function (e) {
            if (!$('#k-idle-modal').hidden) { return; } // uyarı yalnız butonla kapanır
            resetIdle();
        }, { passive: true });
    });

    /* ---------------- Çevrimdışı (§22) ---------------- */
    function setOffline(off) { $('#k-offline').hidden = !off; }
    window.addEventListener('online', function () { setOffline(false); });
    window.addEventListener('offline', function () { setOffline(true); });
    setOffline(!navigator.onLine);

    /* ---------------- Kalp atışı (uzaktan kilit + sağlık + cihaz kilidi) ---------------- */
    function runHeartbeat() {
        post(D.endpoints.heartbeat, { token: D.token, device_token: deviceToken })
            .then(function (r) {
                if (r.status === 410 || r.status === 404) { hardReset(); return; } // token yenilendi/iptal
                var j = r.json || {};
                // Cihaz kilidi: ilk bağlanmada sunucu kimlik verir → sakla.
                if (j.device_token) { saveDeviceToken(j.device_token); }
                // Bu bağlantı başka cihaza kilitli → engelleyici kilit ekranı.
                if (j.status === 'locked_device') { showDeviceLocked(j.message); return; }
                if (j.status === 'locked' && S.screen === 'attract') { hardReset(); }
                setOffline(false);
            })
            .catch(function () { setOffline(!navigator.onLine ? true : false); });
    }
    setInterval(runHeartbeat, D.timing.heartbeat * 1000);
    runHeartbeat(); // ilk açılışta hemen: cihaz kilidini erken kur/doğrula

    /* ---------------- Akış ---------------- */
    function enterMenu() {
        S.activeCat = D.menu.categories.length ? D.menu.categories[0].id : null;
        renderCats();
        renderGrid();
        show('menu');
    }

    document.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-action]');
        if (!btn) { return; }
        var action = btn.getAttribute('data-action');

        switch (action) {
            case 'start': show('type'); break;
            case 'back-attract': show('attract'); break;
            case 'back-type': show('type'); break;
            case 'pick-type':
                S.orderType = btn.getAttribute('data-type');
                if (S.orderType === 'dine_in') {
                    if (D.tables.length === 0) { S.orderType = 'takeaway'; enterMenu(); break; }
                    renderTables(); show('tables');
                } else {
                    S.tableId = null; S.tableLabel = null; enterMenu();
                }
                break;
            case 'open-cart': renderCart(); show('cart'); break;
            case 'back-menu': show('menu'); break;
            case 'back-cart': renderCart(); show('cart'); break;
            case 'to-summary':
                if (S.cart.length === 0) { break; }
                renderSummary(); show('summary');
                break;
            case 'submit': submitOrder(); break;
            case 'pay-back': renderCart(); show('cart'); break;
            case 'close-modal': $('#k-product-modal').hidden = true; S.modal = null; break;
            case 'qty-dec':
                if (S.modal && S.modal.qty > (S.modal.product.min_qty || 1)) { S.modal.qty -= 1; $('#k-pm-qty').textContent = String(S.modal.qty); refreshModalPrice(); }
                break;
            case 'qty-inc':
                if (S.modal) {
                    var mx = Math.min(S.modal.product.max_qty || 50, 50);
                    if (S.modal.qty < mx) { S.modal.qty += 1; $('#k-pm-qty').textContent = String(S.modal.qty); refreshModalPrice(); }
                }
                break;
            case 'add-to-cart':
                if (S.modal && validateModal()) {
                    S.cart.push({
                        uid: newUid(),
                        productId: S.modal.product.id,
                        variantId: S.modal.variantId,
                        qty: S.modal.qty,
                        note: S.modal.note.trim(),
                        optionIds: S.modal.optionIds.slice()
                    });
                    $('#k-product-modal').hidden = true;
                    S.modal = null;
                    renderCartBadge();
                }
                break;
            case 'restart-confirm': $('#k-restart-modal').hidden = false; break;
            case 'close-restart': $('#k-restart-modal').hidden = true; break;
            case 'restart': hardReset(); break;
            case 'idle-continue': resetIdle(); break;
            case 'toggle-a11y': {
                var html = document.documentElement;
                var on = html.getAttribute('data-kiosk-a11y') === '1';
                html.setAttribute('data-kiosk-a11y', on ? '0' : '1');
                btn.setAttribute('aria-pressed', on ? 'false' : 'true');
                break;
            }
            case 'lang':
                S.lang = btn.getAttribute('data-lang');
                applyLang();
                if (S.screen === 'menu') { renderGrid(); }
                if (S.screen === 'summary') { renderSummary(); }
                break;
        }
    });

    $('#k-search').addEventListener('input', function (e) {
        S.search = e.target.value;
        renderGrid();
    });

    /* ---------------- Başlat ---------------- */
    applyLang();
    show('attract');
    resetIdle();
})();
