<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Tasarım sistemi sayfası (/tasarim, /tasarim/menu)
    |--------------------------------------------------------------------------
    | Geliştirme referansıdır; canlı kiracı trafiğine açılmadan önce
    | .env'de DESIGN_PAGE_ENABLED=false yapılmalıdır.
    */

    'page_enabled' => (bool) env('DESIGN_PAGE_ENABLED', false),

];
