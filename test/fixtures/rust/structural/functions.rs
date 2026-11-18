// Function definitions - M2.2s Structural Layer

fn no_args() {}

fn one_arg(x: i32) -> i32 {
    x
}

fn many_args(a: i32, b: i32, c: i32) -> i32 {
    a + b + c
}

fn returns_unit(x: i32) {
    let _ = x;
}
