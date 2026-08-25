<?php

/**
 * Kiosk-Fehler-/Sperrbildschirme — vollständiger Kontext in lang/tr/kiosk.php.
 * PARITÄT: tr/en/de-Dateien enthalten DENSELBEN Schlüsselsatz.
 */
return [
    'error_title' => 'Kiosk',
    'locked_title_suffix' => 'Kiosk',

    // error.blade.php — 410 (Adresse rotiert / Gerät deaktiviert)
    'error_gone_heading' => 'Dieses Kiosk-Gerät ist nicht mehr gültig',
    'error_gone_body' => 'Die Geräteadresse wurde erneuert oder die Registrierung deaktiviert. Bitte fragen Sie den Filialleiter nach der neuen Kiosk-Adresse.',

    // error.blade.php — 429 (Rate-Limit)
    'error_throttled_heading' => 'Zu viele Anfragen',
    'error_throttled_body' => 'Bitte versuchen Sie es in Kürze erneut.',

    // error.blade.php — 404 (ungültiges/unbekanntes Token oder Feature deaktiviert)
    'error_invalid_heading' => 'Kiosk nicht gefunden',
    'error_invalid_body' => 'Diese Adresse gehört zu keinem gültigen Kiosk-Gerät.',

    // locked.blade.php — vom Panel gesperrtes Gerät (fragt sich selbst ab)
    'locked_heading' => ':device ist vorübergehend nicht verfügbar',
    'locked_body' => 'Dieser Kiosk wurde von einem Manager gesperrt. Bitte wenden Sie sich an das Personal.',
];
