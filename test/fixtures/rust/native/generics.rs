// Generics and lifetimes - M2.3 Native Layer
//
// Generic parameters and lifetime bounds have no cross-language analogue in
// MetaAST, so they are carried in metadata rather than modelled structurally.

fn identity<T>(value: T) -> T {
    value
}

struct Wrapper<T> {
    inner: T,
}

fn first<'a>(items: &'a [i32]) -> &'a i32 {
    &items[0]
}
