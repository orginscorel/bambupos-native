<?php

use App\Modules\Payments\Providers\CardPresentProvider;
use App\Modules\Payments\Providers\CashProvider;
use App\Modules\Payments\Providers\DemoPosProvider;
use App\Modules\Payments\Providers\GenericRestPosProvider;
use App\Modules\Payments\Providers\GenericXmlPosProvider;
use App\Modules\Payments\Providers\MockPosProvider;
use App\Modules\Payments\Providers\SandboxPosProvider;

/**
 * Payments modülü ayarları (Faz-5, ADR-010).
 *
 * ENTEGRATÖR MİMARİSİ: çekirdek kod sağlayıcıdan BAĞIMSIZDIR. Her işletme (tenant)
 * kendi cihazını `tenant_integrations` (key='pos_terminal') config'inde seçer; yeni
 * banka/YN-POS/TSM eklemek çoğunlukla `presets`e satır + kimlik bilgisidir ("kod
 * değil konfig"). `generic_rest` adaptörü herhangi bir REST/TSM ucuna config ile takılır.
 */
return [

    // Terminal (kredi/banka kartı) yöntemlerinin GLOBAL varsayılan sağlayıcısı.
    // İşletme kendi 'pos_terminal' entegrasyonunu tanımlamadıysa bu kullanılır.
    'default_terminal_provider' => env('PAYMENTS_TERMINAL_PROVIDER', 'mock'),

    // Sağlayıcı kayıt defteri: anahtar → adapter sınıfı.
    'providers' => [
        'cash' => CashProvider::class,
        'card_present' => CardPresentProvider::class,
        'mock' => MockPosProvider::class,
        // DEMO: her tutarı onaylar (sunum için; mock'un ,95–,99 red mayınını kaldırır).
        'demo' => DemoPosProvider::class,
        'sandbox' => SandboxPosProvider::class,
        // Config-tabanlı jenerik entegratörler: REST/TSM (JSON) + banka XML/SOAP.
        'generic_rest' => GenericRestPosProvider::class,
        'generic_soap' => GenericXmlPosProvider::class,
    ],

    /*
     * SAĞLAYICI KATALOĞU — UI/servis her sağlayıcıya TEK-BİÇİMDE uyum sağlar
     * (yetenekler + kurulum alanları). Yeni sağlayıcı = katalog + preset satırı.
     */
    /*
     * 'simulated' (FAZ2, kasa POS-durum göstergesi): true = bu sağlayıcı gerçek bir
     * banka/ECR'a bağlı DEĞİL (test/sunum/yapılandırılmamış iskelet) — kasiyer
     * ekranı bunu görüp personeli yanlış yönlendirmesin diye rozet/uyarı gösterir.
     * Yeni sağlayıcı eklerken bu alanı DOĞRU işaretleyin; unutulursa terminalStatus()
     * güvenli tarafta kalıp simulated=true varsayar (bkz. PaymentController).
     */
    'catalog' => [
        'cash' => [
            'label' => 'Nakit', 'terminal' => false, 'fiscal' => false, 'simulated' => false,
            'refund' => true, 'partial_refund' => true, 'void' => true,
            'callback' => false, 'requires_terminal_id' => false, 'fields' => [],
        ],
        'card_present' => [
            'label' => 'Kart (manuel/harici POS)', 'terminal' => false, 'fiscal' => false, 'simulated' => false,
            'refund' => true, 'partial_refund' => true, 'void' => true,
            'callback' => false, 'requires_terminal_id' => false, 'fields' => [],
        ],
        'mock' => [
            'label' => 'Simülasyon (test)', 'terminal' => true, 'fiscal' => false, 'simulated' => true,
            'refund' => true, 'partial_refund' => true, 'void' => true,
            'callback' => true, 'requires_terminal_id' => false, 'fields' => [],
        ],
        'demo' => [
            'label' => 'Demo (her ödemeyi onaylar — sunum)', 'terminal' => true, 'fiscal' => false, 'simulated' => true,
            'refund' => true, 'partial_refund' => true, 'void' => true,
            'callback' => false, 'requires_terminal_id' => false, 'fields' => [],
        ],
        'sandbox' => [
            // SandboxPosProvider: gerçek entegrasyon YOK, her çağrı yapılandırılmadı
            // hatası döner (bkz. app/Modules/Payments/Providers/SandboxPosProvider.php).
            'label' => 'Sandbox (entegrasyon iskeleti — bağlı değil)', 'terminal' => true, 'fiscal' => false, 'simulated' => true,
            'refund' => false, 'partial_refund' => false, 'void' => false,
            'callback' => false, 'requires_terminal_id' => false, 'fields' => [],
        ],
        'generic_rest' => [
            'label' => 'Entegratör (REST/TSM POS)', 'terminal' => true, 'fiscal' => true, 'simulated' => false,
            'refund' => true, 'partial_refund' => true, 'void' => true,
            'callback' => true, 'requires_terminal_id' => true,
            // Kurulum sihirbazının soracağı alanlar (preset bunları ön-doldurur).
            'fields' => [
                ['key' => 'preset', 'label' => 'Cihaz/Sağlayıcı', 'type' => 'preset', 'required' => false],
                ['key' => 'base_url', 'label' => 'API adresi (base_url)', 'type' => 'url', 'required' => true],
                ['key' => 'merchant_id', 'label' => 'Üye işyeri no', 'type' => 'text', 'required' => true],
                ['key' => 'defaults.terminal_id', 'label' => 'Terminal no', 'type' => 'text', 'required' => false],
                ['key' => 'auth.key_id', 'label' => 'API anahtar kimliği', 'type' => 'text', 'required' => false],
                ['key' => 'auth.secret', 'label' => 'API gizli anahtar', 'type' => 'secret', 'required' => true],
                ['key' => 'callback.secret', 'label' => 'Callback imza sırrı', 'type' => 'secret', 'required' => false],
            ],
        ],
        'generic_soap' => [
            'label' => 'Banka Sanal POS (XML/SOAP)', 'terminal' => false, 'fiscal' => false, 'simulated' => false,
            'refund' => true, 'partial_refund' => true, 'void' => true,
            'callback' => true, 'requires_terminal_id' => true,
            // Banka VPOS kimlikleri XML gövdesinde taşınır (kullanıcı/şifre/mağaza no).
            'fields' => [
                ['key' => 'preset', 'label' => 'Banka', 'type' => 'preset', 'required' => false],
                ['key' => 'base_url', 'label' => 'Sanal POS adresi (base_url)', 'type' => 'url', 'required' => true],
                ['key' => 'merchant_id', 'label' => 'Üye işyeri no (ClientId/MerchantID)', 'type' => 'text', 'required' => true],
                ['key' => 'defaults.terminal_id', 'label' => 'Terminal no', 'type' => 'text', 'required' => false],
                ['key' => 'auth.username', 'label' => 'API kullanıcı adı', 'type' => 'text', 'required' => true],
                ['key' => 'auth.password', 'label' => 'API şifresi', 'type' => 'secret', 'required' => true],
                ['key' => 'auth.secret', 'label' => 'Mağaza anahtarı (storeKey/hash)', 'type' => 'secret', 'required' => false],
                ['key' => 'callback.secret', 'label' => 'Callback imza sırrı', 'type' => 'secret', 'required' => false],
            ],
        ],
    ],

    /*
     * PRESET'LER — TR YN-POS/ÖKC cihazları + banka sanal POS + ödeme kuruluşları.
     * `generic_rest` bunları temel alır; işletme YALNIZ base_url + kimlik girer.
     *
     * ÖNEMLİ: endpoints/map değerleri her sağlayıcının RESMİ DOKÜMANINDAN
     * (preset_catalog.doc_url) doğrulanması gereken ŞABLONLARDIR ('verified' => false).
     * Mimari güvenlidir: kesin olmayan/yapılandırılmamış sonuç ASLA "onaylandı"
     * sayılmaz (GenericRestPosProvider), bu yüzden yanlış eşleme para kaybettirmez —
     * yalnız işlemi pending/hata bırakır. Değerler doğrulanınca 'verified' => true yapın.
     *
     * Çoğu Türk bankası ORTAK ağ geçidi kullanır (NestPay/EST → Akbank, İşbank, Ziraat,
     * Halkbank, TEB, QNB, Anadolubank…). Ortak aile tek preset'tir (est_nestpay); banka
     * yalnız base_url + kimlik ile ayrışır.
     */
    'presets' => [
        /* ---------- Yeni Nesil ÖKC / YN-POS cihazları (TSM · GMP-3) ---------- */
        'token_gmp3' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Signature', 'key_header' => 'X-Key-Id'],
            'endpoints' => ['initiate' => '/sale/init', 'charge' => '/sale', 'query' => '/sale/query', 'cancel' => '/sale/void', 'refund' => '/sale/refund', 'status' => '/terminal/status'],
            'map' => ['status_field' => 'result', 'txn_id_field' => 'transactionId', 'auth_code_field' => 'authCode', 'approved' => ['00', 'approved', 'success'], 'declined' => ['declined', 'error'], 'pending' => ['pending', 'processing']],
            'callback' => ['sig_header' => 'X-Pos-Signature', 'ts_header' => 'X-Pos-Timestamp'],
        ],
        'ingenico_tsm' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Signature'],
            'endpoints' => ['charge' => '/payment', 'query' => '/payment/query', 'cancel' => '/payment/void', 'refund' => '/payment/refund', 'status' => '/status'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'txnId', 'auth_code_field' => 'authCode'],
        ],
        'verifone_tsm' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'bearer'],
            'endpoints' => ['charge' => '/transactions/sale', 'query' => '/transactions/status', 'cancel' => '/transactions/void', 'refund' => '/transactions/refund'],
            'map' => ['status_field' => 'state', 'txn_id_field' => 'id', 'approved' => ['approved', 'captured'], 'pending' => ['pending', 'in_progress']],
        ],
        'hugin_beko' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Hugin-Sign'],
            'endpoints' => ['charge' => '/ecr/sale', 'query' => '/ecr/query', 'cancel' => '/ecr/void', 'refund' => '/ecr/refund', 'status' => '/ecr/status'],
            'map' => ['status_field' => 'resultCode', 'txn_id_field' => 'fiscalId', 'approved' => ['0', '00', 'ok']],
        ],
        'profilo' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac'],
            'endpoints' => ['charge' => '/sale', 'query' => '/query', 'cancel' => '/void', 'refund' => '/refund', 'status' => '/status'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'ficheNo', 'approved' => ['00', 'approved']],
        ],
        'pax' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'bearer'],
            'endpoints' => ['charge' => '/api/v1/sale', 'query' => '/api/v1/query', 'cancel' => '/api/v1/void', 'refund' => '/api/v1/refund', 'status' => '/api/v1/status'],
            'map' => ['status_field' => 'responseCode', 'txn_id_field' => 'transactionId', 'approved' => ['00', 'approved']],
        ],
        'pavo' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'bearer'],
            'endpoints' => ['charge' => '/api/payment/sale', 'query' => '/api/payment/status', 'cancel' => '/api/payment/void', 'refund' => '/api/payment/refund', 'status' => '/api/device/status'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'paymentId', 'auth_code_field' => 'authCode', 'approved' => ['success', 'approved', '00'], 'pending' => ['pending', 'waiting']],
            'callback' => ['sig_header' => 'X-Pavo-Signature', 'ts_header' => 'X-Pavo-Timestamp'],
        ],
        'kodpos' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Signature'],
            'endpoints' => ['charge' => '/sale', 'query' => '/query', 'cancel' => '/void', 'refund' => '/refund', 'status' => '/status'],
            'map' => ['status_field' => 'resultCode', 'txn_id_field' => 'transactionId', 'approved' => ['0', '00']],
        ],
        'faprika' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'bearer'],
            'endpoints' => ['charge' => '/api/sale', 'query' => '/api/status', 'refund' => '/api/refund'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'id', 'approved' => ['approved', 'success']],
        ],

        /* ---------- Banka Sanal POS ---------- */
        // NestPay/EST ortak ailesi (Akbank, İşbank, Ziraat, Halkbank, TEB, QNB, Anadolubank…)
        // XML/CC5Request — kimlikler gövdede (Name/Password/ClientId). doc'tan doğrula.
        'est_nestpay' => [
            'provider' => 'generic_soap',
            'auth' => ['type' => 'none'],
            'endpoints' => ['charge' => '/fim/api', 'query' => '/fim/api', 'cancel' => '/fim/api', 'refund' => '/fim/api'],
            'xml' => [
                'root' => 'CC5Request', 'form_field' => null,
                'requests' => [
                    'charge' => ['Name' => '{api_user}', 'Password' => '{api_password}', 'ClientId' => '{merchant_id}', 'Type' => 'Auth', 'Currency' => '949', 'Total' => '{amount}', 'OrderId' => '{reference}'],
                    'query' => ['Name' => '{api_user}', 'Password' => '{api_password}', 'ClientId' => '{merchant_id}', 'OrderId' => '{reference}', 'Extra' => ['ORDERSTATUS' => 'QUERY']],
                    'cancel' => ['Name' => '{api_user}', 'Password' => '{api_password}', 'ClientId' => '{merchant_id}', 'Type' => 'Void', 'OrderId' => '{reference}'],
                    'refund' => ['Name' => '{api_user}', 'Password' => '{api_password}', 'ClientId' => '{merchant_id}', 'Type' => 'Credit', 'Currency' => '949', 'Total' => '{refund_amount}', 'OrderId' => '{reference}'],
                ],
            ],
            'map' => ['status_field' => 'Response', 'txn_id_field' => 'TransId', 'auth_code_field' => 'AuthCode', 'message_field' => 'ErrMsg', 'approved' => ['Approved'], 'declined' => ['Declined', 'Error']],
        ],
        'garanti_gvp' => [
            'provider' => 'generic_soap',
            'auth' => ['type' => 'none'],
            'endpoints' => ['charge' => '/VPServlet', 'query' => '/VPServlet', 'cancel' => '/VPServlet', 'refund' => '/VPServlet'],
            'xml' => [
                'root' => 'GVPSRequest', 'form_field' => 'data',
                'requests' => [
                    'charge' => ['Mode' => 'PROD', 'Terminal' => ['MerchantID' => '{merchant_id}', 'ID' => '{terminal_id}'], 'Order' => ['OrderID' => '{reference}'], 'Transaction' => ['Type' => 'sales', 'Amount' => '{amount_minor}', 'CurrencyCode' => '949']],
                    'query' => ['Mode' => 'PROD', 'Terminal' => ['MerchantID' => '{merchant_id}', 'ID' => '{terminal_id}'], 'Order' => ['OrderID' => '{reference}'], 'Transaction' => ['Type' => 'orderinq']],
                    'cancel' => ['Mode' => 'PROD', 'Terminal' => ['MerchantID' => '{merchant_id}', 'ID' => '{terminal_id}'], 'Order' => ['OrderID' => '{reference}'], 'Transaction' => ['Type' => 'void']],
                    'refund' => ['Mode' => 'PROD', 'Terminal' => ['MerchantID' => '{merchant_id}', 'ID' => '{terminal_id}'], 'Order' => ['OrderID' => '{reference}'], 'Transaction' => ['Type' => 'refund', 'Amount' => '{refund_amount_minor}', 'CurrencyCode' => '949']],
                ],
            ],
            'map' => ['status_field' => 'Transaction/Response/Message', 'txn_id_field' => 'Transaction/RetrefNum', 'auth_code_field' => 'Transaction/AuthCode', 'message_field' => 'Transaction/Response/ErrorMsg', 'approved' => ['Approved'], 'declined' => ['Declined', 'Error']],
        ],
        'yapikredi_posnet' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Signature'],
            'endpoints' => ['charge' => '/PosnetWebService/XML', 'query' => '/PosnetWebService/XML', 'refund' => '/PosnetWebService/XML'],
            'map' => ['status_field' => 'approved', 'txn_id_field' => 'hostlogkey', 'auth_code_field' => 'authCode', 'approved' => ['1', 'approved']],
        ],
        'vakifbank_vpos' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac'],
            'endpoints' => ['charge' => '/VposService/v3/Vposreq.aspx', 'query' => '/VposService/v3/Vposreq.aspx', 'refund' => '/VposService/v3/Vposreq.aspx'],
            'map' => ['status_field' => 'ResultCode', 'txn_id_field' => 'TransactionId', 'auth_code_field' => 'AuthCode', 'approved' => ['0000', '0']],
        ],
        'denizbank_inest' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Signature'],
            'endpoints' => ['charge' => '/mpi/Default.aspx', 'query' => '/mpi/Default.aspx', 'refund' => '/mpi/Default.aspx'],
            'map' => ['status_field' => 'Response', 'txn_id_field' => 'TransId', 'approved' => ['Approved']],
        ],
        'kuveyt_turk' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'basic'],
            'endpoints' => ['charge' => '/Non3DPayGate', 'query' => '/GetMerchantOrderDetail', 'refund' => '/PartialDrawback'],
            'map' => ['status_field' => 'ResponseCode', 'txn_id_field' => 'RRN', 'auth_code_field' => 'ProvisionNumber', 'approved' => ['00', '0']],
        ],

        /* ---------- Ödeme Kuruluşları / Aggregator (PSP) ---------- */
        'iyzico' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'Authorization', 'key_header' => 'x-iyzi-rnd'],
            'endpoints' => ['charge' => '/payment/auth', 'query' => '/payment/detail', 'cancel' => '/payment/cancel', 'refund' => '/payment/refund'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'paymentId', 'auth_code_field' => 'authCode', 'approved' => ['success'], 'declined' => ['failure']],
        ],
        'paytr' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-PAYTR-Token'],
            'endpoints' => ['charge' => '/odeme', 'query' => '/odeme/durum', 'refund' => '/odeme/iade'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'merchant_oid', 'approved' => ['success', '1'], 'declined' => ['failed', '0']],
            'callback' => ['sig_header' => 'X-PAYTR-Hash', 'ts_header' => 'X-PAYTR-Timestamp'],
        ],
        'param' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac'],
            'endpoints' => ['charge' => '/turkpos.ws/service_turkpos_prod.asmx', 'query' => '/turkpos.ws/service_turkpos_prod.asmx', 'refund' => '/turkpos.ws/service_turkpos_prod.asmx'],
            'map' => ['status_field' => 'Sonuc', 'txn_id_field' => 'Islem_ID', 'approved' => ['1']],
        ],
        'sipay' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'bearer'],
            'endpoints' => ['charge' => '/api/paySmart2D', 'query' => '/api/checkstatus', 'refund' => '/api/refund'],
            'map' => ['status_field' => 'status_code', 'txn_id_field' => 'invoice_id', 'auth_code_field' => 'auth_code', 'approved' => ['100', '1'], 'pending' => ['pending']],
        ],
        'moka' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac'],
            'endpoints' => ['charge' => '/PaymentDealer/DoDirectPayment', 'query' => '/PaymentDealer/GetDealerPaymentTrxDetailList', 'refund' => '/PaymentDealer/DoCreateRefundRequest'],
            'map' => ['status_field' => 'ResultCode', 'txn_id_field' => 'VirtualPosOrderId', 'approved' => ['Success', '000'], 'declined' => ['Failed']],
        ],
        'craftgate' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'x-signature', 'key_header' => 'x-api-key'],
            'endpoints' => ['charge' => '/payment/v1/card-payments', 'query' => '/payment/v1/payments', 'cancel' => '/payment/v1/cancels', 'refund' => '/payment/v1/refunds'],
            'map' => ['status_field' => 'paymentStatus', 'txn_id_field' => 'id', 'auth_code_field' => 'authCode', 'approved' => ['SUCCESS'], 'declined' => ['FAILURE'], 'pending' => ['WAITING']],
        ],
        'hepsipay' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'bearer'],
            'endpoints' => ['charge' => '/payment/api/order/create', 'query' => '/payment/api/order/detail', 'refund' => '/payment/api/order/refund'],
            'map' => ['status_field' => 'status', 'txn_id_field' => 'orderId', 'approved' => ['SUCCESS', 'APPROVED'], 'pending' => ['PENDING']],
        ],

        // Genel şablon: yukarıdakilerden hiçbiri değilse (bilinmeyen REST POS/banka).
        'bank_vpos' => [
            'provider' => 'generic_rest',
            'auth' => ['type' => 'hmac', 'header' => 'X-Signature'],
            'endpoints' => ['charge' => '/vpos/pay', 'query' => '/vpos/inquiry', 'cancel' => '/vpos/cancel', 'refund' => '/vpos/refund'],
            'map' => ['status_field' => 'Response', 'txn_id_field' => 'TransId', 'auth_code_field' => 'AuthCode', 'approved' => ['Approved', 'Success', '00'], 'declined' => ['Declined', 'Error']],
        ],
    ],

    /*
     * PRESET KATALOĞU (UI meta) — kurulum ekranı bunu listeler. `verified=false`:
     * endpoint/eşleme doc_url'den DOĞRULANMALI (şablon). Doğrulanınca true yapın.
     * Bu meta sağlayıcıya GÖNDERİLMEZ; yalnız arayüz için.
     */
    'preset_catalog' => [
        // YN-POS / ÖKC cihazlar (TSM · GMP-3)
        'token_gmp3' => ['label' => 'Token Financial (GMP-3)', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.tokenfinans.com.tr'],
        'ingenico_tsm' => ['label' => 'Ingenico YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.ingenico.com.tr'],
        'verifone_tsm' => ['label' => 'Verifone YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.verifone.com/tr'],
        'hugin_beko' => ['label' => 'Hugin / Beko YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.hugin.com.tr'],
        'profilo' => ['label' => 'Profilo YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.profilo.com'],
        'pax' => ['label' => 'PAX YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.paxtechnology.com'],
        'pavo' => ['label' => 'Pavo YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://developerdocs.pavo.com.tr'],
        'kodpos' => ['label' => 'KodPos YN-POS', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://www.kodpos.com'],
        'faprika' => ['label' => 'Faprika', 'category' => 'okc', 'verified' => false, 'doc_url' => 'https://faprika.com'],
        // Banka Sanal POS
        'est_nestpay' => ['label' => 'NestPay/EST (Akbank·İşbank·Ziraat·Halkbank·TEB·QNB…)', 'category' => 'bank', 'verified' => false, 'doc_url' => 'https://www.asseco-see.com.tr'],
        'garanti_gvp' => ['label' => 'Garanti BBVA (GVP)', 'category' => 'bank', 'verified' => false, 'doc_url' => 'https://dev.garantibbva.com.tr'],
        'yapikredi_posnet' => ['label' => 'Yapı Kredi (POSNet)', 'category' => 'bank', 'verified' => false, 'doc_url' => 'https://sanalpos.yapikredi.com.tr'],
        'vakifbank_vpos' => ['label' => 'VakıfBank Sanal POS', 'category' => 'bank', 'verified' => false, 'doc_url' => 'https://sanalpos.vakifbank.com.tr'],
        'denizbank_inest' => ['label' => 'DenizBank (InterVPOS)', 'category' => 'bank', 'verified' => false, 'doc_url' => 'https://sanalpos.denizbank.com'],
        'kuveyt_turk' => ['label' => 'Kuveyt Türk Sanal POS', 'category' => 'bank', 'verified' => false, 'doc_url' => 'https://sanalpos.kuveytturk.com.tr'],
        // Ödeme Kuruluşları (PSP)
        'iyzico' => ['label' => 'iyzico', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://docs.iyzico.com'],
        'paytr' => ['label' => 'PayTR', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://dev.paytr.com'],
        'param' => ['label' => 'Param (TurkPos)', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://dev.param.com.tr/tr/api'],
        'sipay' => ['label' => 'Sipay', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://apidocs.sipay.com.tr'],
        'moka' => ['label' => 'Moka United', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://developer.mokaunited.com'],
        'craftgate' => ['label' => 'Craftgate', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://developer.craftgate.io'],
        'hepsipay' => ['label' => 'Hepsipay', 'category' => 'psp', 'verified' => false, 'doc_url' => 'https://developer.hepsipay.com'],
        // Genel
        'bank_vpos' => ['label' => 'Diğer / Genel REST POS', 'category' => 'other', 'verified' => false, 'doc_url' => ''],
    ],

    // Nakit yuvarlama adımı (kuruş): kalan tutar bu adıma yuvarlanabilir.
    'cash_rounding_step_minor' => (int) env('PAYMENTS_CASH_ROUNDING_STEP', 25),

    // Adisyon başına izin verilen en büyük mutlak yuvarlama (kuruş).
    'max_rounding_minor' => 99,

    // Callback zaman damgası toleransı (saniye) — replay penceresi.
    'callback_tolerance_seconds' => (int) env('PAYMENTS_CALLBACK_TOLERANCE', 300),

    // Servis bedeli üst sınırı (yüzde).
    'max_service_charge_percent' => 20.0,

    'mock' => [
        // Boşsa app.key'den türetilir (yalnız mock için kabul edilebilir).
        'secret' => env('PAYMENTS_MOCK_SECRET', ''),
        // Terminal simülasyon gecikmesi (ms, 0-2000).
        'delay_ms' => (int) env('PAYMENTS_MOCK_DELAY_MS', 0),
    ],

    'sandbox' => [
        'base_url' => env('PAYMENTS_SANDBOX_BASE_URL', ''),
        'api_key' => env('PAYMENTS_SANDBOX_API_KEY', ''),
        'secret' => env('PAYMENTS_SANDBOX_SECRET', ''),
    ],

];
