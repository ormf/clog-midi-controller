;;;
;;; faderfox-gui.lisp
;;;
;;; faderfox-gui besteht aus einer Gui Instanz (faderfox-gui) und
;;; einem Controller (faderfox-midi), der eine spezielle Klasse eines
;;; midicontrollers ist (definiert in cl-midictl).
;;; 
;;; faderfox-gui ist eine Klasse, die die Gui Instanz und den
;;; Hardware Controller zusammenfasst (faderfox-gui existiert nur der
;;; Vollständigkeit halber, falls der unwahrscheinliche Fall auftritt,
;;; dass man ein Gui ohne HardwareController verwenden möchte). Da es
;;; mehrere Gui Instanzen geben kann, die alle auf die selbe
;;; Controller Instanz bezogen sind, ist der Controller ein Slot der
;;; Gui Instanz von (faderfox-gui) und muss bei make-instance der
;;; Gui Instanz übergeben werden (wird im on-new-window Code
;;; gemacht). Im Controller sind model-slots, deren set-cell
;;; Funktionen alle Slots im gui updaten.
;;;
;;; Um mangels Motorfadern/Endlosreglern bei Controllern, wie dem
;;; NanoKontrol2 Werte "fangen zu können", um Wertesprünge zu
;;; vermeiden, gibt es cl-midictl:*midi-cc-state*, der immer den
;;; aktuellen Stand der HardwareFader/knobs enthält (der responder
;;; dafür wird automatisch gestartet). *midi-cc-state* enthält keine
;;; model-slots, da die Werte einfach nur gesetzt werden, wenn der
;;; Fader bewegt wird, ansonsten aber nur gelesen werden müssen, wenn
;;; das gui mit den HardwareControllern verglichen werden soll.
;;;
;;; Das konkrete Verhalten des Controllers ist in handle-midi-in der
;;; Controller Klasse (faderfox-midi) geregelt und besteht nur darin,
;;; den Wert des jeweiligen model-slots zu aktualisieren (wenn der
;;; Wert "gefangen" ist).
;;;
;;; Bei Instantiierung des Gui Instanz (initialize-instance :after)
;;; werden an die model-slots der Controller Instanz set-cell-hooks
;;; gebunden, die alle existierenden Gui Referenzen updaten.
;;;
;;; **********************************************************************
;;; Copyright (c) 2023 Orm Finnendahl <orm.finnendahl@selma.hfmdk-frankfurt.de>
;;;
;;; Revision history: See git repository.
;;;
;;; This program is free software; you can redistribute it and/or
;;; modify it under the terms of the Gnu Public License, version 2 or
;;; later. See https://www.gnu.org/licenses/gpl-2.0.html for the text
;;; of this agreement.
;;; 
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;;; GNU General Public License for more details.
;;;
;;; **********************************************************************

(in-package :cl-midictl)

(defclass faderfox-midi (midi-controller)
  ((curr-player :initform 0 :type (integer 0 3) :accessor curr-player)
   (cc-nums :accessor cc-nums)
   (ff-faders :accessor ff-faders)
   (ff-buttons :accessor ff-buttons)))

(defun handle-player-switch (instance button-idx)
  (incudine.util:msg :info "handle-player-switch: ~a" button-idx)
  (with-slots (ff-buttons curr-player) instance
    (setf (val (aref ff-buttons curr-player)) 0)
    (setf curr-player button-idx)
    (setf (val (aref ff-buttons curr-player)) 127)))

(defmethod handle-midi-in ((instance faderfox-midi) opcode d1 d2)
  (with-slots (cc-fns cc-nums ff-fader-update-fns echo
               cc-map cc-state note-state note-fn last-note-on midi-output chan)
      instance
    (case opcode
      (:cc (incudine.util:msg :info "ccin: ~a ~a" d1 d2)
       (cond
         ((< (aref cc-map d1) 16)
          (let* ((fader-idx (aref cc-map d1))
                 (fader-slot (aref cc-state fader-idx))
                 (old-value (val fader-slot))
                 (new-value (max 0 (min 127 (+ old-value (midi-delta->i d2))))))
            (incudine.util:msg :info "old-value: ~a, new-value: ~a" old-value new-value)
            (when (/= old-value new-value)
              (setf (val fader-slot) new-value)
              (when echo (osc-midi-write-short midi-output (+ chan 176) d1 new-value)))))))
      (:note-on (incudine.util:msg :info "notein: ~a ~a" d1 d2)
       (let ((button-idx (aref cc-map d1)))
         (cond ((and (< 3 button-idx 16) (= d2 127))
                (let ((button-slot (aref note-state button-idx)))
                  (toggle-slot button-slot)))
               ((and (< button-idx 4) (= d2 127))
                (handle-player-switch instance button-idx))))))))

(in-package :clog-midi-controller)

(defclass faderfox-gui (clog-midi-controller)
  ((gui-parent :initarg :gui-parent :accessor gui-parent)
   (gui-container :initarg :gui-container :accessor gui-container)
   (gui-fader :initarg :gui-fader :accessor gui-fader)
   (gui-buttons :initarg :gui-buttons :accessor gui-buttons)
   (gui-ctl-panel :initarg :gui-ctl-panel :accessor gui-ctl-panel)
   (ctl-panel-vis :initform t :initarg :ctl-panel-vis :accessor ctl-panel-vis)))

(defmacro trigger-fn (slot)
  `(lambda (src) (trigger ,slot src)))

(defmethod initialize-instance :after ((instance faderfox-gui) &rest args)
  (declare (ignorable args))
  (with-slots (connection-hash-key midi-controller
               gui-parent gui-container
               gui-fader gui-buttons
               gui-ctl-panel
               )
      instance
    (unless gui-parent (error "faderfox-gui initialized without parent supplied!"))
    (with-connection-cache (gui-parent)
      (setf gui-container (create-div gui-parent
                                      :css '(:display flex
                                             :flex-wrap wrap
;;;                                             :justify-content "space-between"
                                             :flex "0 0 auto"
                                             :margin-right 15px
                                             :padding-bottom 30px)))
      (let (fader-panel button-panel
            fader-subpanel button-subpanel
            (gui-btn-css '(:width 50px :height 15px :font-size 10px :margin 2px)))
        (setf fader-panel (create-div gui-container :css '(:width 220px
                                                           :height 80px
                                                           :display "flex"
                                                           :flex-direction "column"
                                                           :justify-content "flex-end"
                                                           :max-width 220px
                                                           :max-height 80px)))
        (setf fader-subpanel (create-div fader-panel :css '(:width "100%" :height 65px
                                                            :display "grid"
                                                            :grid-template-columns "1fr 1fr 1fr 1fr"
                                                            :grid-template-rows "1fr 1fr 1fr 1fr"
                                                            :gap 0px ;
                                                            :padding 10px
                                                            :justify-content "space-around"
                                                            :align-content "space-around")))
        (setf button-panel (create-div gui-container :css '(:width 220px
                                                            :height 80px
                                                            :display "flex"
                                                            :flex-direction "column"
                                                            :justify-content "flex-end"
                                                            :max-width 220px
                                                            :max-height 80px)))
        (setf button-subpanel (create-div button-panel :css '(:width "100%" :height 65px
                                                              :display "grid"
                                                              :grid-template-columns "1fr 1fr 1fr 1fr"
                                                              :grid-template-rows "1fr 1fr 1fr 1fr"
                                                              :gap 0px ;
                                                              :padding 10px
                                                              :justify-content "space-around"
                                                              :align-content "space-around")))
        (setf gui-fader
              (coerce
               (v-collect
                   (n 16)
                   (numbox
                    fader-subpanel
                    :min 0 :max 127 :size 10 :css '(:background "#cccccc" :margin 2px)
                    :val-change-cb
                    (let ((n n))
                      (lambda (v obj)
                        (declare (ignore obj))
                        (let ((new-value (read-from-string v)))
                          (setf (val (aref (ff-faders midi-controller) n)) new-value))))))
               'vector))
        (setf gui-buttons
              (coerce
               (v-collect (n 16)
                          (toggle
                           button-subpanel
                           :background '("gray" "#ff8888")
                           :label (1+ n)
                           :css gui-btn-css
                           :val-change-cb
                           (let* ((n n)
                                  (keynum (aref (cc-nums midi-controller) n)))
                             (lambda (v obj) (declare (ignore obj v))
                               (incudine.util:msg :info "keynum: ~a" keynum)
                               (cl-midictl:handle-midi-in midi-controller :note-on keynum 127)))))
               'vector))))
    
    (with-slots (ff-faders ff-buttons chan midi-output cc-nums echo) midi-controller
      (setf echo nil)
      (dotimes (i 16) ;;; rotaries and buttons
        (let ((i i)
              (connection-hash-key connection-hash-key))
          (setf (ref-set-hook (aref ff-faders i))
                (lambda (val) 
                  (osc-midi-write-short midi-output (+ chan 176) (aref cc-nums i) (round val))
                  (maphash (lambda (connection-id connection-hash)
                             (declare (ignore connection-id))
                             (let* ((ff-gui (gethash connection-hash-key connection-hash)))
                               (when ff-gui
                                 (let ((elem (aref (gui-fader ff-gui) i)))
                                   (setf (clog:value elem) val)))
                               ))
                           clog-connection::*connection-data*)))
          (setf (ref-set-hook (aref ff-buttons i))
                (lambda (val) 
                  (maphash (lambda (connection-id connection-hash)
                             (declare (ignore connection-id))
                             (let* ((ff-gui (gethash connection-hash-key connection-hash)))
                               (when ff-gui
                                 (let ((elem (aref (gui-buttons ff-gui) i)))
                                   (setf (clog:value elem) val)))))
                           clog-connection::*connection-data*)))
          )))
    (update-gui-state instance)))

(defmethod update-gui-state ((gui faderfox-gui))
  (with-slots (midi-controller gui-fader gui-buttons) gui
    (with-slots (cc-nums cc-state note-state chan) midi-controller
      (dotimes (i 16)
        (let ((numbox (aref gui-fader i))
              (button (aref gui-buttons i))
              (fader-value (val (aref cc-state i)))
              (button-state (val (aref note-state i))))
          (setf (clog:value numbox) fader-value)
          (clog-dsp-widgets:highlight button button-state))))))

;;; (add-midi-controller 'faderfox-gui :id :ff01 :chan 5)

;;; (find-controller :ff01)
