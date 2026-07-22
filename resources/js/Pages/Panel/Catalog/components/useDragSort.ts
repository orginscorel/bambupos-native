import { ref } from 'vue';

/**
 * HTML5 drag-drop ile liste sıralama (dış kütüphane yok).
 * Kullanım: satıra `draggable` + handler'lar bağlanır; bırakınca
 * `commit(yeniSiraliIdler)` çağrılır (API'ye POST etmek çağıranın işi).
 */
export function useDragSort<T extends { id: number }>(
    getItems: () => T[],
    setItems: (items: T[]) => void,
    commit: (ids: number[]) => void,
) {
    const dragIndex = ref<number | null>(null);
    const overIndex = ref<number | null>(null);

    function onDragStart(index: number, e: DragEvent): void {
        dragIndex.value = index;
        if (e.dataTransfer) {
            e.dataTransfer.effectAllowed = 'move';
            e.dataTransfer.setData('text/plain', String(index)); // Firefox gereği
        }
    }

    function onDragOver(index: number, e: DragEvent): void {
        e.preventDefault();
        if (dragIndex.value === null || index === dragIndex.value) return;
        overIndex.value = index;

        const items = [...getItems()];
        const [moved] = items.splice(dragIndex.value, 1);
        items.splice(index, 0, moved);
        setItems(items);
        dragIndex.value = index;
    }

    function onDrop(e: DragEvent): void {
        e.preventDefault();
        finish();
    }

    function onDragEnd(): void {
        finish();
    }

    function finish(): void {
        if (dragIndex.value !== null) {
            commit(getItems().map((i) => i.id));
        }
        dragIndex.value = null;
        overIndex.value = null;
    }

    return { dragIndex, overIndex, onDragStart, onDragOver, onDrop, onDragEnd };
}
