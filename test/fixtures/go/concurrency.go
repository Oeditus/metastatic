package fixtures

import (
	"context"
	"fmt"
)

func Worker(ctx context.Context, input <-chan int, output chan<- int) {
	defer close(output)
	for {
		select {
		case <-ctx.Done():
			return
		case value, ok := <-input:
			if !ok {
				return
			}
			select {
			case output <- value * 2:
			case <-ctx.Done():
				return
			}
		}
	}
}

func Launch(ctx context.Context, input <-chan int) <-chan int {
	output := make(chan int)
	go Worker(ctx, input, output)
	return output
}

func Describe(value any) string {
	switch v := value.(type) {
	case int, int64:
		return fmt.Sprint(v)
	case string:
		return v
	default:
		return "unknown"
	}
}
