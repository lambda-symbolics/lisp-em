(in-package #:lisp-em)

;;;; -- JSON Evaluation --

(defun evaluate-json (socket body &key arguments (timeout 10)
                                       (maximum-reply (* 8 1024 1024)))
  "Evaluate elisp BODY at SOCKET with string ARGUMENTS bound as A0, A1, and so on.

Encode arguments as UTF-8 data, not elisp source. BODY must return a value
accepted by Emacs's json-serialize. Return its decoded Argo JSON value:
objects as EQUAL hash tables, arrays as vectors, true as T, false as the
marker from ARGO:JSON-FALSE, and null as NIL. TIMEOUT and MAXIMUM-REPLY are
as in EVALUATE. Malformed replies signal EMACS-CLIENT-ERROR with reason
:PROTOCOL and the decoding condition as its cause, when available."
  (check-type body string)
  (check-type arguments list)
  (dolist (argument arguments)
    (check-type argument string))
  (client--decode-json
   (evaluate socket (client--json-form body arguments)
             :timeout timeout :maximum-reply maximum-reply)))

(defun client--json-form (body arguments)
  "Return the elisp form binding string ARGUMENTS around JSON-valued BODY."
  (format nil "(base64-encode-string (encode-coding-string (json-serialize (let (~{~A~^ ~}) ~A)) 'utf-8) t)"
          (loop for argument in arguments
                for index from 0
                collect (format nil "(a~D (decode-coding-string (base64-decode-string ~S) 'utf-8))"
                                index
                                (cl-base64:usb8-array-to-base64-string
                                 (sb-ext:string-to-octets argument :external-format ':utf-8))))
          body))

(defun client--decode-json (reply)
  "Decode the printed base64 string REPLY into its UTF-8 JSON value."
  (handler-case
      (progn
        (unless (and (>= (length reply) 2)
                     (char= (char reply 0) #\")
                     (char= (char reply (1- (length reply))) #\"))
          (client--fail ':protocol "Emacs did not return a printed base64 string."))
        (argo:json-decode
         (sb-ext:octets-to-string
          (cl-base64:base64-string-to-usb8-array (subseq reply 1 (1- (length reply)))
                                                :whitespace ':error)
          :external-format ':utf-8)))
    (emacs-client-error (condition)
      (error condition))
    (error (condition)
      (client--fail ':protocol "Emacs returned an unreadable JSON value." condition))))
