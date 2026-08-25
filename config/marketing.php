<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Tanıtım (landing) host'u
    |--------------------------------------------------------------------------
    | Kurumsal tanıtım/landing ana sayfasının gösterileceği apex host.
    | Boş ise HİÇBİR host'ta landing gösterilmez; kök doğrudan /giris'e yönlenir
    | (uygulama davranışı — bogahostdeveloper.com.tr kurulumu böyle çalışır).
    | bambumpos.com kurulumunda .env: MARKETING_HOST=bambumpos.com
    */
    'host' => env('MARKETING_HOST', ''),
];
