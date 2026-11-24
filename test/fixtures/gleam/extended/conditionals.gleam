pub fn simple(x: Int) -> Int {
  case x {
    0 -> 1
    _ -> 2
  }
}

pub fn with_guard(x: Int) -> Int {
  case x {
    n if n > 0 -> n
    _ -> 0
  }
}

pub fn multi_subject(a: Int, b: Int) -> Int {
  case a, b {
    0, 0 -> 0
    _, 0 -> a
    0, _ -> b
    _, _ -> a + b
  }
}

pub fn nested(x: Int) -> Int {
  case x {
    0 ->
      case x {
        _ -> 0
      }

    _ -> 1
  }
}

pub fn list_pattern(xs: List(Int)) -> Int {
  case xs {
    [] -> 0
    [first, ..] -> first
  }
}

pub fn tuple_pattern(pair: #(Int, Int)) -> Int {
  case pair {
    #(a, b) -> a + b
  }
}
