<?php

namespace App\Modules\Catalog\Http\Controllers\Panel;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Models\ProductImage;
use App\Modules\Catalog\Services\ProductImageService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Ürün görselleri: güvenli yükleme (§26.3), kapak seçimi, silme. */
class ProductImageController extends Controller
{
    public function __construct(private readonly ProductImageService $images) {}

    public function store(Request $request, Product $product): JsonResponse
    {
        $this->authorize('update', $product);

        $request->validate([
            'image' => ['required', 'file', 'max:4096'], // asıl içerik doğrulaması serviste (finfo + getimagesize)
        ]);

        $image = $this->images->store($product, $request->file('image'));

        return response()->json(['image' => $image], 201);
    }

    public function makePrimary(Request $request, Product $product, ProductImage $image): JsonResponse
    {
        $this->authorize('update', $product);
        abort_unless((int) $image->product_id === (int) $product->id, 404);

        $this->images->makePrimary($image);

        return response()->json(['ok' => true]);
    }

    public function destroy(Request $request, Product $product, ProductImage $image): JsonResponse
    {
        $this->authorize('update', $product);
        abort_unless((int) $image->product_id === (int) $product->id, 404);

        $this->images->delete($image);

        return response()->json(['ok' => true]);
    }
}
