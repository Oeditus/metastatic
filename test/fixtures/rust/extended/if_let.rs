// While-let and if-let - M2.2 Extended Layer

fn while_let(mut stack: Vec<i32>) -> i32 {
    let mut total = 0;
    while let Some(item) = stack.pop() {
        total = total + item;
    }
    total
}

fn if_let(value: Option<i32>) -> i32 {
    if let Some(x) = value {
        x
    } else {
        0
    }
}
