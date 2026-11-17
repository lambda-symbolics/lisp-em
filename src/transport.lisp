(in-package #:lisp-em)

;;;; -- Native SBCL Transport --

(defun client--close (connection)
  "Close the socket owned by this request, including its associated stream."
  (sb-bsd-sockets:socket-close connection))

(defun client--connect (pathname)
  "Open one local socket or signal a typed unsupported-host failure."
  #+win32
  (declare (ignore pathname))
  #+win32
  (client--fail ':unavailable "This host has no supported Emacs local-socket transport.")
  #-win32
  (let ((socket (make-instance 'sb-bsd-sockets:local-socket :type ':stream)))
    (handler-case
        (progn
          (sb-bsd-sockets:socket-connect socket (uiop:native-namestring pathname))
          socket)
      (error (condition)
        (handler-case (client--close socket)
          (error () nil))
        (error condition)))))

(defun client--make-stream (connection timeout)
  "Create the UTF-8 stream owned by CONNECTION with a per-I/O timeout."
  (sb-bsd-sockets:socket-make-stream
   connection :input t :output t :element-type 'character
              :external-format ':utf-8 :buffering ':full :timeout timeout))

(defun client--call-with-connection (socket function &key timeout
                                                        (connector #'client--connect)
                                                        (stream-maker #'client--make-stream)
                                                        (closer #'client--close))
  "Call FUNCTION with a fresh stream, releasing only the connection opened here.

The private transport callbacks let tests exercise every ownership transition.
Cleanup cannot replace the result or condition from the request."
  (let ((connection
          (handler-case (funcall connector socket)
            (emacs-client-error (condition)
              (error condition))
            (error (condition)
              (client--fail ':unavailable "The Emacs server socket is not reachable." condition)))))
    (unwind-protect
         (handler-case
             (funcall function (funcall stream-maker connection timeout))
           (emacs-client-error (condition)
             (error condition))
           (sb-sys:io-timeout (condition)
             (client--fail ':timeout "The Emacs server I/O timed out." condition))
           (error (condition)
             (client--fail ':protocol "The Emacs server connection failed." condition)))
      (handler-case (funcall closer connection)
        (error () nil)))))

(defun evaluate (socket form &key (timeout 10) (maximum-reply (* 8 1024 1024)))
  "Evaluate elisp FORM at local SOCKET and return its printed value.

TIMEOUT is SBCL's per-blocking-I/O timeout in seconds, not a total deadline.
MAXIMUM-REPLY bounds all received wire characters before retention. Each call
owns one fresh connection and closes it on every exit. No configuration,
JSON conversion, authorization or server discovery is performed."
  (check-type socket (or pathname string))
  (check-type form string)
  (check-type timeout (real 0))
  (check-type maximum-reply (integer 0))
  (client--call-with-connection
   (pathname socket)
   (lambda (stream) (client--roundtrip stream form maximum-reply))
   :timeout timeout))
