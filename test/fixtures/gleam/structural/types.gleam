pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
  Point
}

pub type Alias = List(Int)

pub type Pair(a) {
  Pair(first: a, second: a)
}

opaque type Secret {
  Secret(Int)
}

pub type Nested {
  Nested(inner: List(#(Int, String)))
}

pub type Documented {
  /// A documented constructor.
  Documented(Int)
}
