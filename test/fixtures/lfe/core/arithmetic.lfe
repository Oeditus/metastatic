;; Arithmetic and comparison operators - M2.1 Core Layer
;;
;; Every expression here must abstract to the same MetaAST shape as its
;; Python, Elixir, JavaScript, Rust and Ruby counterparts.

(defun arithmetic ()
  (let ((a (+ 1 2))
        (b (- 10 7))
        (c (* 3 4))
        (d (/ 8 2))
        (e (rem 17 5))
        (f (- 5))
        (g (not 'true))
        (h (* (+ 1 2) 3))
        (i (- (+ 1 2) 3)))
    (list a b c d e f g h i)))

(defun comparisons (x)
  (list (== x 1)
        (/= x 2)
        (< x 3)
        (> x 4)
        (=< x 5)
        (>= x 6)))

(defun booleans (a b)
  (list (and a b)
        (or a b)
        (andalso a b)
        (orelse a b)))
