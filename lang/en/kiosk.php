<?php

/**
 * Kiosk error/locked pages — see lang/tr/kiosk.php for full context.
 * PARITY: tr/en/de files hold the SAME key set.
 */
return [
    'error_title' => 'Kiosk',
    'locked_title_suffix' => 'Kiosk',

    // error.blade.php — 410 (rotated / deactivated device)
    'error_gone_heading' => 'This kiosk device is no longer valid',
    'error_gone_body' => 'The device address was rotated or the registration was deactivated. Please ask your manager for the new kiosk address.',

    // error.blade.php — 429 (rate limit)
    'error_throttled_heading' => 'Too many requests',
    'error_throttled_body' => 'Please try again in a moment.',

    // error.blade.php — 404 (invalid/unknown token or disabled feature)
    'error_invalid_heading' => 'Kiosk not found',
    'error_invalid_body' => 'This address does not belong to a valid kiosk device.',

    // locked.blade.php — device locked from the panel (self-polling screen)
    'locked_heading' => ':device is temporarily unavailable',
    'locked_body' => 'This kiosk was locked by a manager. Please ask a staff member for help.',
];
