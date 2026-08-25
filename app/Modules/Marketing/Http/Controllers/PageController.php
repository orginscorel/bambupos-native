<?php

namespace App\Modules\Marketing\Http\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * Kurumsal site içerik sayfaları (sektör, çözüm, kurumsal, yasal).
 * Slug → config kaydı → ilgili Blade şablonu. Yalnız tanıtım host'unda servis
 * edilir (MARKETING_HOST); diğer host'larda 404.
 */
class PageController extends Controller
{
    /** Sadece belirlenen tanıtım host'unda içerik sayfaları gösterilir. */
    private function ensureMarketingHost(Request $request): void
    {
        $mk = trim((string) config('marketing.host', ''));
        $host = $request->getHost();
        $ok = $mk !== '' && ($host === $mk || $host === 'www.'.$mk);
        if (! $ok) {
            throw new NotFoundHttpException();
        }
    }

    /**
     * Tek /{slug} giriş noktası: slug hangi içerik grubuna aitse o şablonu render eder.
     * (Aynı URI'li çoklu route Laravel'de birbirini ezdiği için tek handler kullanılır.)
     */
    public function dispatch(Request $request, string $slug)
    {
        $this->ensureMarketingHost($request);

        if (is_array($p = config("corporate.$slug"))) {
            return view('marketing.corporate', ['page' => $p, 'slug' => $slug]);
        }
        if (is_array($p = config("sectors.$slug"))) {
            return view('marketing.sector', ['page' => $p, 'slug' => $slug]);
        }
        if (is_array($p = config("solutions.$slug"))) {
            $p = array_merge($p, config("solution_extras.$slug", []));
            return view('marketing.solution', ['page' => $p, 'slug' => $slug]);
        }

        throw new NotFoundHttpException();
    }

    public function sector(Request $request, string $slug)
    {
        $this->ensureMarketingHost($request);

        $page = config("sectors.$slug");
        if (! is_array($page)) {
            throw new NotFoundHttpException();
        }

        return view('marketing.sector', ['page' => $page, 'slug' => $slug]);
    }

    public function solution(Request $request, string $slug)
    {
        $this->ensureMarketingHost($request);

        $page = config("solutions.$slug");
        if (! is_array($page)) {
            throw new NotFoundHttpException();
        }
        $page = array_merge($page, config("solution_extras.$slug", []));

        return view('marketing.solution', ['page' => $page, 'slug' => $slug]);
    }

    /** Fiyatlandırma sayfası (/fiyatlandirma) — içerik config/pricing.php. */
    public function pricing(Request $request)
    {
        $this->ensureMarketingHost($request);

        return view('marketing.pricing');
    }

    /** Kurumsal / yasal / bilgi sayfaları — içerik config/corporate.php. */
    public function corporate(Request $request, string $slug)
    {
        $this->ensureMarketingHost($request);

        $page = config("corporate.$slug");
        if (! is_array($page)) {
            throw new NotFoundHttpException();
        }

        return view('marketing.corporate', ['page' => $page, 'slug' => $slug]);
    }
}
