;;;; -- Development Check Dependencies --

;;; qlot installs project deps by reading ASDF system definitions.
;;; This system declares cheque, the source checker loaded by the ./script/check script.
;;; This is so that installing checks/qlfile also installs cheque's own dependencies.

(asdf:defsystem #:lisp-em-check-tools
  :description "The devel tools loaded for lisp-em's source checks."
  ;; Fresh cl-unicode sources require flexi-streams through a prepare-op
  ;; dependency on cl-unicode/build, outside Qlot's declared dependency graph.
  :depends-on  (#:cheque #:flexi-streams))
