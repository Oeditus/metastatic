/// Adds two integers.
pub fn add(a: Int, b: Int) -> Int {
  a + b
}

@deprecated("use add instead")
pub fn plus(a: Int, b: Int) -> Int {
  a + b
}

pub fn generic(value: a) -> a {
  value
}

pub fn higher_order(f: fn(Int) -> Int, x: Int) -> Int {
  f(x)
}

@external(erlang, "lists", "reverse")
pub fn reverse_list(xs: List(a)) -> List(a)

@target(javascript)
pub fn js_only() -> Int {
  1
}

pub fn labelled(label a: Int, b other: String) -> Int {
  a
}

fn private_helper() -> Int {
  0
}
