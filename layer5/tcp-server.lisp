;; tcp application base
;; Copyright (C) 2007 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(in-package :application)

(defclass tcp-server(application)
  ((protocol :type tcp :accessor protocol
             :documentation "The tcp (layer 4) protocol instance")
   (local-port :initarg :local-port :initform nil
               :type ipport :reader local-port
               :documentation "Port number to bind to")
   (bytes-sent
    :initform 0 :type counter :accessor bytes-sent
    :documentation "total number of bytes sent by this application.")
   (bytes-ack :initform 0 :type counter :accessor bytes-ack
              :documentation "total bytes acknowledged by this application.")
   (bytes-received :initform 0 :type counter :accessor bytes-received
                   :documentation "total bytes received by this application")
   (response-statistics :initform nil
                        :initarg :response-statistics
                        :reader response-statistics
                        :documentation "object for logging response time")
   (tcp:close-on-empty :initform nil :initarg :close-on-empty
                   :reader tcp:close-on-empty)
   (msg-start
    :type time-type
    :documentation "Time the last message started transmission or receipt."))
  (:documentation "A simple model of a request/response
  TCP server.  The server binds to a specified port, and
  listens for connection requests from TCP peers.  The
  data received from the peers specifies how much data to send
  or receive."))

(defmethod initialize-instance((app tcp-server)
                               &key node local-port
                               (tcp-variant tcp:*default-tcp-variant*)
                               &allow-other-keys)
  (setf (slot-value app 'protocol)
        (make-instance tcp-variant
                       :application app :node node :local-port local-port))
  (tcp:listen (protocol app)))

(defmethod receive((app tcp-server) packet protocol &optional seq)
  (declare (ignore seq))
  (let ((data (pop-pdu packet)))
    (incf (bytes-received app) (size data))
    (unless (slot-boundp app 'msg-start)
      (setf (slot-value app 'msg-start) (packet:created packet)))
    (when (>= (bytes-received app) (data:msg-size data))
      (decf (bytes-received app) (data:msg-size data)) ;; subtract for nxt msg
      (setf (bytes-sent app) (data:response-size data) ;; no to send
            (bytes-ack app) 0);; clear ack
      (setf (tcp:close-on-empty (protocol app)) (tcp:close-on-empty app))
      (when (response-statistics app)
        (record (- (simulation-time) (slot-value app 'msg-start))
                (response-statistics app)))
      (slot-makunbound app 'msg-start)
      (when (> (bytes-received app) 0)
        (setf (slot-value app 'msg-start) (packet:created packet)))
      (when (> (bytes-sent app) 0)
        (send (bytes-sent app) (protocol app))))))

(defmethod sent((app tcp-server) c protocol)
  (incf (bytes-ack app) c)
  (when (>= (bytes-ack app) (bytes-sent app))
    (when (tcp:close-on-empty app)
      (close-connection (protocol app)))))

(defmethod bind((app tcp-server) &key port)
  "Binds and listen"
  (unbind (protocol app))
  (bind (protocol app) :port port)
  (listen (protocol app)))