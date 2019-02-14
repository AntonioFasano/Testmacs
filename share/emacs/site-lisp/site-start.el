;;; Testmacs --- Administer classroom tests over a LAN -*- lexical-binding: t -*-

;; ----->  Copy this in share\emacs\site-lisp\site-start.el

;; Author: Antonio Fasano
;; Version: 0.4
;; Keywords: exam, quiz, test, forms, widget
;; This program requires: cl-lib subr-x seq emacs "25"

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
;; Answers are stored locally in the parent of `exam-loc-server-ini' and remotely in `exam-net-course-pt'.  
;; To find the remote share, the file retrived from `exam-loc-server-ini' is used.
;;
;; ## Default Entries
;; Before the question area, the computer screen reports some fields to collect student details. By default they are:
;;  
;;     Test num.: _______
;;     Given Name(s): _______________________  Family Name: _____________________________
;;     Student ID: ___________________
;;  
;; An equivalent answer file is produced locally and remotely (as set by the variables `exam-loc-ans-file-pt` and `exam-net-ans-file-pt`. The asnwer file will be similar to the follwing:
;;  
;;     exam-id:123
;;     given-name:John
;;     family-name:Doe
;;     student-id:1234567
;;     ans-string:"b" "b" nil nil "b" nil "a" "b" nil "a" nil nil nil nil nil
;;  
;; The values after the colon for `exam-id`, `given-name`, `family-name`, and `student-id` depend on the respective values typed by the student for Test num., Given Name(s), Family Name and Student ID. 
;;  
;; `ans-string` is clearly a list of the answer given `nil` being the answers not given.
;;  							       
;; ## Custom Entries
;; You can customise the fields adding the file `~/custfld.txt`. Note that the Windows launcher redirects the home directory `~` to the subdirectory `data` found in Testmacs package. Each file line has a custom-field entry with the format `Name:Width:Text`. `Name` is the field name as reported in the answer files.
;; `Witdh` is the width of the user typing area, but note that the initial width will dynamically expads as the user types. `Text` is the text describing the information to enter displayed on the screen to the left of the typing area.  However, if `Width` is 0, the field is only informative and there is no information to type. `Width` can be -1, in which case the nothingis displayed on screen, just the the combination `Name:Text` is reported in the answer files for further processing.
;;
;; Example:
;;
;;     project-date:10:Date when you delivered the class project: %v \n
;;     disp-seat-name:0:Computer name is %c\n
;;     seat-name:-1:%c
;;  
;; \"project-date\" is an editable field and the text \"Date when you ...\" will be displayed replacing `%v' with an edititable area of 10-character width. Information entered is reported in the answer files as \"project-date:DATE\", where DATE is the value entered by the student. 
;; \"disp-seat-name\" displays on the subsequent line the screen text \"Computer name is foo\", where \"foo\" is the name of the computer where Testmacs is running. 
;; \"seat-name\" is similar to the preceding field, but it does not involve any screen display, only \"seat-name:foo\" is reported in the answer files.
;; To add line-breaks to TEXT use `\n` preceeded by a single slash.
;;  
;; Customs fields are displayed immediately after default fields area. If you include a default field in  `~/custfld.txt`, that field will be removed from default field area.
;;
;; Read the Elisp docstring of `exam-loc-cust-fld` for more information.
;;
;; ## Remote Commands
;; Emacs performs some actions if detects predefined command filenames in the
;;   remote directory `exam-net-data-pt`. See action for each command filename.
;; Command filename "exit007": Emacs will exit in 10 seconds.
;; Command filename "update007": Emacs updates `site-start.el' with the file `new-site-start.txt'
;; in the remote directory `exam-net-data-pt' and possibly the `custfld.txt' with remote `new-custfld.txt'.
;; If `new-site-start.txt' is not found or there is a copy error a non-critical error is displayed
;; until the action succeeds or the command filename is removed.

;; Inspirations
;; https://github.com/syohex/emacs-mode-line-timer
;; https://github.com/davep/quiz.el

;;; Code:

(require 'cl-lib)
(require 'widget)
(require 'wid-edit)
(require 'subr-x)
(require 'seq)

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

(defconst exam-default-fields
  '(("exam-id"       4   "Test num.: %v ")
    ("seat-disp"     0   " Seat: %c\n\n")
    ("seat"          -1  "%c")
    ("given-name"    30  "Given Name(s): %v ")
    ("family-name"   25  "Family Name(s): %v \n\n")
    ("student-id"    20  "Student ID: %v \n")
    ("saved-at"      -1  "%t")    
    )

  "List of default fields (and related text) inserted on the screen answer sheet before the answer widgets. 
The list can be overridden by `exam-custom-fields'.

Each element of `exam-default-fields' represents a text only widget, an editable field widget, or a hidden fields. Text only fields appear only on screen and they are not reported in the student's answer files. Editable field widgets collect student input to be reported in the answer files. Hidden fields report (computed) information in the answer files, but do not show on screen. 

Elements of `exam-default-fields' are lists consisting of the following elements: NAME, WIDTH, and TEXT. NAME is a string denoting the field name. TEXT is the text string presented on screen and a `%v' inside TEXT is replaced by the field's editable area of width WIDTH. For text only widgets, WIDTH is zero. For hidden fields, WIDTH is -1.

For each editable or hidden field, an equivalent line is added to the local (`exam-loc-ans-file-pt') and the remote (`exam-net-ans-file-pt') answer file with the format NAME:VALUE. For editable field widgets, VALUE is the text entered by the student in the editable area; for hidden fields, VALUE is TEXT. 
In TEXT, beyond `%v', a `%c' is replaced by the client computer name, a `%t' is replaced by time in ISO format (but without time zone) and `%%' must be used to show a literal `%'. Warning: When you use `%v' always preceded it with some other text. Also In an editable-field widget, the editable field must not be adjacent to another widget—that won't work. TODO You must put some text in between. Either make this text part of the editable-field widget itself, or insert it with XXXXwidget-insert.")
  
(defconst exam-loc-cust-fld "~/custfld.txt"
  "Local file with custom fields. If the file exists, it defines custom fields displayed immediately after the, overriding default fields in `default-fields' with the same name. 
Each line of the file `exam-loc-cust-fld' has a custom-field entry with the format NAME:WIDTH:TEXT and an equivalent line is added to the local (`exam-loc-ans-file-pt') and the remote (`exam-net-ans-file-pt') answer file with the format NAME:VALUE. Parsed fields are added to the list `exam-custom-fields', therefore NAME, WIDTH, and TEXT are like the fields' elements of `exam-custom-fields'. 
Example:

project-date:10:Date when you delivered the class project: %v \\n
disp-seat-name:0:Computer name is %c
seat-name:-1:%c

\"project-date\" is an editable field and the text \"Date when you ...\" will be displayed replacing `%v' with an edititable area of 10-character width. Information entered is reported in the answer files as \"project-date:DATE\", where DATE is the value entered by the student. 
\"disp-seat-name\" displays on the subsequent line the screen text \"Computer name is foo\", where \"foo\" is the name of the computer where Testmacs is running. 
\"seat-name\" is similar to the preceding field, but it does not involve any screen display, only \"seat-name:foo\" is reported in the answer files.
To add line-breaks to TEXT use `n' preceeded by a single slash.")

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
  "Path of remote answer file. The file is identical to the local answer file, whose format is described by the variable `exam-loc-ans-file-pt'.")

(defvar exam-loc-ans-file-pt  nil
  "Path of client local answer file.
Each line of the answer file (entry) has the format NAME:VALUE. The entries are the following:

DEFAULT ENTRIES
CUSTOM ENTRIES
ans-string:VALUE VALUE ...

DEFAULT ENTRIES contain student details entered by the student during the test or produced by the system.
They are set and documented by the variable `default-fields'. 
CUSTOM ENTRIES are optional and are defined in the file `exam-loc-cust-fld'.
\"ans-string\" contains answers entered. Each VALUE can be \"a\", \"b\" etc. (including quotes)  or `nil' (without quotes).")

(defvar exam-custom-fields nil
  "List of custom fields to insert on the screen answer sheet, with the same format as `exam-default-fields'.
If an `exam-custom-fields' field has the same name of an `exam-default-fields' field, the latter field is not showed on screen nor is added to the answer files. Definitions of fields are set in the file `exam-loc-cust-fld' and copied by the function `get-custom-fields' to `exam-custom-fields' list. 
Fields in `exam-custom-fields' cannot have duplicate names. See the function `parse-cust-field', for more information on acceptable field definitions.")

(defvar exam-custom-field-names nil
  "List of custom fields names, build with cars of element of `exam-custom-fields'.")

(defvar exam-field-vars nil
  "Alist to store field names and values as strings. Field names and values depends on the list structures `exam-default-fields' and `exam-custom-fields'. Each field pair NAME:VALUE is saved to the local (`exam-loc-ans-file-pt') and the remote (`exam-net-ans-file-pt') answer file every `exam-update-freq' seconds.")

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
  "Timer object to run scheduled tasks in `exam-schedule-hook' every `exam-update-freq' seconds.
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

;;(defvar-local given-name nil
;;  "Student contact.")
;; 
;;(defvar-local family-name nil
;;  "Student contact.")
;; 
;;(defvar-local student-id nil
;;  "Student contact.")
;; 
;;(defvar-local student-birth nil
;;  "Student contact.")
;; 
;;(defvar-local exam-date nil
;;  "Examination day.")
;; 
;;(defvar-local exam-id  nil
;;  "Test ID to be used to match student answers.")


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
    (dotimes (_ 3 id)
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
Note: To restart the app remove the remote answer file from the server.\n
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

(defun exam-process-head (widget var-name)
  "On updated head fields hook."
;  (set var-name (widget-value widget))
  (setcdr (assoc var-name exam-field-vars) (widget-value widget))
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
  (with-temp-file exam-net-ans-file-pt  (insert exam-ans-string))
  (exam-remote-cmds))

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

  ; (setq exam-scheduler (run-with-timer 0 exam-update-freq 'exam-schedule-hook))
  )

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
  "When a field is updaded this syncs `exam-ans-string' with header field values and answers."
  (let ((ans-string
	 (format "ans-string:%s" (replace-regexp-in-string  "[][]" "" (prin1-to-string answers-given))))
	(head-fields
	 (mapconcat (lambda (elt) (format "%s:%s\n" (car elt) (cdr elt)))  exam-field-vars "")
	 ;;(apply 'concat (mapcar (lambda (elt) (format "%s:%s\n" (symbol-name elt) (symbol-value elt)))
	 ;; 			'(given-name family-name student-birth student-id  exam-date exam-id)))
	 ))
    (setq exam-ans-string (concat head-fields ans-string
					;"\nsaved-at:" (format-time-string "%Y-%m-%d %H:%M:%S")
		  ))))


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

(defun make-head-notify (field-varname)
  "Make the notify property to be added to the edit fields in the header area of the test form.
The property triggers the function `exam-process-head' each time a key is pressed in the edit area.
The property is a lambda whose body contains the name of the field riceived by FIELD-VARNAME."
  (list 'lambda `(widget &rest _) (list 'exam-process-head `widget field-varname)))

(defun add-edit-field (name width text)
  "Add the edit field with name NAME, width WIDTH and text TEXT."
  (widget-create 'editable-field
		  :size width
		  :format text
		  :notify (make-head-notify name)
		  ""))

		     
(defun exam-insert-header ()
  "Insert test header used to collect student details or display information."
  
  (let* ((def-field-names (mapcar 'car exam-default-fields))
	 (def-names-str (mapconcat 'identity def-field-names " "))
	 unique-fields common-fld-names)

    ;; Check for duplication errors in setting `exam-default-fields' 
    (when (dups-p def-field-names)
      (exam-err
       "The constant `exam-default-fields', set by the main program module, has duplicate field names:\n%s"
       def-names-str)
      (throw 'test t))

    ;; Build custom field list
    (get-custom-fields) ; fills exam-custom-fields, exam-custom-field-names

    (setq common-fld-names (seq-intersection  exam-custom-field-names def-field-names))


;    (mapcar (lambda (elt) ; Build unique list with default fields possibly overridden by custom fields 
; 	      (if (member (car elt)  common-fld-names)	       
; 		  (add-to-list 'unique-fields (assoc (car elt) exam-custom-fields) t)
; 		(add-to-list 'unique-fields elt t)))
; 	    exam-default-fields)

    ;; Create unique list with default fields not redefined as custom + custom fields
    (setq unique-fields
	  (append unique-fields
		  (seq-filter (lambda (elt) (not (member (car elt) common-fld-names)))
			      exam-default-fields)
		  exam-custom-fields))
    
    ;(setq unique-fields   ; Append remaining (non common) custom fields to unique field list 
    ; 	  (append unique-fields
    ; 		  (seq-filter (lambda (elt) (not (member (car elt) common-fld-names)))
    ; 				  exam-custom-fields)))

    (setq exam-field-vars nil)
    (mapc (lambda (elt) (add-to-list 'exam-field-vars (list (car elt)) t))
	    unique-fields)

    ;; For each element of unique-fields add an edit field 
    (widget-insert "\n")    
    (let* (w
	   (wds unique-fields)
	   (comp-name (downcase (getenv "COMPUTERNAME")))
	   (time  (format-time-string "%FT%T"))

	   name width text
	   
	   ;; Replace %c with compname and escape %%
	   (rep (lambda (s)  
		  (thread-last 
		      (replace-regexp-in-string "%\\{1\\}c" comp-name s  nil 'literal)
		      (replace-regexp-in-string "%\\{1\\}t" time)
		    (replace-regexp-in-string "%%" "%" )))))

    
      (while (setq w (pop wds))
	(setq name  (nth 0 w)
	      width (nth 1 w)
	      text  (funcall rep (nth 2 w)))

	(cond 
	 ;; Add text only
	 ((eq width 0)
	  (assq-delete-all name exam-field-vars) ; name points to value, so works with assq
	  (widget-insert text))
	 	 
	 ;; Add store hidden fields
	 ((eq width -1)
	    (setcdr (assoc name exam-field-vars) text))

	 ;; Add editable field widget
	 ((> width 0) (add-edit-field name width text))))
      
      (widget-insert "\n"))))
    


;   (widget-create 'editable-field
;         :size 4
;         :format "Test num.: %v "
; 	 :notify (lambda (widget &rest _) (exam-process-head widget 'exam-id))
;         "")
;   (widget-insert (format " Seat: %s\n\n" (downcase (getenv "COMPUTERNAME"))))
; 
;   (widget-create 'editable-field
;         :size 30
;         :format "Given Name(s): %v "
; 	 :notify (lambda (widget &rest _) (exam-process-head widget 'given-name))
;         "")
;   (widget-create 'editable-field
;         :size 25
;         :format "Family Name: %v " ; Text after the field!
; 	 :notify (lambda (widget &rest _) (exam-process-head widget 'family-name))
;         "")
;   (widget-insert "\n\n")
; 
;   (widget-create 'editable-field
;         :size 10
;         :format "Birth Date (day/month/year): %v "
; 	 :notify (lambda (widget &rest _) (setq student-birth (widget-value widget)))
;         "")
;;   (widget-insert "\n")
; 
;   (widget-create 'editable-field
;         :size 20
;         :format "  Student ID. This is optional: %v "
; 	 :notify (lambda (widget &rest _) (exam-process-head widget 'student-id))
;         "")
;   (widget-insert "\n")
; 
;   (widget-create 'editable-field
;         :size 10
;         :format "Today is (day/month/year): %v "
; 	 :notify (lambda (widget &rest _) (exam-process-head widget 'exam-date))
;         "")
;   (widget-insert "\n\n"))

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
		 '(item "a") '(item "b") '(item "c") '(item "d") '(item "e") (list 'item :tag exam-no-answer-string :value nil)
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
  "Update local \"site-start.el\" and possibly the local custom-field file with equivalent remote files  \"new-site-start.txt\" and \"new-custfld.txt\" in `exam-net-data-pt'. 
Update results are written in the folder  \"update-performed\" in `exam-net-data-pt'.
The name of local custom file is set in `exam-loc-cust-fld' the remote name is obtained adding the \"new-\" prefix."

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
	   new-content old-content res-content

	   ;; Custom fileds
	   (new-custom-flds (concat "new-" (file-name-nondirectory exam-loc-cust-fld)))
	   (remote-new-custom-flds (make-path exam-net-data-pt new-custom-flds))
	   (local-new-custom-flds (make-path (file-name-directory exam-loc-cust-fld) new-custom-flds)))

      ;; Test remote site-start and possibly  signal non critical error
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

      ;; Get version for result file
      (string-match "^;; *[Vv]ersion: +.+" new-content)      
      (setq res-content	(match-string-no-properties 0 new-content)      
	    res-content     
	    (concat res-content "\nUpdated at: " (format-time-string "%Y-%m-%d %H:%M:%S"))) 
      
      ;; Copy custom-field file only if it exists
      (when (file-exists-p remote-new-custom-flds)
	(message "Main file updated. Now updating custom field file.")

	;; Copy remote file without overwrite
	(copy-file remote-new-custom-flds local-new-custom-flds t)
	(when (not (file-exists-p local-new-custom-flds))
	  (message "Error: Copying `%s' to `%s' (trying later)"
		 remote-new-custom-flds local-new-custom-flds)
	  (throw 'update t))
	(copy-file local-new-custom-flds exam-loc-cust-fld t)

	;; Overwrite original file with local copy
	(setq new-content
	      (with-temp-buffer (insert-file-contents local-new-custom-flds) (buffer-string)))
	(setq old-content
	      (with-temp-buffer (insert-file-contents exam-loc-cust-fld) (buffer-string))) 
	(when (not (string= new-content old-content))
	  (message "Error: Copying `%s' to `%s' (trying later)"
		   remote-new-custom-flds local-new-custom-flds)
	  (throw 'update t)))

      ;; Make update dir 
      (make-directory update-dir-pt t)
      (when (not (file-accessible-directory-p update-dir-pt))
	(message "Unable to write to remote dir `%s.'" update-dir-pt)
	(throw 'update t))
	 
      ;; Write to remote result file
      (when (not (file-writable-cross-p remote-result-file-pt))
	(message "Unable to write to remote file `%s.'" remote-result-file-pt)
	(throw 'update t))

      (with-temp-file remote-result-file-pt (insert res-content))

      (message "Updating successful.") 
      (setq exam-cmd-update-performed t))))


;;; === end of Remote Commands
;;; ==========================

;;; ========================== ;;;
;;; === Get Custom Fields  === ;;;
;;; ========================== ;;;


(defun unique-p  (list)
  "NOT USED Return nil if LIST has duplicates or LIST."
  (let (ret (lst list))
    (while (and lst (setq ret (not (member (pop lst) lst)))))
    (if ret list)))

(defun dups-p (lst)
  "Return t if LIST has duplicates"
  (let (ret)
    (while (and lst (setq ret (not (member (pop lst) lst)))))
    (not ret)))

(defalias 'custom-field-cursor 
  (let ((lineno 0))
    (lambda (&optional action)
      (setq lineno (pcase action 
	('init 0)
	('inc (1+  lineno))
	(_ lineno)))))
  "When reading `exam-loc-cust-fld', return statically sets and return the current line number. 
An optional ACTION argument is accepted. Before returning line number, if ACTION is 'init, the value is set to zero; if ACTION is 'inc, the value is incremented by one.")


;; "Possibly fill `exam-custom-fields' and `exam-custom-field-names' with data from `exam-loc-cust-fld'."

(defun get-custom-fields () 
      "Read custom field file `exam-loc-cust-fld'  and create a list of custom fields. 
Each file line has the format NAME:WIDTH:TEXT, whose meaning is that of the elements of `exam-custom-fields'.
Blank lines, if any, are skipped. If no errors are detected, `exam-custom-fields' and `exam-custom-field-names' are filled. Errors include duplicate field names. See `parse-cust-field' acceptable field definitions."

      (setq exam-custom-fields nil
	    exam-custom-field-names nil)
      (when (file-exists-p exam-loc-cust-fld)
	(let ((cust-flds-buf (split-string
			      (with-temp-buffer (insert-file-contents exam-loc-cust-fld) (buffer-string))
			      "\n"))
	      custflds entry)

	  ;; Init cursor 
	  (custom-field-cursor 'init)

	  ;; Fill custom field list
	  (while (setq entry (pop cust-flds-buf))
	    (custom-field-cursor 'inc)
	    (if (setq entry (parse-cust-field entry))	 
		(push entry custflds)))
	  (setq exam-custom-fields (reverse custflds)))

	;; Test duplicates
	(setq exam-custom-field-names (mapcar 'car exam-custom-fields))
	(if (dups-p exam-custom-field-names)
	    (parse-err "Duplicate custom fields:\n%s" (mapconcat 'identity exam-custom-field-names " ")))))

(defun parse-cust-field (line)
      "Parse a line from the custom field file `exam-loc-cust-fld' and return a list (NAME WIDTH TEXT). 
The function `get-custom-fields' uses the returned list to fill the list `exam-custom-fields' and the car, NAME, to fill `exam-custom-field-names'. 
NAME can only have alphanumeric characters or the four literals `-_.'.  WIDTH should be non-negative and not more than 100. 
See the variable `exam-custom-fields' for the meaning of the returned list elements." 

      (let* ((ss (split-string line ":"  nil split-string-default-separators))
	     (name (nth 0 ss))
	     (width (nth 1 ss))
	     (text (replace-regexp-in-string (regexp-quote "\\n") "\n" line))
	     (text (mapconcat 'identity (cddr (split-string text ":")) ":")))
	
	(if (eq 0 (length (car ss))) nil 
	  ;; Check syntax
	  (if (< (length ss) 3)
	      (parse-err-ln "Not enough elements in:\n%s" line))
	  (unless (string-match-p "^[[:alnum:]-_.]+$" name)
	    (parse-err-ln "Not only `alphanum-_.' in `%s' in:\n%s" name line))
	  (unless (string-match-p "^-?[[:digit:]]+$" width)
	    (parse-err-ln "Width `%s' is not a non-negative integer in:\n%s" width line))
	  (if (< 100 (setq width (string-to-number width)))
	      (parse-err-ln "Excessive field width in:\n%s" line))

	  (list name width text))))


(defun parse-err-ln (msg &rest ags)
  "Exit safe in case of errors in parsing custom fields, which includes removing cookies. 
See `exam-err' for more safe belts."
  (let ((errmess "Error in custom field file `%s', line %d\n")
	(cursor  (list exam-loc-cust-fld (custom-field-cursor))))
    (apply 'exam-err (concat errmess msg) (append cursor ags)))
  (throw 'test t))

(defun parse-err (msg &rest ags)
  "A version of `parse-err-ln ' not printing the number of the line parsed."
  (let ((errmess "Error in custom field file `%s'\n"))    
    (apply 'exam-err (concat errmess msg) (append (list exam-loc-cust-fld) ags)))
  (throw 'test t))

;;; === end of Get Custom Fields
;;; ============================


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
;      (exam-make-answer-string)
      (exam-make-dirs)
      
      ;; Set header-line (will start timed functions)
      (exam-mode-header exam-max-time)

      ;;Make form 
      (exam-insert-header)
      (cl-loop for i from 1 to quest-count
	       do (exam-insert-question i))
      (exam-insert-finish) ;)
      (widget-setup) ;  adds a read-only mode outside widgets
      (widget-forward 1)

      ;; Update countdown and save answers every exam-update-freq seconds
      (exam-make-answer-string)
      (setq exam-scheduler (run-with-timer 0 exam-update-freq 'exam-schedule-hook)))

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

  (setq frame-title-format  "Testmacs")
 
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
;;; FS Helpers, Widget Functions, Stop Hooks, Remote Commands, Get Custom Fields, Debug Functions


;;; FIRE!
(test)


 

