pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
  Point
}

pub fn todo_demo() -> Int {
  todo
}

pub fn todo_with_message() -> Int {
  todo as "not implemented"
}

pub fn panic_demo() -> Int {
  panic
}

pub fn panic_with_message() -> Int {
  panic as "boom"
}

pub fn block() -> Int {
  let x = {
    let y = 1
    y
  }
  x
}

pub fn use_demo() {
  use x <- res.try(Ok(1))
  x
}

pub fn assert_demo(x: Int) -> Int {
  assert x > 0
  assert x < 100 as "too big"
  x
}

pub fn string_prefix(value: String) -> String {
  case value {
    "hi " <> rest -> rest
    _ -> value
  }
}

pub fn record_update(shape: Shape) -> Shape {
  case shape {
    Rectangle(..) as rect -> Rectangle(..rect, width: 10.0)
    other -> other
  }
}

pub fn constructor_pattern(shape: Shape) -> Float {
  case shape {
    Circle(radius) -> radius
    Rectangle(..) -> 0.0
    Point -> 0.0
  }
}
