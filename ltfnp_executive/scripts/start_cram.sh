#!/usr/bin/env sh
"true"; exec /usr/bin/env /usr/bin/sbcl --noinform --end-runtime-options --noprint --no-userinit --disable-debugger --script "$0" "$@"


(REQUIRE :ASDF)

(load "/opt/ros/indigo/share/common-lisp/source/slime/swank-loader.lisp")
(swank-loader:init)


(labels ((get-roslisp-path ()
           ;; calls rospack to find path to roslisp
           (let ((rospack-process
                   (run-program "rospack" '("find" "roslisp")
                                :search t
                                :output :stream)))
             (when rospack-process
               (unwind-protect
                    (with-open-stream (o (process-output rospack-process))
                      (concatenate 'string (car (loop
                                                  for line := (read-line o nil nil)
                                                  while line
                                                  collect line)) "/load-manifest/"))
                 (process-close rospack-process)))))
         (load-ros-lookup ()
           ;; make sure roslisp is in asdf central registry
           (PUSH (get-roslisp-path) ASDF:*CENTRAL-REGISTRY*)
           ;; load ros-load-manifest, defining e.g. "ros-load:load-system"
           (ASDF:OPERATE 'ASDF:LOAD-OP :ROS-LOAD-MANIFEST :VERBOSE NIL)))
  (load-ros-lookup))


(PUSH :ROSLISP-STANDALONE-EXECUTABLE *FEATURES*)


(ros-load:load-system "roslisp" "roslisp")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          Here, the actual executive code begins.          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; Make sure the ltfnp package is loaded
(roslisp:ros-info (ltfnp-aux) "Loading Longterm Fetch and Place scenario.")
(ros-load:load-system "ltfnp_executive" "ltfnp-executive")
(roslisp:ros-info (ltfnp-aux) "Longterm Fetch and Place scenario loaded.")

;; Change into the package namespace
(swank:set-package "LTFNP")

;; Start the cram server, waiting for PRAC requests
(roslisp:ros-info (ltfnp-aux) "Let's go!")
(start-cram :logged t)