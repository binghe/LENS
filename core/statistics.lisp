;; Statistics base API
;; Copyright (C) 2013-2014 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;;; Copying:

;; This file is part of Lisp Educaqtional Network Simulator (LENS)

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; LENS is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(in-package :lens)

(defgeneric title(instance)
  (:documentation "* Arguments

- instance :: a [[statistic-listener]]

* Description

Return the publishable title for a result from a [[statistic-listener]]. Declared in the arguments to the =:statistic= property of a [[component]]."))

(defgeneric record(recorder time value)
  (:documentation "* Arguments

- recorder :: a [[result-recorder]]
- time :: a [[time-type]]
- value :: a =number=

* Description

Must be specialised for all [[result-recorder]] classes to record the
/value/ at simulation time /time/. /value/ will usually be a number
but could be a structure containing more information or treated as a
boolean for simple counting recorders."))

(defgeneric report(recorder stream)
  (:documentation "* Arguments

- recorder :: a [[result-recorder]]
- stream :: a /stream-designator/

* Description

Must be specialised for all [[result-recorder]] classes to report the
statistic value to /stream/. Defined for the [[scalar-recorder]] class
to output the value returned from [[recorded-value]] using the
[[output-format]] format string and for [[vector-recorder]] to output
the vector returned from [[recorded-vector]] at full precision.

* Notes

The [[finish]] method will be called on the [[result-recorder]] in
order for it to complete its statistics analysis at the simulation
termination time beforer any calls to [[report]]"))

(defstruct weighted
  "Structure for storing weighted values for statistical purposes."
  (weight 1.0 :type double-float)
  (value))

(defmethod record(recorder time (value weighted))
  "By default most recorders only want value"
  (record recorder time (weighted-value value)))

(defvar *statistic-filter-generators* (make-hash-table)
  "Mapping betetween statistic filter names and the function
  generators for this statistic generated using
  [[define-statistic-filter]].")

(defvar *result-recorders* (make-hash-table)
  "Mapping between statistic recorder recorder name and the
  implementation classes defined using [[define-result-recorder]]")

(defun declare-p (form)
  "Test if the form is a function declaration"
  (and (consp form) (eq 'declare (car form))))

(defmacro define-statistic-filter (name (var &rest statevars) &body body)
  "* Arguments

- name :: a =symbol= (evaluated)
- var :: a =symbol= (evaluated)
- statevars :: a binding form*
- body :: form*

* Description

Define and register a statistic filter function. /var/ is the name
used in /body/ to refer to the input value. statevars are the state
value definitions as per let which are bound outside the
finction. /body/ must return the filter value or null to abort
filtering.

* Example

;;; (define-statistic-filter count(value (count 0))
;;;   (declare (ignore value))
;;;   (incf count))

"
  (let ((filter-name (intern (format nil "STATISTIC-FILTER-~a" name))))
    `(progn
       (defun ,filter-name ()
         (let (,@statevars)
           #'(lambda (,var)
               ,(when (stringp (first body)) (first body))
               ,@(when (declare-p (second body)) `(,(second body)))
               (or (progn ,@(if (stringp (first body))
                                (if (declare-p (second body))
                                    (rest (cdr body))
                                  (rest body))
                              body))
                   (throw 'filter-abort ',name)))))
       (eval-when (:load-toplevel :execute)
         (setf (gethash ',name *statistic-filter-generators*)
               #',filter-name)))))

(defun make-statistic-filter(name)
  (let ((f (gethash name *statistic-filter-generators*)))
    (when f (funcall f))))

(defun define-result-recorder(classname &optional (name classname))
  "* Arguments

- classname :: a =symbol=
- name :: a =symbol=

* Description

Register the class denoted by /classname/ as a result recorder which
can be denoted by name /name/ in configuration files and =:statistic=
propery definitons of simulation components."
  (setf (gethash name *result-recorders*)
        (find-class classname)))

(defun make-result-recorder(spec owner)
  (multiple-value-bind(name args)
      (if (listp spec) (values (car spec) (cdr spec)) (values spec))
    (let ((class (gethash name *result-recorders*)))
      (if class
          (apply #'make-instance class
                 (nconc (list :name name :owner owner) args))
          (error "Unknown result recorder ~A" name)))))

(defclass statistic-listener(owned-object parameter-object)
  ((title :type string :reader title)
   (signal-values :type list :initform nil :accessor signal-values
                  :documentation "Cache of last signal values received")
   (source :type function :initform nil :initarg :source :reader source
           :documentation "Filter function for this statistic")
   (recorders :initarg :recorder :initform nil :reader recorders
              :documentation "The result recorders for this statistic"))
  (:metaclass parameter-class)
  (:documentation "Listener class for statistic recording. Statistics
  are declared using =:statistic= property in simulation component
  definitions and created after the simulation network has been
  created on the basis of the configuration parameters. There may be
  more than one such definition per component."))

(defmethod finish((instance statistic-listener))
  (map nil #'finish (recorders instance)))

(defun filter-code-walk(instance expression)
  "Return filter code from a filter expression"
  (let ((signals nil))
    (labels ((do-expand(form)
              (typecase form
                (symbol
                 (if (signal-id form)
                     (progn
                       (pushnew form signals)
                       `(signal-value ',form))
                     form))
               (list
                (let* ((name (first form))
                       (args (rest form))
                       (filter (make-statistic-filter name)))
                  (if filter
                      `(funcall ,filter ,@(mapcar #'do-expand args))
                      `(,name ,@(mapcar #'do-expand args)))))
               (t form))))
      (values
       (eval
        `(flet((signal-value(name)
                 (let ((v (getf (signal-values ,instance) name 'no-value)))
                   (when (eql v 'no-value) (throw 'filter-abort nil))
                   v)))
           (lambda() ,(do-expand expression))))
       signals))))

(defun stat-eql(a b)
  (flet((tp(x) (if (listp x) (first x) x)))
    (eql (tp a) (tp b))))

(defmethod initialize-instance :after ((instance statistic-listener)
                                       &key statistic &allow-other-keys)
  (setf (slot-value instance 'title)
        (or (getf statistic :title) (string (name instance))))
  (let* ((spec
          (multiple-value-bind(v f-p)
              (read-parameter instance 'result-recording-modes
                              '(read :multiplep t))
            (if f-p v (list :default))))
         (recording-modes
          (append (getf statistic :default)
                  (when (member :all spec) (getf statistic :optional)))))
    (when (eql (car spec) :none)
      (setf recording-modes nil
            spec (cdr spec)))
    (loop :for a :on spec :by #'cdr
       :when (eql (car a) '+)
       :do (setf recording-modes
                        (cons (second a)
                        (delete (second a) recording-modes :test #'stat-eql)))
       :when (eql (car a) '-)
       :do (setf recording-modes
                 (delete (second a) recording-modes :test #'stat-eql)))
    (setf (slot-value instance 'recorders)
            (mapcar
             #'(lambda(recorder-mode)
                 (make-result-recorder recorder-mode instance))
             recording-modes)))
  (multiple-value-bind(filter signals)
      (filter-code-walk instance
                        (or (getf statistic :source) (name instance)))
    (setf (slot-value instance 'source)  filter)
    (dolist(signal signals)
      (subscribe (owner instance) signal instance))))

(defclass result-recorder(owned-object)
  ()
  (:documentation "The base class for all result recorders.
  [[receive-signal]] is specialised on this class to call [[record]]
  on the instance with appropriate values after the simulation
  [[warmup-period]]."))

(defmethod title((instance result-recorder))
         (title (owner instance)))

;; map listener receive-signal with source onto statistic receive-signal with time
(defmethod receive-signal((listener statistic-listener) signal
                          source (value timestamped))
  (receive-signal listener signal
                  (timestamped-time value) (timestamped-value value)))

(defmethod receive-signal((listener statistic-listener) signal
                          source value)
  (receive-signal listener signal (simulation-time) value))

(defmethod receive-signal((listener statistic-listener) signal (time real)
                          value)
  (unless (>= time (warmup-period *simulation*))
    (return-from receive-signal))
  (setf (getf (signal-values listener) signal) value)
  (catch 'filter-abort
    (let ((value (funcall (source listener))))
      (dolist(recorder (recorders listener))
        (record recorder time value)))))

(defmethod info((r result-recorder))
  (with-output-to-string(os) (report r os)))

(defclass scalar-recorder(result-recorder)
  ((output-format :initform "~A" :initarg :format
           :documentation "Format to use when outputing recorded units"))
  (:documentation "Base class for all scalar value [[result-recorder]]
  classes. Specialises [[report]] to output the value returned by
  [[recorded-value]] using the format specified in the =:format
  initialisation argument. "))

(defgeneric recorded-value(scalar-recorder)
  (:documentation "Return the value to record for a scalar recorder"))

(defmethod finish((r scalar-recorder))
  (let ((os (scalar-stream *simulation*)))
    (when (and os (scalar-recording r))
      (report r os))))

(defmethod report((r scalar-recorder) stream)
  (format stream "scalar ~S ~S ~?~%"
          (full-path-string (owner (owner r))) (title r)
          (slot-value r 'output-format) (list (recorded-value r))))

(defun add-statistics(sim)
  (labels((do-add-statistics(module)
            (let((names nil))
              (loop :for a :on (properties module) :by #'cddr
                 :when (eql (first a) :statistic)
                 :do (let ((name (car (second a)))
                           (statistic (rest (second a))))
                       (unless (member name names)
                         (push name names)
                         (make-instance 'statistic-listener
                                  :owner module
                                  :name name
                                  :statistic statistic)))))
            (when (typep module 'compound-module)
              (for-each-submodule module #'do-add-statistics))))
    (do-add-statistics (network sim))))

(eval-when(:load-toplevel :execute)
  (pushnew 'add-statistics *simulation-init-hooks*))
