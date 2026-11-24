pub fn bytes() -> BitArray {
  <<1, 2, 3>>
}

pub fn sized() -> BitArray {
  <<1:size(8)>>
}

pub fn utf8() -> BitArray {
  <<"hi":utf8>>
}

pub fn pattern(data: BitArray) -> Int {
  case data {
    <<first, rest:bits>> -> first
    <<>> -> 0
  }
}

pub fn empty() -> BitArray {
  <<>>
}
