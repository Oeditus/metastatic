// Attribute access - M2.2s Structural Layer

struct Point {
    x: i32,
    y: i32,
}

fn access(point: Point) -> i32 {
    let a = point.x;
    let b = point.y;
    a + b
}
