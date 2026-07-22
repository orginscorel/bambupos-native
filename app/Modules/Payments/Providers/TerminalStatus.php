<?php

namespace App\Modules\Payments\Providers;

/** Terminal erişilebilirlik durumu. */
final class TerminalStatus
{
    public function __construct(
        public readonly bool $online,
        public readonly ?string $terminalId = null,
        public readonly ?string $message = null,
    ) {
    }
}
