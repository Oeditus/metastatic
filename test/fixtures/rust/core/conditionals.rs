// Conditionals - M2.1 Core Layer

fn positive(x: i32) -> bool {
    if x > 0 {
        true
    } else {
        false
    }
}

fn classify(x: i32) -> i32 {
    if x > 0 {
        1
    } else if x < 0 {
        -1
    } else {
        0
    }
}
