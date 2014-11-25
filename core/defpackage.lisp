;; Core Package Definitions
;; Copyright (C) 2013-2014 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;;; Copying:

;; This file is part of Lisp Educational Network Simulator (LENS)

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

;; All the public protocol interfaces should be exported appear here so
;; they can easily be imported into the packages for specific networks.

;;; Code:

(in-package :cl-user)

(defpackage :lens
  (:documentation "This package provides the main simulation
  framework. It is intended that every simulation system will be
  defined in its own package which will use this package to import the
  public API. Simulations should be run from within the dynamic
  context of their specific simulation package so that symbolic
  configuration parameters will be read into the correct package.

Simulations are represented as a heirarchical network of
modules interconnected using channels. Every simulation must have one
top level network module which will specify submodules and their
interconnections. These submodules may be compound modules which can
contain further submodules or simple modules which contain
implementations. All module types are declared as CLOS classes
inheriting from [[network]], [[compound-module]] and
[[module]] base classes as appropriate. In addition module classes
must declare a metaclass - [[compound-module-class]] for
networks and compound modules and [[module-class]] for simple
modules. These meta-classes allow for the declaration of parameter
slots (where the value may be initialised from the configuration
file), gates, submodules and connections in the class definition.
When a simulation is run the network type is read from the parameter
file and created. This will then create the submodules and so on until
the whole network is created.")
  (:nicknames :lisp-educational-network-simulator)
  (:use :closer-common-lisp :closer-common-lisp-user :data-format-validation)
  (:import-from :alg
                 #:enqueue #:dequeue #:make-binary-heap #:empty-p #:size
                 #:peek #:make-queue #:back)
  (:shadow duration)
  (:export

   ;; common
   #:coord #:make-coord #:coord-x #:coord-y #:coord-z
   #:coord+ #:coord- #:coord* #:coord-op #:distance
   #:while #:until #:filter #:for #:copy-slots #:set-slots #:reinitialise-slots
   #:range-getf #:range-list-p
   #:queue #:make-queue #:enqueue #:dequeue #:peek #:back #:average-queue-time #:size
   #:timestamped-queue #:packet-buffer
   #:buffer-size #:buffer-size-bytes #:empty-p
   #:history-buffer #:duplicate-p

   ;; common object
   #:+c+ #:*context* #:simulation-condition #:name #:owner
   #:named-object #:owned-object #:index #:parent-module #:full-name #:full-path
   #:for-each-child #:info #:detailed-info #:duplicate #:serialise #:find-object
   #:property-union #:initialize #:initialized-p #:finish

   ;; parameters and configuration
   #:read-configuration #:format-from-type #:read-parameter
   #:parameter-class #:parameter-object #:configure #:number-or-expression

   ;; simulation kernel
   #:*simulation* #:*simulation-init-hooks* #:*time-format* #:time-type #:sec
   #:configuration #:simulation #:network #:sim-time-limit #:cpu-time-limit
   #:simulation-time #:schedule #:scheduled-p #:cancel #:stop
   #:run-simulations
   #:sent-time #:arrival-time
   #:root-event #:*simulation-trace-stream* #:tracelog
   #:timestamped #:timestamped-time #:timestamped-value #:latency
   ;; signals and listeners
   #:register-signal #:signal-id #:receive-signal #:entity-with-signals
   #:listeners #:may-have-listeners #:has-listeners #:emit
   #:subscribe #:unsubscribe  #:subscribed-p #:repair-signal-flags

   ;; common signals
   #:pre-model-change #:post-model-change #:message-sent #:message-discarded
   #:drop #:buffer-length #:buffer-time

  ;; components: modules,gates and channels
   #:gate #:gate-direction #:gate-slot #:input #:output #:gate-extend
   #:gate-size #:size #:end-module
   #:gate-type #:path-start-gate #:path-end-gate #:connect #:disconnect
   #:deliver #:connected-p #:connected-outside-p #:connect-inside-p
   #:deliver-on-reception-start-p #:busy-p
   #:channel #:transmission-channel #:ideal-channel #:channel-result
   #:process-message #:nominal-datarate #:calculate-duration
   #:transmission-finish-time #:delay-channel #:delay #:disabled-p
   #:message-sent-signal-value #:message-sent-signal-value-timestamp
   #:message-sent-signal-value-message #:message-sent-signal-value-result
   #:component #:module-class #:module #:compound-module-class #:compound-module
   #:build-gates #:build-submodules #:build-connections #:build-inside
   #:arrived #:for-each-gate #:for-each-submodule #:for-each-channel
   #:submodule #:schedule-at #:send #:send-direct #:<= #:=> #:<=>

   ;; RNG
   #:uint #:rand #:urandom #:mt-random-state #:seed #:rng-map
   #:uniform #:exponential #:normal #:lognormal #:truncnormal #:gamma-d #:beta
   #:erlang-k
   #:chi-square #:student-t #:cauchy #:triang #:weibull #:pareto-shifted
   #:intuniform #:bernoulli #:binomial #:geometric #:negbinomial #:poisson
   #:do-histogram

   ;; model change notifications
   #:module-add-notification #:module-delete-notification
   #:module-reparent-notification #:gate-add-notification
   #:gate-delete-notification #:gate-vector-resize-notification
   #:gate-connect-notification #:gate-disconnect-notification
   #:path-create-notification #:path-cut-notification
   #:parameter-change-notification

   ;; messages and packets
   #:message #:creation-time #:to-gate #:from-gate #:to-module #:from-module
   #:timestamp #:handle-message #:send-message #:self-message-p
   #:packet #:bit-length #:byte-length
   #:duration #:control-info #:bit-error-p #:header-specification
   #:unknown-message #:encapsulate #:decapsulate

   ;; timers
   #:with-timers #:timer-message #:timer #:set-timer #:cancel-timer
   #:handle-timer

   ;; statistics layer
   #:define-statistic-filter #:define-result-recorder #:record #:report
   #:title
   #:sum #:mean #:constant0 #:constant1 #:last-value #:stddev #:timeavg
   #:time-average-recorder #:stddev-recorder #:histogram
   #:indexed-count-recorder #:indexed-count #:accumulated-time
   #:probability-density-function #:cumulative-density-function
))


