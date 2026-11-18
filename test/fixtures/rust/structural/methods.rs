// Methods and impl blocks - M2.2s Structural Layer

struct Counter {
    value: i32,
}

impl Counter {
    fn new(value: i32) -> Counter {
        Counter { value: value }
    }

    fn increment(&mut self) {
        self.value = self.value + 1;
    }

    fn get(&self) -> i32 {
        self.value
    }
}
