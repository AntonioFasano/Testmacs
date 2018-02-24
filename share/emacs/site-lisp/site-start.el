;;; Testmacs --- Administer classroom tests over a LAN -*- lexical-binding: t -*-

;; ----->  Copy this in share\emacs\site-lisp\site-start.el

;; Author: Antonio Fasano
;; Version: 0.3
;; Keywords: exam, quiz, test, forms, widget
;; Package-Requires: ((cl-lib "0.5") (emacs "25"))

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation, either version 3 of the License, or (at your
;; option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
;; Public License for more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Testmacs implements a simple multiple-choice test.
;; The test header lines ask for test ID and student details.
;; Questions are without question-text like: Question N; a), b) c) ... I do not know.
;; The student is given a separate paper-sheet with a test ID and the question text.
;; The test shows a mode line with answered questions and a countdown in minutes.
;; At countdown expiration Emacs exits, saving answers.
;; At predefined times (10 seconds) the answers are saved locally and remotely.
;;
;; Answers are stored locally in the parent of `exam-loc-server-ini' and remotely in `exam-net-course-pt'.  
;; To find the remote share, the file retrived from `exam-loc-server-ini' is used.
;; Emacs performs some actions if detects predefined command filenames in the
;;   remote directory `exam-net-data-pt`. See action for each command filename.
;; Command filename "exit007": Emacs will exit in 10 seconds.
;; Command filename "update007": Emacs updates `site-start.el' with the file `new-site-start.txt'
;; in the remote directory `exam-net-data-pt`. If this file is not found or there is a copy error
;; a non-critical error is displayed until the action succeeds or the command filename is removed.

;; Inspirations
;; https://github.com/syohex/emacs-mode-line-timer
;; https://github.com/davep/quiz.el

;;; Code:

(require 'cl-lib)
(require 'widget)
(require 'wid-edit)


;;; ==================== ;;;
;;; === Customise Me === ;;;
;;; ==================== ;;;

(defconst exam-version  "0.3"
  "Current app version.")

(defconst exam-loc-server-ini  "~/server*.txt"
  "Local file whose first line has the path of the remote used by the variable `exam-net-data-pt'.
Note that the \"~\" is redirected by the Testemacs launcher to a subdirectory of the Testemacs package named \"data\". If the variable has wildcards, the first valid server path is used. See `set-server-share' for more.")

(defconst exam-net-init "INITFILE*.txt"
  "File name in the remoted share with values for `exam-max-time', and `quest-count' and `exam-course'.
If the variable has wildcards, the first path found is used.")

(defconst exam-buffer-name "*Test*"
  "Name of the test buffer.")

(defconst exam-update-freq 10
  "Frequency of updates in seconds for countdown or saving.")

(defconst exam-no-answer-string "I do not answer."
  "Default value in case of missing answer.")

;;; === end of Customise Me
;;; =======================

;;; =================== ;;;
;;; === Global Vars === ;;;
;;; =================== ;;;

;;; We want global vars to work even if the buffer is not local
(defvar exam-net-ans-file-pt  nil
  "Path of remote answer file.")

(defvar exam-loc-ans-file-pt  nil
  "Path of client local answer file.")

(defvar exam-net-data-pt nil
  "Path of the remote share containing program data (answers, init and command files etc.). 
The path is read from a local server file identified by `exam-loc-server-ini'. If this variable is a wildcard and more server files are identified, the first valid path is used.")

(defvar exam-ans-string nil
  "Stores all editable field values. It is updated whenever a field is.")

(defvar exam-remaining-secs nil
  "Current countdown value in seconds as a number.")

(defvar exam-cmd-cache nil
  "Used for storing remote commands.")

(defvar exam-cmd-update-performed nil
  "Non-nil if an update has been performed from the remote data dir.")

(defvar exam-running-id  nil
  "Random number used written in `exam-running-cookie-pt' to detect multiple local app instances.")

(defvar exam-running-cookie-pt  nil
  "Path of client cookie with random `exam-running-id'. Used to detect multiple local app instances.")

(defvar exam-scheduler nil
  "Timer object to run scheduled tasks in `exam-schedule-hook' every `exam-update-freq'.
To be used in case one needs to cancel timer.")

(defvar exam-scheduler-wait nil
  "Non-nil if the user is prompted  with a question. In this case some tasks in `exam-schedule-hook' might be postpones, until the user complete the answer.")


;;; Buffer local vars used during the init phase or on click events
;;; ---------------------------------------------------------------

(defvar-local exam-net-course-pt nil
  "Path of course related net folder inside `exam-net-data-pt'.")

(defvar-local exam-answered-ones  nil
  "Total answered questions.")

(defvar-local exam-max-time nil
  "Maximum allowed time in minutes for entering answers. Retrieved from `exam-net-init' file.")

(defvar-local quest-count nil
  "Number of available questions. Retrieved from `exam-net-init' file.")

(defvar-local exam-course nil
  "Name of the course. Retrieved from `exam-net-init' file.")

(defvar-local answers-given nil
  "Answer vector given by the students.")

(defvar-local given-name nil
  "Student contact.")

(defvar-local family-name nil
  "Student contact.")

(defvar-local student-id nil
  "Student contact.")

;(defvar-local student-birth nil
;  "Student contact.")

(defvar-local exam-date nil
  "Examination day.")

(defvar-local exam-id  nil
  "Test ID to be used to match student answers.")


;;; === end of Global Vars
;;; ======================


;;; ============= ;;;
;;; === Style === ;;;
;;; ============= ;;;
(modify-frame-parameters  nil (quote ((fullscreen . maximized))))
(set-face-attribute 'default  nil :height 146) ; font height
(setq visible-bell t)
(tool-bar-mode -1)
(menu-bar-mode -1)
(defun display-startup-echo-area-message ()
  (message ""))

;;; === end of Style
;;; ================

;;; =================== ;;;
;;; === FS Helpers  === ;;;
;;; =================== ;;;

(defun make-path (path subpath)
  "Concatenate PATH and SUBPATH in order to make a new path. If necessary a trailing slash is added to PATH."
  (concat (file-name-as-directory path) subpath))

(defun file-writable-cross-p (filename)
  "This function works similarly to `file-writable-p' but is compatible with Windows. Therefore it returns nil if another process is blocking write access."  
  
  (if (not (file-exists-p filename))
      (file-writable-p filename)
    (not (condition-case err
	     (rename-file filename filename)        
	   (error err)))))

(defun get-data-dir ()
  "Expand wildcards in `exam-loc-server-ini' and use the first expanded path as a server configuration file. 
The first line of the conf file contains the Windows UNC path of the remote datadir, e.g.: 
\"\\\\server-name\\path-to\\data-dir\". The UNC path should be written in Windows style, without escaping backslashes. If wildcard expansion gives no file or the UNC path is nonexistent, throw an error, otherwise return UNC path."

  (let (serverp data-dir
	(loc-files (file-expand-wildcards exam-loc-server-ini)))
    (dolist (s loc-files)
      (when (not serverp)
	(setq data-dir
	      (car (split-string
		    (with-temp-buffer (insert-file-contents s) (buffer-string))
		    "\n"))
	      serverp (file-exists-p data-dir))))

    (when (not loc-files)
      (exam-err "File(s) `%s' not found." exam-loc-server-ini)
      (throw 'test t))
	
    (when (not serverp)
      (exam-err "No valid server/share in files %s" (mapconcat 'identity loc-files ", "))
      (throw 'test t))
    data-dir))


(defun set-running-id ()
  "Assign random value to `exam-running-id' and set cookie path."

  (setq exam-running-cookie-pt
	(make-path (file-name-directory exam-loc-server-ini) "RUNNING"))	
  (let (id)  
    (dotimes (x 3 id)
      (setq id (cons (random 999999) id)))
    (setq exam-running-id (mapconcat 'number-to-string id "-"))))

(defun single-instance-init ()
  "On startup sequence, detect running instances if `exam-running-cookie-pt' cookie is found.
If none detected write the random `exam-running-id' to cookie periodic detection."

  (cond
   
   ;; A local cookie exists
   ((file-exists-p  exam-running-cookie-pt)
    (let ((ans (exam-choice 3 
     "A local cookie exists. 
A previous app instance was not closed properly or a concurrent app instance is running.\n
Select an option:
1 Exit this instance and remove cookie
2 Continue overwriting the cookie.
3 Exit this instance and do NOT remove cookie.\n
Please type your option below ↓")))
	  
      ;; Manage selection
      ;; 1
      (when (string= ans "1")
	(if (delete-cookie)
	    (kill-emacs)
	  (throw 'test t)))
      ;; 2
      ;; do nothing      
      ;; 3
      (if (string= ans "3") (kill-emacs))))
      
    ;; Test access to local cookie  
   ((not (file-writable-cross-p  exam-running-cookie-pt))    
    (exam-err-cookie "Unable to write to local file `%s.'" exam-running-cookie-pt)
    (throw 'test t)))

  ;; If no concurrency detected, write random running-id used for periodic detection
  (with-temp-file exam-running-cookie-pt  (insert exam-running-id)))

(defun single-instance-update ()
  "On scheduled hook, if the cookie file is externally deleted, restore it; if its value does not match `exam-running-id', raise a concurrency error."

  ;; Restore if missing
  ;; use again file-writable-cross-p ?
  (unless (file-exists-p exam-running-cookie-pt)
    (with-temp-file exam-running-cookie-pt  (insert exam-running-id)))
  
  ;; Read cookie value
  (let (ans (id (with-temp-buffer
		  (insert-file-contents exam-running-cookie-pt)
		  (buffer-string))))

    ;; On mismatch raise error
    (unless (string= id exam-running-id)
      (setq exam-scheduler-wait t)
      (setq ans (exam-choice 3 "Local cookie mismatch. A concurrent app is running.\n
Select an option:
1 Exit this instance and remove cookie
2 Continue overwriting the cookie.
3 Exit this instance and do NOT remove cookie.\n
Note: To restart the app remove the answer file on the server.\n
Please type your option below ↓"))

      ;; Manage selection
      ;; 1
      (if (and (string= ans "1") (delete-cookie))
	  (kill-emacs))
      ;; 2
      ;; do nothing      
      ;; 3
      (if (string= ans "3") (kill-emacs)))
        (setq exam-scheduler-wait nil))

    (with-temp-file exam-running-cookie-pt  (insert exam-running-id)))
      
(defun delete-cookie ()
  "Safe delete `exam-running-cookie-pt' cookie"

  ;; Delete cookie and test result
  (if (file-exists-p exam-running-cookie-pt)
      (delete-file exam-running-cookie-pt))
  (let ((removed (not (file-exists-p  exam-running-cookie-pt))))
    (unless removed (exam-err-cookie "I am unable to delete the cookie `%s'. Try to do it manually."
				     exam-running-cookie-pt))
    removed))





;;; === end of FS Helpers
;;; =====================



;;; ======================== ;;;
;;; === Widget Functions === ;;;
;;; ======================== ;;;

(defun exam-process-contacts (widget contact-var)
  "On updated contact field hook."
  (set contact-var (widget-value widget))
  (exam-make-answer-string))

(defun exam-process-answer (widget ith-quest)
  "On click answer hook."
  (let* ((ans (widget-value widget))
	 (ans-no-nil (if ans ans exam-no-answer-string)))
    (message "You clicked \"%s\"." ans-no-nil)
    (aset answers-given (1- ith-quest) ans))
  (setq exam-answered-ones (length (remove nil answers-given)))
  (exam-make-answer-string))

(defvar exam-mode-map
  (let ((map widget-keymap))
;    (suppress-keymap map t)
    (define-key map " " 'widget-button-press)
    (define-key map (kbd "C-x") 'do-nothing)
    (define-key map (kbd "C-c") 'do-nothing)
    map)
  "Local keymap for `test'.")

(defun do-nothing ()
  "Do nothing. Used to disable some key bindings."
  (interactive))

;;; === end of Widget Functions
;;; ===========================


;;; ================== ;;;
;;; === Stop Hooks === ;;;
;;; ================== ;;;

(defun exam-exit-ahead (&rest _)
  "Called by widget to query user to exit ahead of time.
In case of confirmation save form and exit."

  ;; The funct below is used to create an experience similar to C-x C-c
  ;; It will trigger related kill-emacs-query-functions
  (save-buffers-kill-terminal))

(defun exam-exit-hook ()
  "Hook called whenerever users asks to exit"
  (exam-save-test)
  (let ((yes (y-or-n-p "Are you **absolutely sure** you want to finish your test now?")))
    (if yes (delete-cookie))
    yes))

(defun exam-exit-forced ()
  "Save answer string and exit. Dangerous for debugging, since unsaved material is lost!."
  (exam-save-test)
  (delete-cookie)
  (kill-emacs))

(defsubst exam-schedule-hook ()
  "Maintenance tasks run at form setup and every subsequent `exam-update-freq' seconds.
A) Decrement `exam-remaining-secs' by the value in `exam-update-freq' and force headeline update.
B) Save answer string locally and remote. C) Check for concurrent instance of the exam app.
D) Check for remote commands.

Note that variables used here shoul not be buffer local."

  ;; Exit when time is over
  (if (< exam-remaining-secs 0) (exam-exit-forced))

  ;; Or update countdown
  (setq exam-remaining-secs  (- exam-remaining-secs exam-update-freq))
  (force-mode-line-update t)

  ;;Test for single instance
  (single-instance-update)
  
  ;; Save answers-given
  (exam-save-test))

(defun exam-save-test ()
  "Save answer string. Note that variables used here are not buffer local.
Note that variables used here are not buffer local."
  
  (with-temp-file exam-loc-ans-file-pt  (insert exam-ans-string))
  (with-temp-file exam-net-ans-file-pt  (insert exam-ans-string)))

(defun exam-remote-cmds ()
  "Execute remote commands."
  
  ;; Manage remote exit command
  (when (string= exam-cmd-cache "exit007")
    (delete-cookie)
    (kill-emacs)) 
  (when (file-exists-p (make-path exam-net-data-pt  "exit007"))
    (setq exam-cmd-cache "exit007")
    (message "Exit in 10 seconds"))

  ;; Manage remote update command
  (if (file-exists-p (make-path exam-net-data-pt  "update007"))
      (remote-update)))

(defun exam-err (str &rest pars)
  "Critical message, involving subsequent user exit. The string STR can be formatted with PARS parameters. 
Remove the cookie, kill hooks and possibly the close answer form and stop its timer, without saving answer files. If necessary, call `exam-save-test' before this."
  (exam-err_ t str pars))

(defun exam-err-cookie (str &rest pars)
  "Like `exam-err' but leaves the cookie."
  (exam-err_ nil str pars))

(defun exam-err_ (remove-cookie str &rest pars)
  "Workhorse for `exam-err' and `exam-err-cookie'. REMOVE-COOKIE is non-nil if cookie is to be removed."
  
  (switch-to-buffer "blank")
  (setq inhibit-read-only t)
  (erase-buffer)
  (insert "Report Issue to the Instructor\n------------------------------\n\n")
  (let ((mess (apply 'format str (car pars))))
    (insert mess))
  (setq inhibit-read-only nil)
  (cleanup)
  (if remove-cookie (delete-cookie)))

(defun exam-choice (choice-count str &rest pars)
  "Prompt user choice with CHOICE-COUNT numeric alternatives. 
The string STR can be formatted with the parameters PARS."
  (save-window-excursion
    (switch-to-buffer "blank")
    (setq inhibit-read-only t)
    (erase-buffer)
    (insert "Report Issue to the Instructor\n------------------------------\n\n")
    (let ((mess (apply 'format str pars)))
      (insert mess))
    (setq inhibit-read-only nil)

    (let ((rgx (format "^[1-%s]$" choice-count)) (ans ""))
	(while (not (string-match-p rgx ans))
	  (setq ans (read-string "Please, type the selected number: ")))
	ans)))



;;; === end of Stop Hooks
;;; =====================


;;; ========================= ;;;
;;; Main Form Setup Functions ;;;
;;; ========================= ;;;

(define-derived-mode exam-mode nil "Test"
  "Major mode for playing `test'.

The key bindings for `exam-mode' are:

\\{exam-mode-map}"

  (define-key widget-field-keymap (kbd "C-x") 'do-nothing)
  (define-key widget-field-keymap (kbd "C-c") 'do-nothing)
  (setq truncate-lines  nil)
  (buffer-disable-undo))

(defun exam-mode-header (max-time)
  "Set the header-line for test mode and initialize countdown timer."

    ;; Set header-line
  (setq header-line-format
	'(:eval
	  (format " Residual minutes: %s | Answered: %d out of %d      Ver. %s"
		  (format "%02d"  (+ (/ exam-remaining-secs 60) 1)) ; countdown as a minute string
		  (buffer-local-value 'exam-answered-ones (get-buffer exam-buffer-name))
		  (buffer-local-value 'quest-count (get-buffer exam-buffer-name))
		  exam-version
		  )))

  ;; Init countdown
  (setq exam-remaining-secs  (* max-time 60))

  ;; Update countdown every exam-update-freq seconds
  (setq exam-scheduler (run-with-timer 0 exam-update-freq 'exam-schedule-hook)))

(defun read-inits ()
  "Obtain remte data-dir from the local file `exam-loc-server-ini' and read there init values from `exam-net-init' file. Wildcards are expanded, if any,  and the first (valid) path is used."

  ;; Set server paths local init file 
  (setq exam-net-data-pt (get-data-dir))   

  ;; Set remote init file
  (let*  (init-file-pt txt ans-file-name)
   
    ;; Take the first expanded path 
    (setq init-file-pt
	  (car 
	   (file-expand-wildcards
	    (make-path exam-net-data-pt exam-net-init))))
    
    (when (not init-file-pt)
      (exam-err "No file matching `%s'."  (make-path exam-net-data-pt exam-net-init))
      (throw 'test t))
    
    ;; Read init file vars
    (setq txt
	  (split-string
	   (with-temp-buffer
	     (insert-file-contents init-file-pt)
	     (buffer-string)) "\n")
	  txt (mapcar 'split-string  (butlast txt))
	  txt (cl-pairlis (car txt) (cadr txt))

	  exam-max-time
	  (string-to-number (cdr (assoc "time" txt)))
	  quest-count
	  (string-to-number (cdr (assoc "questcount" txt)))
	  exam-course  (cdr (assoc "course" txt))
	  exam-net-course-pt
	  (make-path exam-net-data-pt (concat exam-course "-answers"))
	  ans-file-name (concat exam-course "-ans-" (downcase (getenv "COMPUTERNAME")) ".txt")	  
	  exam-net-ans-file-pt (make-path exam-net-course-pt ans-file-name)
	  exam-loc-ans-file-pt (make-path (file-name-directory exam-loc-server-ini) ans-file-name))))

(defun exam-make-answer-string ()
  "When a field is updaded this syncs `exam-ans-string' with contacts and  answers."
  (let ((ans-string
	 (format "ans-string:%s" (replace-regexp-in-string  "[][]" "" (prin1-to-string answers-given))))
	 (contacts
	  (apply 'concat (mapcar  ;; removed student-birth
			  (lambda (elt) (format "%s:%s\n" (symbol-name elt) (symbol-value elt)))
			  '(given-name family-name student-id  exam-date exam-id)))))    
    (setq exam-ans-string
	  (concat contacts ans-string "\nsaved-at:" (format-time-string "%Y-%m-%d %H:%M:%S")))))


(defun exam-make-dirs ()
  "Make remote course dir in `exam-net-data-pt' and test for local and remote write access. If remote answer file `ans-file-name' exits, throw an error. If remote course dir exists (possibly with some answer files), prompt to proceed."

  ;; Test access to remote data dir
  (when (not (file-accessible-directory-p  exam-net-data-pt))    
      (exam-err "Unable to write to remote dir `%s.'" exam-net-data-pt)
      (throw 'test t))

  ;; Do not overwrite answer file
  ;; It seems better to test answer file error before answer dir warning
  (when (file-exists-p exam-net-ans-file-pt)
    (exam-err "Remote answer file `%s' alredy exists!"  
	     (file-name-nondirectory exam-net-ans-file-pt))
    (throw 'test t))

;  ;; Confirm to go if answer dir exists
;  (when (file-directory-p exam-net-course-pt)
;    (save-excursion 
;      (exam-err "Remote answer directory already exists.
;Answer to the question below to proceed.")
;      (unless
; 	  (yes-or-no-p "Do you want to proceed? ")
; 	(kill-emacs))))
  (make-directory exam-net-course-pt t)
  
  ;; Test access to remote course dir
  (when (not (file-accessible-directory-p  exam-net-course-pt))    
      (exam-err "Unable to write to remote dir `%s.'" exam-net-course-pt)
      (throw 'test t))
  
  ;; Test access to remote answer file  
  (when (not (file-writable-cross-p exam-net-ans-file-pt))
      (exam-err "Unable to write to remote file `%s.'" exam-net-ans-file-pt)
      (throw 'test t))
  (with-temp-file exam-net-ans-file-pt (insert "Test write"))

  ;; Test access to local answer file  
  (when (not (file-writable-cross-p  exam-loc-ans-file-pt))    
    (exam-err "Unable to write to local file `%s.'" exam-loc-ans-file-pt)
    (throw 'test t))
  (with-temp-file exam-loc-ans-file-pt  (insert "Test write")))


(defun exam-insert-contacts ()
  "Insert test header and ask student contact details."

  ;; (widget-insert "Please, read and fill the paper test too.\n\n")
  (widget-insert "\n")

   (widget-create 'editable-field
         :size 4
         :format "Test num.: %v "
	 :notify (lambda (widget &rest _) (exam-process-contacts widget 'exam-id))
         "")
   (widget-insert (format " Seat: %s\n\n" (downcase (getenv "COMPUTERNAME"))))

   (widget-create 'editable-field
         :size 30
         :format "Given Name(s): %v "
	 :notify (lambda (widget &rest _) (exam-process-contacts widget 'given-name))
         "")
   (widget-create 'editable-field
         :size 25
         :format "Family Name: %v " ; Text after the field!
	 :notify (lambda (widget &rest _) (exam-process-contacts widget 'family-name))
         "")
   (widget-insert "\n\n")

   (widget-create 'editable-field
         :size 20
         :format "Matricola or date of birth (d/m/y): %v "
	 :notify (lambda (widget &rest _) (exam-process-contacts widget 'student-id))
         "")
   (widget-insert "\n")
;   (widget-create 'editable-field
;         :size 10
;         :format "If you don't remember your ID, date of birth: %v "
; 	 :notify (lambda (widget &rest _) (setq student-birth (widget-value widget)))
;         "")
   (widget-insert "\n")
   (widget-create 'editable-field
         :size 10
         :format "Today is (day/month/year):          %v "
	 :notify (lambda (widget &rest _) (exam-process-contacts widget 'exam-date))
         "")
   (widget-insert "\n\n"))

(defun exam-insert-question (ith-quest)
  "Insert ITH-QUEST question."

  ;; Question header
  (let ((face '(:height 1.3 :background "black" :foreground "white")))
    (insert
     (propertize (format "Question %s:\n" ith-quest) 'font-lock-face face)
     "\n"))

  ;; Generic text
  (insert (propertize "Select your choice."
		      'font-lock-face '(:weight bold)))
  (insert "\n")
  (widget-create 'radio-button-choice
		 :value nil
		 :notify (lambda  (widget &rest _)
			   (exam-process-answer widget ith-quest))
		 '(item "a") '(item "b") '(item "c") (list 'item :tag exam-no-answer-string :value nil)
		 )
  (insert "\n"))

(defun exam-insert-finish ()
  "Insert the finish button for the QUESTIONS."
  (widget-create 'push-button
                 :notify 'exam-exit-ahead
                 :help-echo "Click if you don't want to continue. You have to confirm your wish."
                 "Exit now!"))

;;; === end of Main Form Setup Functions
;;; ====================================

;;; ======================= ;;;
;;; === Remote Commands === ;;;
;;; ======================= ;;;

(defun remote-update ()
  "Update local \"site-start.el\" with remote file \"update-performed/new-site-start.txt\" in `exam-net-data-pt'."

  (catch 'update 
    ;; Update already done
    (if exam-cmd-update-performed (throw 'update t))

    (if (not (file-exists-p (make-path exam-net-data-pt  "update007")))
	(throw 'update t))
    
    (message "Updating `site-start.el'") 
    (let* ((site-dir  (expand-file-name "../share/emacs/site-lisp" invocation-directory))
	   (original-site-start (make-path site-dir "site-start.el"))
	   (local-new-site-start (make-path site-dir "new-site-start.txt"))
	   (remote-new-site-start (make-path exam-net-data-pt "new-site-start.txt"))
	   (update-dir-pt (make-path exam-net-data-pt "update-performed"))
	   (remote-result-file  (concat "updated-" (downcase (getenv "COMPUTERNAME")) ".txt"))
	   (remote-result-file-pt (make-path update-dir-pt remote-result-file))	     	     
	   new-content old-content res-content)

      ;; Make a local copy of remote site-start or signal non critical error
      (when (not (file-exists-p remote-new-site-start))
	(message "Error: Update file `%s' not found" remote-new-site-start)
	(throw 'update t))

      ;; Copy remote file without overwrite
      (copy-file remote-new-site-start local-new-site-start t)
      (when (not (file-exists-p local-new-site-start))
	(message "Error: Copying `%s' to `%s' (trying later)"
		 remote-new-site-start local-new-site-start)
	(throw 'update t))

      ;; Overwrite original file with local copy
      (copy-file local-new-site-start original-site-start t)
      (setq new-content
	    (with-temp-buffer (insert-file-contents local-new-site-start) (buffer-string)))
      (setq old-content
	    (with-temp-buffer (insert-file-contents original-site-start) (buffer-string))) 
      (when (not (string= new-content old-content))
	(message "Error: Copying `%s' to `%s' (trying later)"
		 local-new-site-start original-site-start)
	(throw 'update t))
      
      ;; Make update dir 
      (make-directory update-dir-pt t)
      (when (not (file-accessible-directory-p update-dir-pt))
	(message "Unable to write to remote dir `%s.'" update-dir-pt)
	(throw 'update t))
	 
      ;; Write to remote result file
      (when (not (file-writable-cross-p remote-result-file-pt))
	(message "Unable to write to remote file `%s.'" remote-result-file-pt)
	(throw 'update t))

      (string-match "^;; *[Vv]ersion: +.+" new-content)      
      (setq res-content	(match-string-no-properties 0 new-content)      
	    res-content     
	    (concat res-content "\nUpdated at: " (format-time-string "%Y-%m-%d %H:%M:%S")))      
      (with-temp-file remote-result-file-pt (insert res-content))

      (setq exam-cmd-update-performed t))))


;;; === end of Remote Commands
;;; ==========================

;;; ============= ;;;
;;; === Main  === ;;;
;;; ============= ;;;

(defun setup-form ()
  "Main widget setup function."

  (let ((buffer (get-buffer-create exam-buffer-name)))
    (with-current-buffer buffer

      ;; The first thing as this mode kills any buffer local var
      (exam-mode)

      ;; Init vars and make dirs
      (read-inits)
      (setq exam-answered-ones 0)
      (setq answers-given (make-vector quest-count nil))
      (exam-make-answer-string)
      (exam-make-dirs)
      
      ;; Set header-line (will start timed functions)
      (exam-mode-header exam-max-time)

      ;;Make form 
      (exam-insert-contacts)
      (cl-loop for i from 1 to quest-count
	       do (exam-insert-question i))
      (exam-insert-finish) ;)
      (widget-setup) ;  adds a read-only mode outside widgets
      (widget-forward 1))

    (switch-to-buffer buffer))

  (run-at-time "1 sec" nil (lambda () (message "Good luck with the your test!")))

  ;; Better as last item, so we can easily close Emacs in case of failures
  (add-hook 'kill-emacs-query-functions 'exam-exit-hook))

(defun cleanup ()
  "Kill possilbe reserved buffers, timer and kill hooks except the message buffer \"blank\". 
For debug scenarios or after raising exceptions."

  (set 'kill-emacs-query-functions nil)
  (if (timerp exam-scheduler) (cancel-timer exam-scheduler)) 
  (if (get-buffer exam-buffer-name)
      (kill-buffer exam-buffer-name)))
  
(defun test ()
  "Generate the multiple choice test based on `exam-net-init'."
  (interactive)

  ;; Convenient encoding to save answer compatible with LaTeX
  (prefer-coding-system 'utf-8-dos)
 
  (cleanup)
  
  ;; Managed exceptions use the "blank" buffer and/or  minibuffer
  (let ((blk "blank"))
    (if (get-buffer blk) (kill-buffer blk))
    (setq blk (get-buffer-create blk))
    (with-current-buffer blk
      (insert "Please do not write here. Write to the right of the question.")
      (read-only-mode)))

  ;; Unmanaged exceptions are visible in message buffer
  (switch-to-buffer (messages-buffer))


  (catch 'test

    ;; Init and test concurrency
    (set-running-id)
    (single-instance-init)
  
    ;; Setup test buffer 
    (setup-form)))

;;; === end of Main 
;;; ===============


;;; ======================== ;;;
;;; === Debug Functions  === ;;;
;;; ======================== ;;;

(defun site-start ()
  "Open `site-start.el', for debug."
  (interactive)
  (find-file "~/../share/emacs/site-lisp/site-start.el"))

(defun stop-the-music ()
  "Safely close buffer and stop timer, for debug."
  (interactive)
  (let ((code (read-string "Stop code:")))
    (when (string= code "990")
      (cancel-timer exam-scheduler)
      (site-start)
      (key-stuff) )))

(defun key-stuff ()
  "Comfort key and the likes, for debug debug."

  (interactive)
  (setq tab-always-indent 'complete)
  (show-paren-mode)
  (global-set-key (kbd "C-f") 'isearch-forward)
  (define-key isearch-mode-map (kbd "C-f") 'isearch-repeat-forward)
  (cua-mode)

  ;;; More debug stuff
  ;; (setq exam-remaining-secs 1000)
  ;; (cancel-timer exam-scheduler)
  ;; (kill-emacs)
  
)

;;; === end of Debug Functions
;;; ==========================

;;; Main, Main Form Setup Functions;
;;; Customise Me, Global Vars, Style
;;; FS Helpers, Widget Functions, Stop Hooks, Remote Commands, Debug Functions


;;; FIRE!
(test)


 
