package main

import "sort"

// commentIndex supports boundary queries without scanning the complete tree
// for each comment. Start/end indexes answer neighbor queries in O(log n).
// A max-end interval tree prunes disjoint syntax when finding containers;
// overlapping matches are the typically shallow enclosing syntax chain.
type commentIndex struct {
	starts []commentInterval
	ends   []commentInterval
	maxEnd []uint64
}

type commentInterval struct {
	node       *Node
	start, end uint64
	order      int
}

func commentPosition(line, column int) uint64 { return uint64(line)<<32 | uint64(uint32(column)) }

func newCommentIndex(nodes []*Node) *commentIndex {
	index := &commentIndex{}
	for order, node := range nodes {
		span := node.Span
		index.starts = append(index.starts, commentInterval{
			node: node, start: commentPosition(span.Line, span.Col),
			end: commentPosition(span.EndLine, span.EndCol), order: order,
		})
	}
	sort.Slice(index.starts, func(i, j int) bool {
		a, b := index.starts[i], index.starts[j]
		return a.start < b.start || a.start == b.start && a.order < b.order
	})
	index.ends = append(index.ends, index.starts...)
	sort.Slice(index.ends, func(i, j int) bool {
		a, b := index.ends[i], index.ends[j]
		return a.end < b.end || a.end == b.end && a.order < b.order
	})
	index.maxEnd = make([]uint64, 4*len(nodes))
	if len(nodes) > 0 {
		index.build(0, 0, len(nodes))
	}
	return index
}

func (index *commentIndex) build(branch, left, right int) uint64 {
	if right-left == 1 {
		index.maxEnd[branch] = index.starts[left].end
		return index.maxEnd[branch]
	}
	middle := (left + right) / 2
	a, b := index.build(branch*2+1, left, middle), index.build(branch*2+2, middle, right)
	if b > a {
		a = b
	}
	index.maxEnd[branch] = a
	return a
}

func (index *commentIndex) boundaries(span Span) (containing, following, preceding *Node) {
	size := len(index.starts)
	if size == 0 {
		return nil, nil, nil
	}
	start, end := commentPosition(span.Line, span.Col), commentPosition(span.EndLine, span.EndCol)
	next := sort.Search(size, func(i int) bool { return index.starts[i].start >= end })
	if next < size {
		first := index.starts[next].start
		// Preserve the previous traversal-order tie break for equal starts.
		next = sort.Search(size, func(i int) bool { return index.starts[i].start > first }) - 1
		following = index.starts[next].node
	}
	previous := sort.Search(size, func(i int) bool { return index.ends[i].end > start }) - 1
	if previous >= 0 && index.ends[previous].node.Span.EndLine == span.Line {
		preceding = index.ends[previous].node
	}
	last := sort.Search(size, func(i int) bool { return index.starts[i].start > start })
	best := -1
	index.container(0, 0, size, last, end, &best)
	if best >= 0 {
		containing = index.starts[best].node
	}
	return
}

func (index *commentIndex) container(branch, left, right, last int, end uint64, best *int) {
	if left >= last || index.maxEnd[branch] < end {
		return
	}
	if right-left == 1 {
		current := index.starts[left]
		if *best < 0 {
			*best = left
			return
		}
		previous := index.starts[*best]
		a, b := spanSize(current.node.Span), spanSize(previous.node.Span)
		if a < b || a == b && current.order < previous.order {
			*best = left
		}
		return
	}
	middle := (left + right) / 2
	index.container(branch*2+1, left, middle, last, end, best)
	index.container(branch*2+2, middle, right, last, end, best)
}

func commentCandidates(file *File) []*Node {
	var candidates []*Node
	var visit func(*Node, bool)
	visit = func(n *Node, boundary bool) {
		if boundary && commentBoundary(n.Kind) {
			candidates = append(candidates, n)
		}
		for i := range n.Children {
			allowed := true
			switch n.Kind {
			case "IfStmt":
				allowed = !flag(*n, "has_init") || i != 0
			case "ForStmt":
				allowed = i >= 3
			case "SwitchStmt", "TypeSwitchStmt":
				allowed = i >= 2 || i == 1 && !flag(*n, "has_init")
			case "CommClause":
				allowed = !flag(*n, "has_comm") || i != 0
			}
			visit(&n.Children[i], allowed)
		}
		if n.TypeNode != nil {
			visit(n.TypeNode, true)
		}
		if n.Pattern != nil {
			visit(n.Pattern, true)
		}
	}
	for i := range file.Children {
		visit(&file.Children[i], true)
	}
	return candidates
}
