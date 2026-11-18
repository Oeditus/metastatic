// Indexing and field access - M2.1 Core Layer

struct Point {
    x: i32,
}

fn access(items: Vec<i32>, point: Point) -> i32 {
    let first = items[0];
    let field = point.x;
    first + field
}
