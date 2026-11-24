pub fn add(a: Int, b: Int) -> Int {
  a + b
}

pub fn subtract(a: Int, b: Int) -> Int {
  a - b
}

pub fn multiply(a: Int, b: Int) -> Int {
  a * b
}

pub fn divide(a: Int, b: Int) -> Int {
  a / b
}

pub fn remainder(a: Int, b: Int) -> Int {
  a % b
}

pub fn add_float(a: Float, b: Float) -> Float {
  a +. b
}

pub fn subtract_float(a: Float, b: Float) -> Float {
  a -. b
}

pub fn multiply_float(a: Float, b: Float) -> Float {
  a *. b
}

pub fn divide_float(a: Float, b: Float) -> Float {
  a /. b
}

pub fn negate(a: Int) -> Int {
  -a
}

pub fn precedence(a: Int, b: Int, c: Int) -> Int {
  a + b * c
}
