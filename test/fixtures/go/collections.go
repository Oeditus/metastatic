package fixtures

import "sort"

type Entry struct {
	Name  string `json:"name"`
	Score int    `json:"score"`
}

type Entries []Entry
type Alias = Entry

func Top(entries []Entry, limit int) []string {
	copyOf := append([]Entry(nil), entries...)
	sort.Slice(copyOf, func(i, j int) bool {
		return copyOf[i].Score > copyOf[j].Score
	})
	names := make([]string, 0, limit)
	for i, entry := range copyOf {
		if i >= limit {
			break
		}
		names = append(names, entry.Name)
	}
	return names
}

func Counts(entries []Entry) map[string]int {
	result := map[string]int{}
	for _, entry := range entries {
		result[entry.Name]++
	}
	return result
}
