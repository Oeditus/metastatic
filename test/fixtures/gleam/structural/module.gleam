//// Module documentation.

import gleam/io
import gleam/list.{map, filter as keep}
import gleam/option.{type Option, None, Some}
import gleam/result as res

pub const answer: Int = 42
const private_constant = "hidden"

pub fn main() -> Nil {
  io.println("hello")
}

fn helper(x: Int) -> Int {
  x + 1
}

pub fn uses_helper(x: Int) -> Int {
  helper(x)
}
