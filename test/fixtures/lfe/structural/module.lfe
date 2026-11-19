;; Module and function structure - M2.2s Structural Layer

(defmodule math
  (export (add 2)
          (sub 2)
          (no-args 0)))

(defun add (a b)
  (+ a b))

(defun sub (a b)
  (- a b))

(defun no-args ()
  'ok)
