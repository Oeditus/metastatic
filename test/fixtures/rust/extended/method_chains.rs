// Method chains - M2.2 Extended Layer
//
// Iterator chains are the Rust form of `collection_op`; they are the construct
// that makes Rust <-> Python/JavaScript equivalence meaningful.

fn chains(items: Vec<i32>) -> Vec<i32> {
    items.iter().map(|x| x * 2).collect()
}

fn filtered(items: Vec<i32>) -> Vec<i32> {
    items.into_iter().filter(|x| *x > 0).collect()
}

fn summed(items: Vec<i32>) -> i32 {
    items.iter().fold(0, |acc, x| acc + x)
}
