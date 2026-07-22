<?php

namespace Tests;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use RuntimeException;

abstract class TestCase extends BaseTestCase
{
    /**
     * GÜVENLİK KİLİDİ: RefreshDatabase asla canlı MySQL'e dokunamaz.
     * bootstrap/cache/config.php (config:cache) phpunit.xml env'ini ezerse
     * testler prod bağlantısıyla açılır — bu durumda migrate çalışmadan
     * burada durdururuz. Çözüm: önce `php artisan config:clear`.
     */
    protected function setUpTraits()
    {
        $usesRefresh = isset(class_uses_recursive(static::class)[RefreshDatabase::class]);

        if ($usesRefresh && $this->app['db']->connection()->getDriverName() !== 'sqlite') {
            throw new RuntimeException(
                'Testler yalnız sqlite üzerinde koşar; config cache aktif görünüyor. Önce: php artisan config:clear'
            );
        }

        return parent::setUpTraits();
    }
}
