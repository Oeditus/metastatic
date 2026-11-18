// Early return - M2.1 Core Layer

fn guard(x: i32) -> i32 {
    if x < 0 {
        return 0;
    }
    x
}

fn bare_return() {
    return;
}
