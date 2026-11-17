;;;; -- Development Check Dependencies --

(asdf:defsystem #:lisp-em-check-tools
  :description "Development-only tools used by check.lisp."
  :depends-on  (#:cheque))
