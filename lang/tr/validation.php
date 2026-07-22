<?php

return [
    'accepted' => ':attribute kabul edilmelidir.',
    'boolean' => ':attribute alanı doğru ya da yanlış olmalıdır.',
    'confirmed' => ':attribute tekrarı eşleşmiyor.',
    'current_password' => 'Mevcut parola doğru değil.',
    'email' => ':attribute geçerli bir e-posta adresi olmalıdır.',
    'exists' => 'Seçilen :attribute geçersiz.',
    'in' => 'Seçilen :attribute geçersiz.',
    'integer' => ':attribute bir tam sayı olmalıdır.',
    'max' => [
        'string' => ':attribute en çok :max karakter olabilir.',
        'numeric' => ':attribute en çok :max olabilir.',
    ],
    'min' => [
        'string' => ':attribute en az :min karakter olmalıdır.',
        'numeric' => ':attribute en az :min olmalıdır.',
    ],
    'numeric' => ':attribute bir sayı olmalıdır.',
    'required' => ':attribute alanı zorunludur.',
    'string' => ':attribute metin olmalıdır.',

    'password' => [
        'letters' => ':attribute en az bir harf içermelidir.',
        'mixed' => ':attribute en az bir büyük ve bir küçük harf içermelidir.',
        'numbers' => ':attribute en az bir rakam içermelidir.',
        'symbols' => ':attribute en az bir özel karakter içermelidir.',
        'uncompromised' => 'Bu :attribute bir veri sızıntısında görülmüş. Lütfen farklı bir parola seçin.',
    ],

    'attributes' => [
        'email' => 'e-posta adresi',
        'password' => 'parola',
        'current_password' => 'mevcut parola',
        'password_confirmation' => 'parola tekrarı',
        'pin' => 'PIN',
        'code' => 'doğrulama kodu',
        'token' => 'sıfırlama anahtarı',
        'tenant' => 'işletme kodu',
        'staff_code' => 'personel kodu',
        'branch_id' => 'şube',
        'theme' => 'tema',
        'locale' => 'dil',
        'remember' => 'beni hatırla',
    ],
];
