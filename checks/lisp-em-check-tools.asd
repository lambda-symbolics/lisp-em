;;;; -- Development Check Dependencies --

(asdf:defsystem #:lisp-em-check-tools
  :description "Development-only tools used by check.lisp."
  ;; Fresh cl-unicode sources require flexi-streams through a prepare-op
  ;; dependency on cl-unicode/build, outside Qlot's declared dependency graph.
  :depends-on  (#:cheque #:flexi-streams))
