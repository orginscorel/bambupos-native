{{-- Yapışkan kategori şeridi: yatay kaydırma, tek elle erişim. $categories: [['id','name'], ...] --}}
<nav class="m-catstrip" aria-label="Menü kategorileri" data-catstrip>
    <ul class="m-catstrip__list">
        @foreach ($categories as $category)
            <li>
                <a class="m-catstrip__chip" href="#kategori-{{ $category['id'] }}" data-cat-link="{{ $category['id'] }}">
                    {{ $category['name'] }}
                </a>
            </li>
        @endforeach
    </ul>
</nav>
