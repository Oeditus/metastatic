// Nested modules - M2.2s Structural Layer

mod outer {
    pub fn a() -> i32 {
        1
    }

    mod inner {
        pub fn b() -> i32 {
            2
        }
    }
}
