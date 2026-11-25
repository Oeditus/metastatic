pub fn integers() -> Int {
  42
}

pub fn floats() -> Float {
  3.14
}

pub fn strings() -> String {
  "hello"
}

pub fn booleans() -> Bool {
  True
}

pub fn tuples() -> #(Int, String) {
  #(1, "a")
}

pub fn lists() -> List(Int) {
  [1, 2, 3]
}

pub fn lists_with_tail(xs: List(Int)) -> List(Int) {
  [1, 2, ..xs]
}

pub fn nested() -> List(#(Int, List(String))) {
  [#(1, ["a", "b"])]
}

pub fn escaped() -> String {
  "a \"quoted\" word"
}
