{{--
    /kiosk/{token} — Self-servis kiosk sipariş ekranı (Faz 8).

    Ekranlar [data-screen] bölümleridir; kiosk.js durum makinesi olarak
    aralarında geçer. Dinamik listeler (kategori/ürün/sepet/fiş) JS'te
    textContent ile kurulur (XSS-güvenli). Veri #kiosk-data JSON bloğunda.
--}}
@extends('kiosk.layout')

@section('title', $tenantName.' — Kiosk')

@section('content')
    <div id="k-app" class="k-app" data-state="attract">

        {{-- ============ Çevrimdışı şeridi (§22: dürüst uyarı) ============ --}}
        <div class="k-offline" id="k-offline" hidden role="alert">
            <span aria-hidden="true">⚠</span>
            <span data-i18n="offline">İnternet bağlantısı yok. Sipariş ve ödeme şu an alınamıyor.</span>
        </div>

        {{-- ==== Cihaz kilidi (feature: device_lock) — bu bağlantı başka cihaza kilitli ====
             kiosk.js showDeviceLocked() display:flex ile açar; kapalıyken (varsayılan)
             sunucu 'locked_device' döndürmez → hiç görünmez. --}}
        <div id="k-devlock" role="alertdialog" aria-modal="true"
             style="display:none;position:fixed;inset:0;z-index:9999;flex-direction:column;align-items:center;justify-content:center;gap:18px;padding:32px;background:#0b1220;color:#e5edff;text-align:center;font-family:inherit">
            <div style="font-size:64px" aria-hidden="true">🔒</div>
            <h2 style="margin:0;font-size:26px;font-weight:800">Bu cihaz kilitli</h2>
            <p id="k-devlock-msg" style="margin:0;max-width:520px;font-size:17px;line-height:1.5;opacity:.85">Bu kiosk bağlantısı başka bir cihaza kilitli.</p>
            <p style="margin:0;font-size:14px;opacity:.6">Yetkili personel “İzinli Cihazlar” ekranından bu bağlantıyı bu cihaza aktarabilir.</p>
        </div>

        {{-- ============ 1) Karşılama ============ --}}
        <section class="k-screen k-attract" data-screen="attract">
            <div class="k-attract__inner">
                <div class="k-attract__brand" aria-hidden="true">
                    <svg width="72" height="72" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2"/><path d="M7 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"/></svg>
                </div>
                <h1 class="k-attract__name">{{ $tenantName }}</h1>
                <p class="k-attract__branch">{{ $branchName }}</p>
                <button type="button" class="k-btn k-btn--hero" data-action="start">
                    <span data-i18n="tap_to_start">Sipariş vermek için dokunun</span>
                </button>
                <p class="k-attract__hint" data-i18n="self_service">Self-servis sipariş ekranı</p>
            </div>
        </section>

        {{-- ============ 2) Sipariş tipi ============ --}}
        <section class="k-screen" data-screen="type" hidden>
            <header class="k-head">
                <button type="button" class="k-btn k-btn--ghost" data-action="back-attract">‹ <span data-i18n="back">Geri</span></button>
                <h2 data-i18n="how_to_eat">Siparişinizi nasıl alırsınız?</h2>
                <span></span>
            </header>
            <div class="k-typegrid">
                <button type="button" class="k-typecard" data-action="pick-type" data-type="dine_in">
                    <span class="k-typecard__icon" aria-hidden="true">🍽</span>
                    <span class="k-typecard__label" data-i18n="dine_in">Masada servis</span>
                    <span class="k-typecard__sub" data-i18n="dine_in_sub">Masanıza getirelim</span>
                </button>
                <button type="button" class="k-typecard" data-action="pick-type" data-type="takeaway">
                    <span class="k-typecard__icon" aria-hidden="true">🥡</span>
                    <span class="k-typecard__label" data-i18n="takeaway">Gel-al</span>
                    <span class="k-typecard__sub" data-i18n="takeaway_sub">Tezgâhtan teslim alın</span>
                </button>
                <button type="button" class="k-typecard" data-action="pick-type" data-type="package">
                    <span class="k-typecard__icon" aria-hidden="true">📦</span>
                    <span class="k-typecard__label" data-i18n="package">Paket</span>
                    <span class="k-typecard__sub" data-i18n="package_sub">Paketleyelim</span>
                </button>
            </div>
        </section>

        {{-- ============ 3) Masa seçimi (masada servis) ============ --}}
        <section class="k-screen" data-screen="tables" hidden>
            <header class="k-head">
                <button type="button" class="k-btn k-btn--ghost" data-action="back-type">‹ <span data-i18n="back">Geri</span></button>
                <h2 data-i18n="pick_table">Masanızı seçin</h2>
                <span></span>
            </header>
            <div class="k-tablegrid" id="k-tables"></div>
        </section>

        {{-- ============ 4) Menü ============ --}}
        <section class="k-screen k-menu" data-screen="menu" hidden>
            <header class="k-menuhead">
                <button type="button" class="k-btn k-btn--ghost" data-action="restart-confirm" data-i18n="start_over">Baştan başla</button>
                <div class="k-menuhead__search">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                    <input type="search" id="k-search" autocomplete="off" data-i18n-ph="search_ph" placeholder="Ürün ara…" aria-label="Ürün ara">
                </div>
                <button type="button" class="k-btn k-btn--cart" data-action="open-cart" id="k-cartbtn">
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg>
                    <span data-i18n="cart">Sepet</span>
                    <span class="k-cartbtn__badge" id="k-cartcount" hidden>0</span>
                </button>
            </header>
            <div class="k-menubody">
                <nav class="k-cats" id="k-cats" aria-label="Kategoriler"></nav>
                <div class="k-products">
                    <div class="k-featured" id="k-featured" hidden>
                        <h3 data-i18n="featured">Öne çıkanlar</h3>
                        <div class="k-featured__row" id="k-featured-row"></div>
                    </div>
                    <div class="k-grid" id="k-grid"></div>
                    <p class="k-empty" id="k-noresult" hidden data-i18n="no_result">Aramanızla eşleşen ürün yok.</p>
                </div>
            </div>
        </section>

        {{-- ============ 5) Sepet ============ --}}
        <section class="k-screen" data-screen="cart" hidden>
            <header class="k-head">
                <button type="button" class="k-btn k-btn--ghost" data-action="back-menu">‹ <span data-i18n="back_menu">Menüye dön</span></button>
                <h2 data-i18n="your_cart">Sepetiniz</h2>
                <span></span>
            </header>
            <div class="k-cartlist" id="k-cartlist"></div>
            <p class="k-empty" id="k-cartempty" hidden data-i18n="cart_empty">Sepetiniz boş.</p>
            <footer class="k-foot">
                <div class="k-foot__total">
                    <span data-i18n="total">Toplam</span>
                    <strong id="k-carttotal">0,00 ₺</strong>
                </div>
                <button type="button" class="k-btn k-btn--primary" data-action="to-summary" id="k-cartnext" data-i18n="continue">Devam et</button>
            </footer>
        </section>

        {{-- ============ 6) Özet ============ --}}
        <section class="k-screen" data-screen="summary" hidden>
            <header class="k-head">
                <button type="button" class="k-btn k-btn--ghost" data-action="back-cart">‹ <span data-i18n="back">Geri</span></button>
                <h2 data-i18n="order_summary">Sipariş özeti</h2>
                <span></span>
            </header>
            <div class="k-summary">
                <div class="k-summary__meta" id="k-summary-meta"></div>
                <div class="k-summary__items" id="k-summary-items"></div>
                <label class="k-field">
                    <span data-i18n="your_name">Adınız (isteğe bağlı — sıra anonsu için)</span>
                    <input type="text" id="k-name" maxlength="120" autocomplete="off">
                </label>
                <label class="k-field">
                    <span data-i18n="order_note">Sipariş notu (isteğe bağlı)</span>
                    <input type="text" id="k-note" maxlength="500" autocomplete="off">
                </label>
            </div>
            <footer class="k-foot">
                <div class="k-foot__total">
                    <span data-i18n="total">Toplam</span>
                    <strong id="k-sumtotal">0,00 ₺</strong>
                </div>
                <button type="button" class="k-btn k-btn--primary" data-action="submit" id="k-submit"></button>
            </footer>
        </section>

        {{-- ============ 7) Ödeme ============ --}}
        <section class="k-screen k-payscreen" data-screen="payment" hidden>
            <div class="k-center__card">
                <div class="k-pay__anim" id="k-pay-anim" aria-hidden="true">
                    <svg width="88" height="88" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="14" x="2" y="5" rx="2"/><line x1="2" x2="22" y1="10" y2="10"/></svg>
                </div>
                <h2 id="k-pay-title" data-i18n="pay_title">Kartınızı POS cihazına okutun</h2>
                <p id="k-pay-msg" class="k-pay__msg" aria-live="polite"></p>
                <div class="k-pay__actions" id="k-pay-actions" hidden>
                    <button type="button" class="k-btn k-btn--ghost" data-action="pay-back" data-i18n="back_cart">Sepete dön</button>
                    <button type="button" class="k-btn k-btn--primary" data-action="restart" data-i18n="new_order">Yeni sipariş</button>
                </div>
            </div>
        </section>

        {{-- ============ 8) Fiş ============ --}}
        <section class="k-screen k-payscreen" data-screen="receipt" hidden>
            <div class="k-center__card k-receipt">
                <div class="k-receipt__check" aria-hidden="true">✓</div>
                <h2 data-i18n="order_received">Siparişiniz alındı</h2>
                <p class="k-receipt__no"><span data-i18n="order_no">Sipariş No</span>: <strong id="k-rc-no">—</strong></p>
                <p class="k-receipt__counter" id="k-rc-counter" hidden data-i18n="pay_at_counter">Lütfen kasada ödeyiniz.</p>
                <div class="k-receipt__items" id="k-rc-items"></div>
                <p class="k-receipt__total"><span data-i18n="total">Toplam</span>: <strong id="k-rc-total"></strong></p>
                <p class="k-receipt__pay" id="k-rc-pay" hidden></p>
                <button type="button" class="k-btn k-btn--primary" data-action="restart">
                    <span data-i18n="new_order">Yeni sipariş</span> (<span id="k-rc-count">45</span>)
                </button>
            </div>
        </section>

        {{-- ============ Ürün modalı ============ --}}
        <div class="k-modal" id="k-product-modal" hidden role="dialog" aria-modal="true">
            <div class="k-modal__panel">
                <button type="button" class="k-modal__close" data-action="close-modal" aria-label="Kapat">×</button>
                <div class="k-modal__scroll" id="k-pm-body"></div>
                <footer class="k-modal__foot">
                    <div class="k-qty">
                        <button type="button" class="k-qty__btn" data-action="qty-dec" aria-label="Azalt">−</button>
                        <span class="k-qty__val" id="k-pm-qty">1</span>
                        <button type="button" class="k-qty__btn" data-action="qty-inc" aria-label="Artır">+</button>
                    </div>
                    <button type="button" class="k-btn k-btn--primary" data-action="add-to-cart" id="k-pm-add"></button>
                </footer>
            </div>
        </div>

        {{-- ============ Zaman aşımı modalı (§18) ============ --}}
        <div class="k-modal" id="k-idle-modal" hidden role="alertdialog" aria-modal="true">
            <div class="k-modal__panel k-modal__panel--small">
                <h2 data-i18n="still_there">Orada mısınız?</h2>
                <p><span data-i18n="idle_msg">İşlem yapılmazsa ekran sıfırlanacak:</span> <strong id="k-idle-count">20</strong> sn</p>
                <div class="k-modal__btns">
                    <button type="button" class="k-btn k-btn--primary k-btn--wide" data-action="idle-continue" data-i18n="im_here">Devam ediyorum</button>
                </div>
            </div>
        </div>

        {{-- ============ Baştan başla onayı ============ --}}
        <div class="k-modal" id="k-restart-modal" hidden role="alertdialog" aria-modal="true">
            <div class="k-modal__panel k-modal__panel--small">
                <h2 data-i18n="restart_q">Baştan başlansın mı?</h2>
                <p data-i18n="restart_msg">Sepetiniz ve girdiğiniz bilgiler silinecek.</p>
                <div class="k-modal__btns">
                    <button type="button" class="k-btn k-btn--ghost" data-action="close-restart" data-i18n="cancel">Vazgeç</button>
                    <button type="button" class="k-btn k-btn--primary" data-action="restart" data-i18n="yes_restart">Evet, sıfırla</button>
                </div>
            </div>
        </div>

        {{-- ============ Kalıcı alt çubuk: dil + erişilebilirlik ============ --}}
        <div class="k-dock">
            <button type="button" class="k-dock__btn" data-action="toggle-a11y" aria-pressed="false">
                <span aria-hidden="true">👁</span> <span data-i18n="a11y">Kolay okuma</span>
            </button>
            <span class="k-dock__brand">{{ $deviceName }} · powered by bogahost</span>
            <div class="k-dock__langs" role="group" aria-label="Dil / Language">
                <button type="button" class="k-dock__btn is-active" data-action="lang" data-lang="tr">TR</button>
                <button type="button" class="k-dock__btn" data-action="lang" data-lang="en">EN</button>
            </div>
        </div>
    </div>

    <script type="application/json" id="kiosk-data">@json($payload)</script>
@endsection

@push('scripts')
    <script src="/assets/kiosk.js?v=20260806.1" defer></script>
@endpush
