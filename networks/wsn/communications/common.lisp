(in-package :lens.wsn)

(defclass wsn-packet(packet)
  ((header-overhead
    :initform 0 :accessor header-overhead :initarg :header-overhead
    :documentation "In bytes")
   (source :initarg :source :accessor source
           :documentation "the  source address of the received packet")
   (destination
    :initarg :destination :accessor destination
    :documentation "the destination address of the packet to be sent")
   (sequence-number :initarg :seqnum :initarg :sequence-number
                    :reader sequence-number :reader sequence-number
                    :documentation "a field to distinguish between packets"))
  (:documentation "Base class for network and link layer packets"))

(defmethod duplicate((packet wsn-packet) &optional duplicate)
  (call-next-method)
  (copy-slots
   '(header-overhead source-address destination-address sequence-number)
   packet duplicate))

(defmethod byte-length((packet wsn-packet))
  (+ (header-overhead packet)
     (byte-length (slot-value packet 'lens::encapsulated-packet))))

(defmethod bit-length((packet wsn-packet)) (* 8 (byte-length packet)))

(defclass comms-module(module)
  ((buffer :type packet-buffer :reader buffer)
   (buffer-size :parameter t :initform 0 :type integer :initarg :buffer-size)
   (packet-history
    :type history-buffer
    :initform (make-instance 'history-buffer
                             :element-type 'packet
                             :key #'(lambda(p)
                                      (cons (source-address p)
                                            (sequence-number p))))
    :reader packet-history)
   (last-sequence-number :initform -1 :type integer
                         :accessor last-sequence-number)
   (header-overhead
    :type integer :parameter t :initform 10 :reader header-overhead
    :properties (:units "B")
    :documentation "in bytes"))
  (:metaclass module-class))

(defmethod build-submodules((module comms-module))
  (let ((buffer-size (slot-value module 'buffer-size)))
    (unless (zerop buffer-size)
      (setf (slot-value module 'buffer)
            (make-instance 'packet-buffer :owner module :name 'buffer
                           :buffer-size buffer-size)))))

(defmethod for-each-submodule((module comms-module) (operator function))
  (funcall operator (buffer module)))

(defmethod shutdown((module comms-module))
  (let ((buffer (buffer module)))
    (while (not (empty-p buffer)))
    (emit buffer 'drop (dequeue (queue buffer)))
    (setf (slot-value buffer 'byte-length) 0)
    (emit buffer 'buffer-length buffer)))
