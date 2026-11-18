// Pattern matching - M2.2 Extended Layer

fn classify(x: i32) -> i32 {
    match x {
        0 => 1,
        1 => 2,
        _ => 3,
    }
}

fn destructure(pair: (i32, i32)) -> i32 {
    match pair {
        (0, y) => y,
        (x, 0) => x,
        (x, y) => x + y,
    }
}
