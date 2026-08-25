<?php

namespace App\Modules\Orders\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * Hazır indirim tanımı (ör. "Şehit/Gazi yakını %20", "Kamu personeli %10").
 *
 * Değer TÜRE göre ayrı sütunda tutulur: yüzde indirim `value_percent`,
 * sabit tutar indirim `value_minor` (kuruş). Tek sütunda "değer" tutup
 * anlamını türe bırakmak, kuruş/yüzde karışmasına açık kapı bırakırdı.
 */
class DiscountPreset extends Model
{
    use BelongsToTenant;

    protected $fillable = ['name', 'type', 'value_percent', 'value_minor', 'note', 'requires_approval', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return [
            'value_percent' => 'float',
            'value_minor' => 'integer',
            'requires_approval' => 'boolean',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function isPercent(): bool
    {
        return $this->type === 'percent';
    }

    /** İndirim ucuna gönderilecek değer (yüzde ya da kuruş). */
    public function value(): float|int
    {
        return $this->isPercent() ? (float) $this->value_percent : (int) $this->value_minor;
    }

    /** Kullanıcıya gösterilen kısa etiket ("%20" / "25,00 ₺"). */
    public function valueLabel(): string
    {
        if ($this->isPercent()) {
            $p = (float) $this->value_percent;

            return '%'.(floor($p) === $p ? (string) (int) $p : number_format($p, 2, ',', '.'));
        }

        return number_format(((int) $this->value_minor) / 100, 2, ',', '.').' ₺';
    }
}
