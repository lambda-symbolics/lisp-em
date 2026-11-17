(in-package #:lisp-em)

;;;; -- Conditions --

(define-condition emacs-client-error (error)
  ((reason :initarg       :reason
           :reader        emacs-client-error-reason
           :type          (member :unavailable :timeout :elisp-error :protocol)
           :documentation "The category of request failure.")
   (message :initarg       :message
            :reader        emacs-client-error-message
            :type          string
            :documentation "A description of the failure.")
   (cause :initarg       :cause
          :initform      nil
          :reader        emacs-client-error-cause
          :documentation "The underlying condition, when available."))
  (:documentation "An Emacs server request failed.")
  (:report (lambda (condition stream)
             (write-string (emacs-client-error-message condition) stream))))

(defun client--fail (reason message &optional cause)
  "Signal a typed request failure with its optional underlying CAUSE."
  (error 'emacs-client-error :reason reason :message message :cause cause))


;;;; -- Quoting --

(defun quote-argument (text)
  "Quote TEXT using server.el's argument encoding."
  (check-type text string)
  (with-output-to-string (stream)
    (loop for character across text
          do (case character
               (#\&
                (write-string "&&" stream))
               (#\-
                (write-string "&-" stream))
               (#\Newline
                (write-string "&n" stream))
               (#\Space
                (write-string "&_" stream))
               (t
                (write-char character stream))))))

(defun unquote-argument (text)
  "Decode server.el's ampersand quoting, including its fallback to space."
  (check-type text string)
  (with-output-to-string (stream)
    (loop with index = 0
          while (< index (length text))
          do (let ((character (char text index)))
               (if (and (char= character #\&) (< (1+ index) (length text)))
                   (progn
                     (write-char (case (char text (1+ index))
                                   (#\&
                                    #\&)
                                   (#\-
                                    #\-)
                                   (#\n
                                    #\Newline)
                                   (t
                                    #\Space))
                                 stream)
                     (incf index 2))
                   (progn
                     (write-char character stream)
                     (incf index)))))))


;;;; -- Framing --

(defun client--read-reply (stream maximum-reply)
  "Read a bounded reply from borrowed STREAM, leaving it open.

Count every wire character, including newlines and ignored metadata, before
retaining it. Read at most MAXIMUM-REPLY + 1 characters. EOF terminates the
last line even without a newline. Join print frames and remove the one final
newline Emacs adds to its printed value."
  (check-type maximum-reply (integer 0))
  (let ((line (make-array (min 128 maximum-reply) :element-type 'character
                         :adjustable t :fill-pointer 0))
        (size 0))
    (with-output-to-string (value)
      (labels ((consume-line ()
                 "Decode a complete frame, ignoring server metadata."
                 (cond
                   ((uiop:string-prefix-p "-print-nonl " line)
                    (write-string (unquote-argument (subseq line 12)) value))
                   ((uiop:string-prefix-p "-print " line)
                    (write-string (unquote-argument (subseq line 7)) value))
                   ((uiop:string-prefix-p "-error " line)
                    (client--fail ':elisp-error
                                  (format nil "Emacs signaled: ~A"
                                          (string-right-trim '(#\Newline)
                                                             (unquote-argument (subseq line 7)))))))
                 (setf (fill-pointer line) 0)))
        (loop for character = (read-char stream nil nil)
              while character
              do (when (> (incf size) maximum-reply)
                   (client--fail ':protocol "The Emacs reply exceeds the character limit."))
                 (if (char= character #\Newline)
                     (consume-line)
                     (vector-push-extend character line)))
        (when (plusp (length line))
          (consume-line)))
      ;; The output stream holds decoded text only, never more than the wire cap.
      (let ((text (get-output-stream-string value)))
        (write-string (if (and (plusp (length text))
                               (char= (char text (1- (length text))) #\Newline))
                          (subseq text 0 (1- (length text)))
                          text)
                      value)))))

(defun client--roundtrip (stream form maximum-reply)
  "Send FORM and read its reply over borrowed STREAM without closing it."
  (write-string "-eval " stream)
  (write-string (quote-argument form) stream)
  (write-char #\Space stream)
  (write-char #\Newline stream)
  (finish-output stream)
  (client--read-reply stream maximum-reply))
