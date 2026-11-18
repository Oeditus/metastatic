// Extended Layer: references, async, if-let, while-let, unsafe

fn references(items: Vec<i32>) {
    let shared = &items;
    let exclusive = &mut items;
    let value = *shared.first().unwrap();
}

fn async_block() {
    let future = async { 1 };
    let _ = future;
}

fn if_let(items: Vec<i32>) -> i32 {
    if let Some(first) = items.first() {
        *first
    } else {
        0
    }
}

fn while_let(mut items: Vec<i32>) {
    while let Some(top) = items.pop() {
        let _ = top;
    }
}

fn unsafe_block() {
    let raw = 1;
    let value = unsafe { raw };
    let _ = value;
}
