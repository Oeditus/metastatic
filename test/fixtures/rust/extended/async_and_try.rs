// Error propagation and async - M2.2 Extended Layer

fn read_value() -> Result<i32, String> {
    let text = load()?;
    Ok(text)
}

fn load() -> Result<i32, String> {
    Ok(1)
}

async fn fetch() -> i32 {
    let value = compute().await;
    value
}

async fn compute() -> i32 {
    1
}
