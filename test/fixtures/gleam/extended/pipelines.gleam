pub fn two_stages(xs: List(Int)) -> List(Int) {
  xs
  |> map(fn(x) { x * 2 })
}

pub fn three_stages(xs: List(Int)) -> List(Int) {
  xs
  |> map(fn(x) { x * 2 })
  |> filter(fn(x) { x > 0 })
  |> reverse()
}

pub fn single(xs: List(Int)) -> List(Int) {
  xs |> reverse()
}
