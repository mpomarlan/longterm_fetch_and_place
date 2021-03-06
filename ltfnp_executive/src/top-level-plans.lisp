;;; Copyright (c) 2016, Jan Winkler <winkler@cs.uni-bremen.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;; * Redistributions of source code must retain the above copyright
;;;   notice, this list of conditions and the following disclaimer.
;;; * Redistributions in binary form must reproduce the above copyright
;;;   notice, this list of conditions and the following disclaimer in the
;;;   documentation and/or other materials provided with the distribution.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :ltfnp-executive)


;;;
;;; Auxiliary Functions
;;;

(defun do-init (simulated &key headless variance)
  (setf *simulated* simulated)
  (cond (*simulated*
         (setf cram-beliefstate::*kinect-topic-rgb* "/head_mount_kinect/rgb/image_raw");;/compressed")
         (setf pr2-manip-pm::*grasp-offset*
               (cl-transforms:make-pose
                (cl-transforms:make-3d-vector -0.14 0.0 0.0)
                (cl-transforms:euler->quaternion :ax (/ pi -2)))))
        (t (setf cram-moveit::*needs-ft-fix* t)
           (setf cram-beliefstate::*kinect-topic-rgb* "/kinect_head/rgb/image_color")))
  (roslisp:ros-info (ltfnp) "Connecting to ROS")
  (roslisp-utilities:startup-ros)
  (prepare-settings :simulated simulated :headless headless :variance variance)
  (roslisp:ros-info (ltfnp) "Putting the PR2 into defined start state")
  (move-arms-up)
  (move-torso))


;;;
;;; Entry Point
;;;

(defun start-scenario (&key (simulated t) (logged nil) skip-init headless (variance "{}"))
  ;; This function is mainly meant as an entry point for external
  ;; runner scripts (for starting the scenario using launch files,
  ;; etc.)
  (let ((variance (yason:parse variance)))
    (beliefstate:enable-logging nil)
    (unless skip-init
      (do-init simulated :headless headless :variance variance))
    (roslisp:ros-info (ltfnp) "Running Longterm Fetch and Place")
    (roslisp:ros-info (ltfnp) "Using variance: ~a" variance)
    (beliefstate:enable-logging logged)
    (setf beliefstate::*enable-prolog-logging* logged)
    (prog1
        (longterm-fetch-and-place :variance variance)
      (when logged
        (beliefstate:extract-files))
      (roslisp:ros-info (ltfnp) "Done with LTFnP"))))


;;;
;;; Top-Level Plans
;;;

(def-top-level-cram-function longterm-fetch-and-place (&key variance)
  (roslisp:ros-info (ltfnp) "Preparation complete, beginning actual scenario")
  (cond (*simulated*
         (roslisp:ros-info (ltfnp) "Environment: Simulated")
         (with-process-modules-simulated
           (fetch-and-place-instance :variance variance)))
        (t
         (roslisp:ros-info (ltfnp) "Environment: Real-World")
         (with-process-modules
           (fetch-and-place-instance :variance variance)))))

(defun make-object-location-goal (name &rest objects+locations)
  (make-instance
   'goal
   :name name
   :preconditions
   (mapcar (lambda (object+location)
             (destructuring-bind (object location) object+location
               `(:object-location ,(make-designator
                                    :object
                                    (enrich-description object))
                                  ,location)))
           objects+locations)))

(defun merge-goals (&rest rest)
  (let* ((names (loop for goal in rest
                      as name = (slot-value goal 'name)
                      collect name))
         (preconditions
           (loop for goal in rest
                 as precondition = (slot-value goal 'preconditions)
                 append precondition))
         (all-merged (reduce (lambda (s0 s1)
                               (concatenate 'string s0 "," s1))
                             names))
         (merged-name
           (concatenate 'string "merged(" all-merged ")")))
    (make-instance
     'goal
     :name merged-name
     :preconditions preconditions)))

(def-cram-function fetch-and-place-instance (&key variance)
  ;; TODO(winkler): Use the variance here to parameterize the
  ;; scenario.
  (let* ((target-table "iai_kitchen_meal_table_counter_top")
         (goal
           (merge-goals
            ;; (make-object-location-goal
            ;;  "fetch-fork"
            ;;  `(((:name "Fork")
            ;;     (:at ,(make-designator
            ;;            :location
            ;;            `((:in "Drawer")
            ;;              (:name "iai_kitchen_sink_area_left_upper_drawer_main")
            ;;              (:handle
            ;;               ,(make-designator
            ;;                 :object
            ;;                 `((:name "drawer_sinkblock_upper_handle")))))))
            ;;     (:location "drawer_sinkblock_upper"))
            ;;    ,(make-designator
            ;;      :location
            ;;      `((:on "CounterTop")
            ;;        (:name "iai_kitchen_meal_table_counter_top")))))
            
            ;; (make-fixed-tabletop-goal
            ;;  `(("RedMetalPlate" ,(tf:make-pose-stamped
            ;;                       "map" 0.0
            ;;                       (tf:make-3d-vector -1.35 -0.90 0.75)
            ;;                       (tf:euler->quaternion)))
            ;;    ("RedMetalCup" ,(tf:make-pose-stamped
            ;;                     "map" 0.0
            ;;                     (tf:make-3d-vector -1.55 -1.05 0.73)
            ;;                     (tf:euler->quaternion))))
            ;;  "iai_kitchen_sink_area_counter_top")
            (make-fixed-tabletop-goal
             `(("RedMetalPlate" ,(tf:make-pose-stamped
                                  "map" 0.0
                                  (tf:make-3d-vector -0.75 -0.90 0.75)
                                  (tf:euler->quaternion)))
               ("RedMetalCup" ,(tf:make-pose-stamped
                                "map" 0.0
                                (tf:make-3d-vector -0.95 -1.05 0.73)
                                (tf:euler->quaternion))))
             "iai_kitchen_sink_area_counter_top")
            ))
         (the-plan (plan (make-empty-state) goal)))
    (spawn-goal-objects goal target-table)
    (roslisp:ros-info (ltfnp) "The plan has ~a step(s)"
                      (length the-plan))
    (dolist (action the-plan)
      (destructuring-bind (type &rest rest) action
        (ecase type
          (:fetch
           (catch-all "fetch"
             (destructuring-bind (object) rest
               (with-designators ((fetch-action :action
                                                `((:to :fetch)
                                                  (:obj ,object))))
                 (perform fetch-action)))))
          (:place
           (catch-all "place"
             (destructuring-bind (object location) rest
               (with-designators ((place-action :action
                                                `((:to :place)
                                                  (:obj ,object)
                                                  (:at ,location))))
                 (go-to-origin :keep-orientation t)
                 (perform place-action))))))))))
