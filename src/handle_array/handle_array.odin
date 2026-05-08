package handle_array

import "core:mem"
import "core:slice"
import "core:fmt"

import "base:intrinsics"

import "base:runtime"

Handle :: struct {
    slotIndex: i32,
    gen: i32,
}

Slot :: struct {
    elemIndex: i32,
    gen: i32,
}

HandleArray :: struct($T:typeid, $H:typeid, $N: int) {
    slots:    [N]Slot,
    elements: [dynamic; N]T,
}

Init :: proc(arr: ^HandleArray($T, $H, $N)) {
    append(&arr.elements, T{})
}

CreateHandle :: proc(arr: ^HandleArray($T, $H, $N)) -> H {
    for &s, i in arr.slots {
        // slot at index 0 is reserved as "invalid resorce" 
        // so never allocate at it

        if s.elemIndex == 0 && i != 0 {
            append(&arr.elements, T{})

            s.elemIndex = i32(len(arr.elements) - 1)
            s.gen += 1

            return H {
                slotIndex = i32(i),
                gen = s.gen,
            }
        }
    }

    return {}
}

@(require_results)
CreateElement :: proc(arr: ^HandleArray($T, $H, $N)) -> (^T, H) {
    handle := CreateHandle(arr)
    assert(handle.slotIndex != 0)

    slot := arr.slots[handle.slotIndex]
    elem := &arr.elements[slot.elemIndex]
    elem.handle = handle

    return elem, handle
}

AppendElement :: proc(arr: ^HandleArray($T, $H, $N), element: T) -> H {
    handle := CreateHandle(arr)
    if handle != {} {
        slot := arr.slots[handle.slotIndex]

        arr.elements[slot.elemIndex] = element
        arr.elements[slot.elemIndex].handle = handle
    }

    return handle
}

IsHandleValid :: proc(arr: HandleArray($T, $H, $N), handle: H) -> bool {
    assert(int(handle.slotIndex) < len(arr.slots))

    if handle == {} do return false

    slot := arr.slots[handle.slotIndex]
    return slot.elemIndex != 0 && slot.gen == handle.gen
}

GetElementPtr :: proc(arr: HandleArray($T, $H, $N), handle: H) -> (element: ^T, ok: bool) {
    arr := arr

    if IsHandleValid(arr, handle) == false {
        return nil, false
    }

    slot := arr.slots[handle.slotIndex]
    return &arr.elements[slot.elemIndex], true
}

GetElement :: proc(arr: HandleArray($T, $H, $N), handle: H) -> T {
    if IsHandleValid(arr, handle) == false {
        return arr.elements[0]
    }

    slot := arr.slots[handle.slotIndex]
    return arr.elements[slot.elemIndex]
}

FreeSlot :: proc {
    FreeSlotAtIndex,
    FreeSlotAtHandle,
}

FreeSlotAtIndex :: proc(arr: ^HandleArray($T, $H, $N), index: i32) {
    assert(index < cast(i32) len(arr.slots))

    lastHandle := arr.elements[len(arr.elements) - 1].handle

    lastElementSlot := &arr.slots[lastHandle.slotIndex]
    elemSlot := &arr.slots[index]

    if lastElementSlot != elemSlot {
        arr.elements[elemSlot.elemIndex] = arr.elements[lastElementSlot.elemIndex]

        lastElementSlot.elemIndex = elemSlot.elemIndex
    }

    elemSlot.elemIndex = 0

    // (^runtime.Raw_Dynamic_Array)(&arr.elements).len -= 1
    unordered_remove(&arr.elements, len(arr.elements) - 1)
}

FreeSlotAtHandle :: proc(arr: ^HandleArray($T, $H, $N), handle: H) {
    FreeSlotAtIndex(arr, handle.slotIndex)
}

Clear :: proc(arr: ^HandleArray($T, $H, $N)) {
    // resize(&arr.slots, 0)
    for &s, i in arr.slots {
        s = {}
    }
    clear(&arr.elements)
}

PoolLen :: proc(arr: HandleArray($T, $H, $N)) -> int {
    return len(arr.elements) - 1
}

Iter :: struct($T: typeid, $H: typeid, $N: int) {
    idx: int,
    dir: int,

    arr: ^HandleArray(T, H, N)
}

MakeIter :: proc(arr: ^HandleArray($T, $H, $N)) -> Iter(T, H, N) {
    return {
        idx = 1,
        dir = 1,

        arr = arr
    }
}

MakeIterReverse :: proc(arr: ^HandleArray($T, $H, $N)) -> Iter(T, H, N) {
    return {
        idx = len(arr.elements) - 1,
        dir = -1,

        arr = arr
    }
}

Iterate :: proc(it: ^Iter($T, $H, $N)) -> (^T, bool) {
    if it.idx <= 0 || it.idx >= len(it.arr.elements) {
        return nil, false
    }

    elem := &it.arr.elements[it.idx]
    it.idx += it.dir

    return elem, true
}