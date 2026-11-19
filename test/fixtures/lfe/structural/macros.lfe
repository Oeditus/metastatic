;; Macros - M2.2s Structural Layer

(defmacro unless (test body)
  `(if (not ,test) ,body 'nil))

(defun use-macro (x)
  (unless (== x 0) 'nonzero))
