# Async function
async def fetch_data():
    result = await api_call()
    return result

# Async for
async def process_stream():
    async for item in stream:
        await process(item)

# Async with
async def use_resource():
    async with get_resource() as resource:
        await resource.use()
