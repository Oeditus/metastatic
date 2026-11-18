// Trait implementations - M2.2s Structural Layer

trait Summary {
    fn summarize(&self) -> String;
}

struct Article {
    title: String,
}

impl Summary for Article {
    fn summarize(&self) -> String {
        self.title.clone()
    }
}
