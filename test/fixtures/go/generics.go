package fixtures

type Number interface {
	~int | ~int64 | ~float64
}

type Box[T any] struct {
	Value T
}

func (b *Box[T]) Get() T {
	return b.Value
}

func Sum[T Number](values ...T) (total T) {
	for _, value := range values {
		total += value
	}
	return
}

func Map[T, U any](values []T, f func(T) U) []U {
	result := make([]U, len(values))
	for index, value := range values {
		result[index] = f(value)
	}
	return result
}

func GenericExample() int {
	b := Box[int]{Value: 42}
	doubled := Map[int, int]([]int{b.Get()}, func(x int) int { return x * 2 })
	return Sum(doubled...)
}
