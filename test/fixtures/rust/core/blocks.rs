// Nested blocks and scoping - M2.1 Core Layer

fn nested() -> i32 {
    let x = 1;
    {
        let y = 2;
        x + y
    }
}
