// Loops - M2.2 Extended Layer

fn while_loop(n: i32) -> i32 {
    let mut i = 0;
    while i < n {
        i = i + 1;
    }
    i
}

fn for_loop(items: Vec<i32>) -> i32 {
    let mut total = 0;
    for item in items {
        total = total + item;
    }
    total
}

fn infinite() {
    loop {
        break;
    }
}
