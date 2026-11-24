pub fn no_arguments() -> Int {
  answer()
}

pub fn one_argument(x: Int) -> Int {
  identity(x)
}

pub fn several_arguments(a: Int, b: Int, c: Int) -> Int {
  sum3(a, b, c)
}

pub fn nested_calls(x: Int) -> Int {
  identity(identity(x))
}

pub fn labelled_arguments() -> Int {
  labelled(label: 1, other: "x")
}

pub fn qualified_call() -> Nil {
  io.println("hi")
}

pub fn tuple_index(pair: #(Int, String)) -> Int {
  pair.0
}

pub fn field_access(record: Person) -> String {
  record.name
}
