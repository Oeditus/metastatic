// Extended Layer: iterator chains, closures, and higher-order operations

fn doubled(items: Vec<i32>) -> Vec<i32> {
    items.iter().map(|x| x * 2).collect()
}

fn positives(items: Vec<i32>) -> Vec<i32> {
    items.into_iter().filter(|x| *x > 0).collect()
}

fn total(items: Vec<i32>) -> i32 {
    items.iter().fold(0, |acc, x| acc + x)
}

fn sorted(items: Vec<i32>) -> Vec<i32> {
    let mut copy = items.clone();
    copy.sort();
    copy
}

fn chained(items: Vec<i32>) -> i32 {
    items
        .iter()
        .map(|x| x + 1)
        .filter(|x| *x > 2)
        .fold(0, |acc, x| acc + x)
}
