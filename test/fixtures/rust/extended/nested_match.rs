// Nested pattern matching - M2.2 Extended Layer

enum Shape {
    Circle(i32),
    Square(i32),
}

fn area(shape: Shape) -> i32 {
    match shape {
        Shape::Circle(r) => r * r,
        Shape::Square(s) => s * s,
    }
}

fn nested(pair: ((i32, i32), bool)) -> i32 {
    match pair {
        ((a, b), true) => a + b,
        ((a, _), false) => a,
    }
}
