;; Statistics definitions
;; Copyright (C) 2013-2014 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;;; Copying:

;; This file is part of LENS

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

;; The implementation is in a seperate file as API definitions have to
;; be loaded to enable registration of filters and recorders.

;;; Code:

(in-package :lens)

;; TODO numberical indexing of vector recorders and results

(defclass vector-recorder(result-recorder)
  ((last-time :initform -1 :type time-type :accessor last-time
              :documentation "to ensure increasing timestamp order")
   (recorded-vector :initform (make-array 1024 :element-type 'timestamped
                                 :adjustable t :fill-pointer 0)
                    :reader recorded-vector))
  (:documentation "Recorder class which records the a vector of time
  and values using [[record]]. Ensures times are increasing order and
  reports the vector of stored values in [[report]]."))

(define-result-recorder 'vector-recorder 'vector)

(defmethod record((recorder vector-recorder) time (value real))
  (with-slots(last-time recorded-vector) recorder
    (assert (< last-time time)
            ()
            "~A cannot record data with earlier timestamp (t=~A)"
            recorder last-time)
    (setf last-time time)
  (vector-push-extend (make-timestamped :time time :value value)
                      recorded-vector)))

(defmethod finish((r vector-recorder))
  (let ((os (vector-stream *simulation*)))
    (when (and os (vector-recording r))
      (report r os))))

(defmethod report((r vector-recorder) stream)
  (format stream "vector ~S ~S~%" (full-path-string (owner r)) (title r))
  (map nil
       #'(lambda(v)
           (format stream "~A~t~A~%"
                   (timestamped-time v) (timestamped-value v)))
       (recorded-vector r)))

(define-statistic-filter count(value (count 0))
  "Count the number of values received."
  (declare (ignore value))
  (incf count))

(define-statistic-filter sum(value (sum 0d0))
  "Return the sum of all received values."
  (incf sum value))

(define-statistic-filter mean(value (sum 0d0) (count 0))
  "Return the average value value received so far."
  (/ (incf sum value) (incf count)))

(define-statistic-filter min(value min)
  "Return the minimum value received so far."
  (when (or (not min) (< value min)) (setf min value)))

(define-statistic-filter max(value max)
  "Return the maximum value received so far."
  (when (or (not max) (> value max)) (setf max value)))

(define-statistic-filter constant0(value)
  "Always return 0"
  (declare (ignore value))
  0)

(define-statistic-filter constant1(value)
  "Always return 1"
  (declare (ignore value))
  1)

(defclass count-recorder(scalar-recorder)
  ((count :accessor recorded-value :initform 0))
  (:documentation "Record the number of signals received."))

(define-result-recorder 'count-recorder 'count)

(defmethod record((recorder count-recorder) time value)
  (declare (ignore time value))
  (incf (recorded-value recorder)))

(defmethod report((r count-recorder) stream)
  (declare (ignore stream))
  (unless (zerop (recorded-value r))
    (call-next-method)))

(defclass sum(scalar-recorder)
  ((sum :accessor recorded-value :initform 0))
  (:documentation "Record the sum of the numeric values received."))

(define-result-recorder 'sum)

(defmethod record((recorder sum) time value)
  (declare (ignore time))
  (incf (recorded-value recorder) value))

(defclass mean(scalar-recorder)
  ((sum :initform 0)
   (count :initform 0))
  (:documentation "Record the mean of the numeric values received."))

(define-result-recorder 'mean)

(defmethod record((recorder mean) time value)
  (declare (ignore time))
  (with-slots(sum count) recorder
    (incf sum value)
    (incf count)))

(defmethod recorded-value((recorder mean))
  (with-slots(sum count) recorder
    (unless (zerop count)
      (/ sum count))))

(defclass last-value(scalar-recorder)
  ((value :initform nil :accessor recorded-value))
  (:documentation "Record the last value received."))

(define-result-recorder 'last-value)

(defmethod record ((r last-value) time value)
  (declare (ignore time))
  (setf (recorded-value r) value))

(defclass min-recorder(last-value)
  ()
  (:documentation "Record the minimum value received."))

(define-result-recorder 'min-recorder 'min)

(defmethod record ((r min-recorder) time value)
  (declare (ignore time))
  (when (or (not (recorded-value r)) (< value (recorded-value r)))
    (setf (recorded-value r) value)))

(defclass max-recorder(last-value)
  ()
  (:documentation "Record the maximum value received."))

(define-result-recorder 'max-recorder 'max)

(defmethod record ((r max-recorder) time value)
  (declare (ignore time))
  (when (or (not (recorded-value r)) (> value (recorded-value r)))
    (setf (recorded-value r) value)))

(defclass timeavg(scalar-recorder)
  ((start-time :initform -1 :type timetype)
   (last-time :type timetype)
   (weighted-sum :type real :initform 0)
   (last-value :type real :initform 0))
  (:documentation "Record the time averaged value received."))

(define-result-recorder 'timeavg)

(defmethod record((r timeavg) time value)
  (with-slots(start-time last-time last-value weighted-sum) r
    (if (< start-time 0)
        (setf start-time time)
        (incf weighted-sum (* last-value (- time last-time))))
    (setf last-time time
          last-value value)))

(defmethod finish :before ((r timeavg))
  "Take account of last interval"
  (record r (simulation-time) nil))

(defmethod recorded-value((r timeavg))
  (with-slots(weighted-sum start-time last-time) r
    (/ weighted-sum (- last-time start-time))))

(defclass stddev(scalar-recorder)
  ((output-format :initform "~3@/dfv:eng/")
   (count :type integer :initform 0 :reader result-count)
   (min :type float :initform nil :reader result-min)
   (max :type float :initform nil :reader result-max)
   (sum :type float :initform 0 :reader result-sum)
   (sqrsum :type float :initform 0 :reader result-sqrsum))
  (:documentation "Output basic statistics (cound,min,max,mean and
  stddev) of numeric values received."))

(define-result-recorder 'stddev)

(defgeneric result-mean(r)
  (:method((r stddev))
    (with-slots(sum count) r
      (unless (zerop count) (coerce (/ sum count)  'float)))))

(defgeneric result-variance(r)
  (:method((r stddev))
    (with-slots(sqrsum sum count) r
      (unless (<= count 1)
        (coerce (/ (- sqrsum (/ (* sum sum) count)) (1- count)) 'float)))))

(defgeneric result-stddev(r)
  (:method((r stddev))
    (let ((v (result-variance r)))
      (when v (sqrt v)))))

(defmethod record((r stddev) time (value real))
  (declare (ignore time))
  (with-slots(min max sum count sqrsum) r
      (when (or (not min) (< value min)) (setf min value))
      (when (or (not max) (> value max)) (setf max value))
      (incf count)
      (incf sum value)
      (incf sqrsum (* value value))))

(defun write-fields(stream r fields)
  (dolist(a fields)
    (format stream "field ~A~13T~?~%"
            (first a)
            (or (third a) (slot-value r 'output-format) "~A")
            (list (let ((v (second a)))
                    (etypecase v
                      (function (funcall v r))
                      (number v)
                      (string v)
                      (symbol (slot-value r v))))))))

(defmethod report((r stddev) stream)
  (unless (zerop (result-count r))
  (format stream "statistic ~S ~S~%" (full-path-string (owner (owner r))) (title r))
  (write-fields
   stream
   r
   `(("count" ,#'result-count "~D")
     ("mean" ,#'result-mean)
     ("stddev" ,#'result-stddev)
     ("sum" ,#'result-sum)
     ("sqrsum", #'result-sqrsum)
     ("min" ,#'result-min)
     ("max" ,#'result-max)))))

(defclass weighted-stddev(stddev)
  ((sum-weights :type real :initform 0)
   (sum-weighted-vals :type real :initform 0)
   (sum-squared-weights :type real :initform 0)
   (sum-weights-squared-vals :type real :initform 0))
  (:documentation "Output basic statistics (cound,min,max,mean and
  stddev) of [[weighted]] values received taking acount of the
  [[weighted-weight]] of these values."))

(define-result-recorder 'weighted-stddev)

(defmethod result-mean((r weighted-stddev))
  (with-slots(sum-weights sum-weighted-vals) r
    (unless (zerop sum-weights) (/ sum-weights sum-weighted-vals))))

(defmethod result-variance((r weighted-stddev))
  (with-slots(count sum-weights sum-weighted-vals
                    sum-squared-weights
                    sum-weights-squared-vals) r
    (unless (<= count 1)
      (/ (- (* sum-weights sum-weights-squared-vals)
            (* sum-weighted-vals sum-weighted-vals))
         (- (* sum-weights sum-weights)
            sum-squared-weights)))))

(defmethod record((r weighted-stddev) time value)
  (call-next-method)
  (multiple-value-bind(value weight)
      (etypecase value
        (real (values value 1))
        (weighted (values (weighted-weight value) (weighted-value value))))
    (with-slots(sum-weights sum-weighted-vals
                sum-squared-weights sum-weights-squared-vals) r
      (incf sum-weights weight)
      (incf sum-weighted-vals (* weight value))
      (incf sum-squared-weights (* weight weight))
      (incf sum-weights-squared-vals (* weight value value)))))

(defmethod report((r weighted-stddev) stream)
  (unless (zerop (result-count r))
    (call-next-method)
    (write-fields
     stream
     r
     '(("weights" sum-weights)
       ("weightedSum" sum-weighted-vals)
       ("sqrSumWeights" sum-squared-weights)
       ("weightedSqrSum" sum-weights-squared-vals)))))

(defclass histogram(stddev)
  ((range-min :initarg :min :initform nil :type real :reader range-min)
   (range-max :initarg :max :initform nil :type real :reader range-max)
   (range-ext-factor :initarg :range-ext-factor :initform 1
                     :type real :reader range-ext-factor
                     :documentation "Factor to expand range by")
   (mode :type symbol :initarg :mode :initform nil :reader histogram-mode
         :documentation "integer or float mode for collection.")
   (rng :type fixnum :initform 0 :initarg :genk
         :documentation "Index of random number generator to use")
   (num-cells :initarg :num-cells :initform 10 :reader num-cells :type fixnum
              :documentation "How many cells to use.")
   (cell-size :initform nil :reader cell-size :type real
              :reader histogram-transformed-p
              :documentation "Cell size once scale determined.")
   (array :type (array real *) :reader cells
          :documentation "Pre-collected observations or cells")
   (units :type string :initform "s" :initarg :units)
   (underflow-cell :initform 0 :type integer :accessor underflow-cell
                   :documentation "Number of observations below range-min")
   (overflow-cell :initform 0 :type integer :accessor overflow-cell
                  :documentation "Number of observations above range-max"))
  (:documentation "Base class for density estimation classes.

 For the histogram classes, you need to specify the number of cells
 and the range. Range can either be set explicitly or you can choose
 automatic range determination.

 Automatic range estimation works in the following way:

 1.  The first num_firstvals observations are stored.
 2.  After having collected a given number of observations, the actual
     histogram is set up. The range (*min*, *max*) of the
     initial values is expanded *range_ext_factor* times, and
     the result will become the histogram's range (*rangemin*,
     *rangemax*). Based on the range, the cells are layed out.
     Then the initial values that have been stored up to this point
     will be transferred into the new histogram structure and their
     store is deleted -- this is done by the transform() function.

You may also explicitly specify the lower or upper limit and have
the other end of the range estimated automatically. The setRange...()
member functions of cDensityEstBase deal with setting
up the histogram range. It also provides pure virtual functions
transform() etc.

Subsequent observations are placed in the histogram structure.
If an observation falls out of the histogram range, the *underflow*
or the *overflow* *cell* is incremented."))

(define-result-recorder 'histogram)

;; TODO INTEGER mode - proper ranging

(defun autorange(min max)
  (let*((diff (- max min))
        (s (float (expt 10 (1- (ceiling (log diff 10)))))))
    (values (* (floor (/ min s)) s)
            (* (ceiling (/ max s)) s))))

(defun histogram-setup-cells(instance)
  (with-slots(range-min range-max num-cells cell-size array mode) instance
    (if (eql mode 'integer)
        (setf range-min (floor range-min)
              range-max (ceiling range-max))
        (multiple-value-bind(min max) (autorange range-min range-max)
          (setf range-min min
                range-max max)))
    (setf cell-size (/ (- range-max range-min) num-cells))
    (when (and (eql mode 'integer) (not (integerp cell-size)))
      (let  ((c (ceiling cell-size)))
        (setf range-min (floor range-min)
              range-max (+ range-min (* num-cells c))
              cell-size c)))
    (setf array
          (make-array num-cells :element-type 'integer
                            :initial-element 0))))

(defun histogram-insert-to-cell(instance value)
  (with-slots(range-min range-max num-cells cell-size) instance
      (let ((k (floor (- value range-min) cell-size)))
        (cond
          ((or (< k 0) (< value range-min))
           (incf (underflow-cell instance)))
          ((or (>= k num-cells) (>= value range-max))
           (incf (overflow-cell instance)))
          (t (incf (aref (cells instance) k)))))))

(defun histogram-transform(instance)
  (assert (not (histogram-transformed-p instance)))
  (with-slots(range-min range-max range-ext-factor cell-size array mode)
      instance
    (declare (ignore cell-size))
    (let* ((firstvals array)
           (min (reduce #'min firstvals))
           (max (reduce #'max firstvals)))
      (cond
        ((not (or range-min range-max))
         (let ((c (/ (+ max min) 2))
                 (r (* (- max min) range-ext-factor)))
             (when (zerop r) (setf r 1.0))
             (setf range-min (- c (/ r 2))
                   range-max (+ c (/ r 2)))))
        (range-max ;; only min needs determining
         (setf range-min
               (if (<= range-max min)
                   (- range-max 1.0)
                   (- range-max (* (- range-max min) range-ext-factor)))))
        (range-min
         (setf range-max
               (if (>= range-min max)
                   (+ range-min 1.0)
                   (+ range-min (* (- max range-min) range-ext-factor))))))
    (unless mode
      (setf mode
            (if (and (every #'integerp firstvals)
                     (not (every #'zerop firstvals)))
                'integer
                'float)))
      (histogram-setup-cells instance)
      (map nil #'(lambda(v) (histogram-insert-to-cell instance v)) firstvals))))

(defmethod initialize-instance :after
    ((instance histogram) &key (num-firstvals 100) &allow-other-keys)
    (if (and (range-min instance) (range-max instance))
        (histogram-setup-cells instance)
        (setf (slot-value instance 'array)
              (make-array num-firstvals :element-type 'real
                          :fill-pointer 0))))

(defmethod record :before ((instance histogram) time (value number))
  (when (eql (histogram-mode instance) 'integer)
    (assert (integerp value)
          (value)
          "Histogram in INTEGER mode cannot accept a float value")))

(defmethod record((instance histogram) time value)
  (declare (ignore time))
  (call-next-method)
  (when (not (histogram-transformed-p instance))
    (let ((firstvals (slot-value instance 'array)))
      (if (< (length firstvals) (array-total-size firstvals))
          (progn
            (vector-push value firstvals)
            (return-from record))
          (histogram-transform instance))))
  (histogram-insert-to-cell instance value))

(defmethod report((r histogram) stream)
  (unless (zerop (result-count r))
    (unless (histogram-transformed-p r) (histogram-transform r))
    (call-next-method)
    (format stream "attr unit ~A~%" (slot-value r 'units))
    (format stream "bin -INF~13T~5D~%" (underflow-cell r))
    (let ((b (range-min r)))
      (dotimes(k (length (cells r)))
        (format stream "bin ~?~13T~5D~%" (slot-value r 'output-format) (list b)
                (aref (cells r) k))
        (incf b (cell-size r))))
    (format stream "bin +INF~13T~5D~%" (overflow-cell r))))

(defgeneric probability-density-function(instance x)
  (:documentation "Returns the estimated value of the Probability
  Density Function at a given x."))

(defgeneric cumulative-density-function(instance x)
  (:documentation "Returns the estimated value of the Cumulated
  Density Function at a given x."))

(defmethod probability-density-function((instance histogram) (x number))
  (unless (histogram-transformed-p instance)
    (histogram-transform instance))
  (let ((k (floor (- x (range-min instance)) (cell-size instance))))
    (if (or (< k 0) (< x (range-min instance))
            (>= k (num-cells instance)) (>= x (range-max instance)))
        0.0d0
        (/ (aref (cells instance) k)
           (cell-size instance)
           (result-count instance)))))

(defmethod rand((instance histogram) &optional limit)
  (assert (null limit)
          ()
          "rand on a histogram requires no limit - limits dictated by
          distribution")
  (with-slots(rng) instance
  (cond
    ((zerop (result-count instance)) 0)
    ((histogram-transformed-p instance)
     (let ((k
        ;;select a random cell (k-1) and return a random number from it
            (do((k 0 (1+ k))
                (m (%genintrand
                    (- (result-count instance)
                       (underflow-cell instance)
                       (overflow-cell instance))
                    rng)
                   (- m (aref (cells instance) k))))
               ((< m 0) k))))
       (+ (range-min instance)
          (* (1- k) (cell-size instance))
          (* (%gendblrand rng) (cell-size instance)))))
    (t ;; simply return sample from stored ones
     (aref (cells instance)  (%genintrand (result-count instance) rng))))))

(defclass indexed-count-recorder(scalar-recorder)
  ((count :initform (make-hash-table :test #'equal)
          :accessor recorded-value))
  (:documentation "Indexed count records the number of times a
  particular value is received. Values are compare using EQL. If a
  CONS is recieved using [[record]] the =car= is taken as the index
  key and the =cdr= is the amount the count is to be incremented.

  This provides a means e.g. to record the number of packets received
  by source at a destination etc.

  The recorder reports as a statistic with the keys as field names.
"))

(define-result-recorder 'indexed-count-recorder 'indexed-count)

(defmethod record((recorder indexed-count-recorder) time value)
  (incf (gethash value (recorded-value recorder) 0)))

(defmethod record((recorder indexed-count-recorder) time (value list))
  (incf (gethash (car value) (recorded-value recorder) 0) (cdr value)))

(defmethod report((r indexed-count-recorder) os)
  (when (not (zerop (hash-table-count (recorded-value r))))
    (format os "statistic ~S ~S~%"
            (full-path-string (owner (owner r))) (title r))
    (dolist(k
             (sort
              (loop :for k :being :each :hash-key :of (recorded-value r)
                 :collect k)
              #'(lambda(a b) (if (numberp a)
                                 (< a b)
                                 (string< (string a) (string b))))))
      (format os "field ~S ~A~%" k (gethash k (recorded-value r))))))

(defclass accumulated-time-recorder(scalar-recorder)
  ((last-time :type time-type :initform 0d0
              :documentation "Last state change recorded")
   (fractional :initarg :fractional :initform t
             :documentation "If true display fractional time.")
   (state :type boolean :initform nil :initarg :initial-state
          :documentation "Boolean state - on or off")
   (accumulated-time :type time-type :initform 0d0))
  (:documentation "Rcords the accumulated time when a =boolean= value
  is true. It is assumed that the initial state is false. If
  =:fractional= initialization argument is true the recorder will
  report the statistic as a fraction of total time, otherwise it will
  output the accumulated time for which the state was true."))

(define-result-recorder 'accumulated-time-recorder 'accumulated-time)

(defmethod record((recorder accumulated-time-recorder) time value)
  (with-slots(last-time state accumulated-time) recorder
    (when (and (slot-boundp recorder 'last-time) state)
      (incf accumulated-time (- time last-time)))
    (setf last-time time
          state value)))

(defmethod finish :before ((r accumulated-time-recorder))
  "Take account of last interval"
  (record r (simulation-time) (slot-value r 'state)))

(defmethod recorded-value((r accumulated-time-recorder))
  (with-slots(last-time state accumulated-time fractional) r
    (declare (ignore last-time state))
    (if fractional
        (/ accumulated-time (simulation-time))
        accumulated-time)))



