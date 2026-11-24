pub fn anonymous() -> fn(Int) -> Int {
  fn(x) { x }
}

pub fn two_arguments() -> fn(Int, Int) -> Int {
  fn(a, b) { a + b }
}

pub fn capture() -> fn(Int) -> Int {
  add(1, _)
}

pub fn nested_lambda() -> fn(Int) -> fn(Int) -> Int {
  fn(a) { fn(b) { a + b } }
}

pub fn as_argument(xs: List(Int)) -> List(Int) {
  map(xs, fn(x) { x * 2 })
}

pub fn multi_statement(x: Int) -> fn(Int) -> Int {
  fn(y) {
    let z = x + y
    z * 2
  }
}
