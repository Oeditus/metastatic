//! Byte-offset → line/column conversion.
//!
//! `gleam_core` reports positions as byte offsets into the source
//! (`SrcSpan { start, end }`). MetaAST, like every other adapter, speaks
//! 1-based line/column pairs. This module is the single conversion point, so
//! the mapping is defined once rather than re-derived at each call site.
//!
//! The index is built once per parse: a sorted vector of the byte offsets at
//! which each line starts, searched with a binary search. That keeps a file
//! with `n` nodes at `O(n log lines)` instead of the `O(n · lines)` a naive
//! "count the newlines before this offset" would cost.

use crate::ast::Span;

/// Maps byte offsets in one source string to [`Span`]s.
#[derive(Debug)]
pub struct LineIndex<'a> {
    /// Byte offset of the first character of each line; `starts[0] == 0`.
    starts: Vec<usize>,
    /// The source, kept for end-column computation.
    source: &'a str,
}

impl<'a> LineIndex<'a> {
    /// Builds an index over `source`.
    pub fn new(source: &'a str) -> LineIndex<'a> {
        let mut starts = vec![0usize];
        for (offset, byte) in source.bytes().enumerate() {
            if byte == b'\n' {
                starts.push(offset + 1);
            }
        }
        LineIndex { starts, source }
    }

    /// Converts a `gleam_core` byte span into a 1-based [`Span`].
    ///
    /// Offsets past the end of the source (which `gleam_core` uses for
    /// synthetic nodes) are clamped rather than panicking, and a span that
    /// cannot be resolved becomes [`Span::UNKNOWN`].
    pub fn span(&self, start: u32, end: u32) -> Span {
        let start = start as usize;
        let end = end as usize;

        if start > self.source.len() || end > self.source.len() || start > end {
            return Span::UNKNOWN;
        }

        let (line, col) = self.position(start);
        let (end_line, end_col) = self.position(end);

        Span {
            line,
            col,
            end_line,
            end_col,
        }
    }

    /// Returns the 1-based `(line, column)` of a byte offset.
    ///
    /// Columns count characters, not bytes, so a line containing multi-byte
    /// UTF-8 reports the column a human would point at.
    fn position(&self, offset: usize) -> (usize, usize) {
        // `partition_point` gives the number of line starts <= offset, so the
        // line number is that count (1-based) and the line start is one before.
        let line_index = self.starts.partition_point(|start| *start <= offset);
        let line = line_index.max(1);
        let line_start = self.starts[line - 1];

        let column = self.source[line_start..offset].chars().count() + 1;
        (line, column)
    }

    /// Returns the source text between two byte offsets, or `""` when the
    /// range is not a character boundary.
    pub fn slice(&self, start: u32, end: u32) -> &'a str {
        let start = start as usize;
        let end = end as usize;

        if start > end || end > self.source.len() {
            return "";
        }

        self.source.get(start..end).unwrap_or("")
    }

    /// Returns the 1-based line of a byte offset, for error reporting.
    pub fn line_of(&self, offset: u32) -> usize {
        self.position((offset as usize).min(self.source.len())).0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_line_starts_at_one_one() {
        let source = "pub fn main() {\n  1\n}\n";
        let index = LineIndex::new(source);
        assert_eq!(
            index.span(0, 3),
            Span {
                line: 1,
                col: 1,
                end_line: 1,
                end_col: 4
            }
        );
    }

    #[test]
    fn subsequent_lines_are_counted() {
        let source = "one\ntwo\nthree";
        let index = LineIndex::new(source);
        // `two` starts at byte 4, which is line 2 column 1.
        assert_eq!(index.span(4, 7).line, 2);
        assert_eq!(index.span(4, 7).col, 1);
        assert_eq!(index.span(4, 7).end_col, 4);
        // `three` starts at byte 8.
        assert_eq!(index.span(8, 13).line, 3);
    }

    #[test]
    fn columns_count_characters_not_bytes() {
        // `λ` is two bytes, so the line break sits at byte 5 and `let` starts
        // at byte 6 — not at the character index 5 a naive count would give.
        let source = "// λ\nlet x = 1";
        let index = LineIndex::new(source);
        assert_eq!(index.span(6, 9).line, 2);
        // Columns, unlike offsets, count characters: `let` is three wide.
        assert_eq!(index.span(6, 9).col, 1);
        assert_eq!(index.span(6, 9).end_col, 4);
    }

    #[test]
    fn out_of_range_offsets_degrade_to_unknown() {
        let index = LineIndex::new("abc");
        assert!(index.span(0, 99).is_unknown());
        assert!(index.span(2, 1).is_unknown());
    }

    #[test]
    fn slice_returns_source_text() {
        let index = LineIndex::new("pub fn main() {}");
        assert_eq!(index.slice(7, 11), "main");
        assert_eq!(index.slice(11, 7), "");
    }

    #[test]
    fn line_of_reports_the_containing_line() {
        let index = LineIndex::new("a\nb\nc");
        assert_eq!(index.line_of(0), 1);
        assert_eq!(index.line_of(2), 2);
        assert_eq!(index.line_of(4), 3);
    }
}
