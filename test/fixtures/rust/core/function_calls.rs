// Function calls - M2.1 Core Layer

fn helper(x: i32) -> i32 {
    x
}

fn calls() {
    let a = helper(1);
    let b = helper(1 + 2);
    let c = std::cmp::max(1, 2);
    let d = "hello".len();
    let e = vec![1, 2, 3].len();
}
