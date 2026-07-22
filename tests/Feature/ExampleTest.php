<?php

namespace Tests\Feature;

use Tests\TestCase;

class ExampleTest extends TestCase
{
    /** Karşılama sayfası yok: misafir kök adresten giriş ekranına yönlenir. */
    public function test_guest_is_redirected_from_root_to_login(): void
    {
        $this->get('/')->assertRedirect('/giris');
    }

    public function test_login_screen_renders(): void
    {
        $this->get('/giris')->assertOk();
    }

    public function test_pin_login_screen_renders(): void
    {
        $this->get('/giris/pin')->assertOk();
    }

    public function test_password_reset_screens_render(): void
    {
        $this->get('/parola-sifirla')->assertOk();
        $this->get('/reset-password?token=abc&email=a%40b.c')->assertOk();
    }

    public function test_guest_cannot_open_panel(): void
    {
        $this->get('/panel')->assertRedirect('/giris');
    }
}
