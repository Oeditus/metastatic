package fixtures

const (
	First = iota
	Second
	Third
)

var Left, Right int = 1, 2

func Control(n int) int {
	total := 0
	Left, Right = Right, Left
	for i := 0; i < n; i++ {
		if value := i * 2; value > 4 {
			total += value
		} else if value == 4 {
			continue
		} else {
			total -= value
		}
	}
	for total < 10 {
		total++
	}
	switch value := n % 3; value {
	case 0:
		total++
		fallthrough
	case 1, 2:
		total += 2
	default:
		total = -1
	}
	switch {
	case total > 0:
		total--
	}
Loop:
	for {
		select {
		default:
			break Loop
		}
	}
	return total
}
