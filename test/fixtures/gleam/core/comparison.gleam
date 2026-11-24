pub fn equal(a: Int, b: Int) -> Bool {
  a == b
}

pub fn not_equal(a: Int, b: Int) -> Bool {
  a != b
}

pub fn less(a: Int, b: Int) -> Bool {
  a < b
}

pub fn less_equal(a: Int, b: Int) -> Bool {
  a <= b
}

pub fn greater(a: Int, b: Int) -> Bool {
  a > b
}

pub fn greater_equal(a: Int, b: Int) -> Bool {
  a >= b
}

pub fn less_float(a: Float, b: Float) -> Bool {
  a <. b
}

pub fn greater_float(a: Float, b: Float) -> Bool {
  a >. b
}

pub fn both(a: Bool, b: Bool) -> Bool {
  a && b
}

pub fn either(a: Bool, b: Bool) -> Bool {
  a || b
}

pub fn negate(a: Bool) -> Bool {
  !a
}

pub fn concatenate(a: String, b: String) -> String {
  a <> b
}
