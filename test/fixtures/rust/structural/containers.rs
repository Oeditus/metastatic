// Containers - M2.2s Structural Layer

struct Point {
    x: i32,
    y: i32,
}

struct Unit;

enum Shape {
    Circle,
    Square,
    Triangle,
}

trait Drawable {
    fn draw(&self);
}

impl Drawable for Point {
    fn draw(&self) {}
}

mod inner {
    pub fn helper() -> i32 {
        1
    }
}
