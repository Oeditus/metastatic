// Native / escape hatch - M2.3 Native Layer
//
// These constructs have no cross-language analogue and must be preserved as
// `:language_specific` so they round-trip exactly.

fn unsafe_block() {
    unsafe {
        let _ = 1;
    }
}

fn macro_call() {
    println!("hello");
    vec![1, 2, 3];
}
