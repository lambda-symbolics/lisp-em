(defpackage #:lisp-em-tests
  (:documentation "Protocol and ownership checks for lisp-em.")
  (:use #:cl)
  (:export #:run-tests))

(in-package #:lisp-em-tests)

(defvar *checks* 0 "The number of assertions in the current run.")

(defun check (value description)
  "Count an assertion, signaling on failure."
  (incf *checks*)
  (assert value () "~A" description))

(defun expect-error (reason function)
  "Return FUNCTION's typed failure after checking its REASON."
  (handler-case
      (progn (funcall function) (check nil "Expected a typed Emacs client failure."))
    (lisp-em:emacs-client-error (condition)
      (check (eq reason (lisp-em:emacs-client-error-reason condition)) "Failure category.")
      condition)))

(defclass counting-input (trivial-gray-streams:fundamental-character-input-stream)
  ((remaining :initarg :remaining :accessor input-remaining
              :documentation "Characters still available to generate.")
   (reads :initform 0 :accessor input-reads
          :documentation "Calls to STREAM-READ-CHAR, including EOF."))
  (:documentation "Generate a huge line without allocating it in the test."))

(defmethod trivial-gray-streams:stream-read-char ((stream counting-input))
  "Generate one character, counting every read request."
  (incf (input-reads stream))
  (if (plusp (input-remaining stream))
      (progn (decf (input-remaining stream)) #\x)
      :eof))

(defun protocol-tests ()
  "Exercise quoting, frame assembly, EOF and aggregate incremental limits."
  (dolist (case (list '("plain" "plain") '("two words" "two&_words")
                      '("-flag" "&-flag") '("a&b" "a&&b")
                      (list (format nil "λ~%line") "λ&nline")))
    (destructuring-bind (text quoted) case
      (check (equal quoted (lisp-em:quote-argument text)) "Wire quoting.")
      (check (equal text (lisp-em:unquote-argument quoted)) "Quoting round trip.")))
  (check (equal "x " (lisp-em:unquote-argument "x&z")) "Server fallback escape.")
  (check (equal "&" (lisp-em:unquote-argument "&")) "Trailing literal ampersand.")
  (dolist (case (list (list (format nil "-emacs-pid 42~%-print \"abc~%-print-nonl &_def\"~%") "\"abc def\"")
                      (list "-print λ&n" "λ")
                      (list "-print x&n&n" (format nil "x~%"))
                      (list "-print 42" "42")
                      (list "" "")))
    (destructuring-bind (wire expected) case
      (with-input-from-string (stream wire)
        (check (equal expected (lisp-em::client--read-reply stream (length wire))) "Frame assembly at exact cap.")
        (check (open-stream-p stream) "The reader borrows its stream."))))
  (with-input-from-string (stream "-error void&_variable&n")
    (let ((condition (expect-error ':elisp-error (lambda () (lisp-em::client--read-reply stream 100)))))
      (check (search "void variable" (lisp-em:emacs-client-error-message condition)) "Unquoted server failure.")
      (check (open-stream-p stream) "Elisp failure does not close borrowed stream.")))
  (dolist (wire (list (format nil "~%~%~%")
                     (format nil "-emacs-pid 42~%-emacs-pid 43~%")
                     (format nil "-print x~%-print y~%")))
    (with-input-from-string (stream wire)
      (expect-error ':protocol (lambda () (lisp-em::client--read-reply stream (1- (length wire)))))
      (check (open-stream-p stream) "Limit failure leaves borrowed stream open.")))
  (let ((stream (make-instance 'counting-input :remaining 1000000000)))
    (unwind-protect
         (progn
           (expect-error ':protocol (lambda () (lisp-em::client--read-reply stream 32)))
           (check (= 33 (input-reads stream)) "A huge unterminated line stops at cap plus one.")
           (check (open-stream-p stream) "Generated borrowed stream is open."))
      (close stream))))

(defun ownership-tests ()
  "Exercise each connection ownership transition, including failing cleanup."
  (dolist (stage '(:connect :stream :request :elisp :success :cleanup))
    (let ((closed  0)
          (primary (make-condition 'simple-error :format-control "Injected failure."))
          (elisp   (make-condition 'lisp-em:emacs-client-error
                                   :reason ':elisp-error :message "Injected elisp failure.")))
      (flet ((invoke ()
               "Execute one simulated request over an owned connection."
               (lisp-em::client--call-with-connection
                #P"unused"
                (lambda (stream)
                  (check (eq stream ':stream) "The request receives its stream.")
                  (case stage
                    (:request
                     (error primary))
                    (:elisp
                     (error elisp))
                    (t
                     "ok")))
                :timeout      1
                :connector    (lambda (path)
                                (declare (ignore path))
                                (when (eq stage ':connect) (error primary))
                                ':connection)
                :stream-maker (lambda (connection timeout)
                                (check (and (eq connection ':connection) (= timeout 1)) "Stream belongs to connection.")
                                (when (eq stage ':stream) (error primary))
                                ':stream)
                :closer       (lambda (connection)
                                (check (eq connection ':connection) "Cleanup receives owned connection only.")
                                (incf closed)
                                (when (member stage '(:request :cleanup)) (error "Cleanup failure."))))))
        (case stage
          ((:connect :stream :request)
           (let ((condition (expect-error (if (eq stage ':connect) ':unavailable ':protocol) #'invoke)))
             (check (eq primary (lisp-em:emacs-client-error-cause condition)) "The original failure is retained.")))
          (:elisp
           (check (eq elisp (expect-error ':elisp-error #'invoke)) "A typed primary failure is preserved."))
          (t
           (check (equal "ok" (invoke)) "Cleanup cannot mask success.")))
        (check (= closed (if (eq stage ':connect) 0 1)) "Close exactly one acquired connection.")))))

#-win32
(defun socket-test (reply &key timeout)
  "Run one native fake-server roundtrip, releasing the fixture's listener."
  (let* ((path     (merge-pathnames (format nil "lisp-em-~D-~D.socket" (sb-posix:getpid) (random 1000000))
                                   (uiop:temporary-directory)))
         (listener (make-instance 'sb-bsd-sockets:local-socket :type ':stream))
         (thread   nil)
         (request  nil))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind listener (uiop:native-namestring path))
           (sb-bsd-sockets:socket-listen listener 1)
           (setf thread
                 (sb-thread:make-thread
                  (lambda ()
                    (let ((connection (sb-bsd-sockets:socket-accept listener)))
                      (unwind-protect
                           (let ((stream (sb-bsd-sockets:socket-make-stream
                                          connection :input t :output t :element-type 'character
                                                     :external-format ':utf-8 :buffering ':full)))
                             (setf request (read-line stream))
                             (if timeout
                                 (sleep 0.2)
                                 (progn (write-string reply stream) (finish-output stream))))
                        (sb-bsd-sockets:socket-close connection))))))
           (let ((result (if timeout
                             (expect-error ':timeout (lambda () (lisp-em:evaluate path "(foo λ)" :timeout 0.05)))
                             (lisp-em:evaluate path "(foo λ)"))))
             (sb-thread:join-thread thread)
             (setf thread nil)
             (check (equal request "-eval (foo&_λ) ") "Native request has quoting and trailing space.")
             result))
      (when thread
        (sb-thread:join-thread thread :timeout 2 :default nil))
      (sb-bsd-sockets:socket-close listener)
      (when (probe-file path) (delete-file path)))))

(defun run-tests ()
  "Run the protocol and ownership cases, plus native transport where supported."
  (let ((*checks* 0))
    (protocol-tests)
    (ownership-tests)
    #-win32
    (progn
      (check (equal "42" (socket-test (format nil "-print 42~%"))) "Native roundtrip.")
      (socket-test "" :timeout t)
      (expect-error ':unavailable (lambda () (lisp-em:evaluate #P"/no-such-lisp-em-server" "t"))))
    #+win32
    (expect-error ':unavailable (lambda () (lisp-em:evaluate #P"missing" "t")))
    (format t "~&lisp-em: ~D checks passed.~%" *checks*)
    t))
