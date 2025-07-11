﻿;;; Testmacs --- Administer classroom tests over a LAN -*- lexical-binding: t -*-

;; ----->  Copy this in share\emacs\site-lisp\site-start.el

;; Author: Antonio Fasano
;; Version: 0.6.1
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
;; Answers are stored locally in the parent of `testmacs-loc-server-ini' and remotely in `testmacs-net-course-pt'.  
;; To find the remote share, the file retrived from `testmacs-loc-server-ini' is used.
;;
;; ## Default Entries
;; Before the question area, the computer screen reports some fields to collect student details. By default they are:
;;  
;;     Test num.: _______
;;     Given Name(s): _______________________  Family Name: _____________________________
;;     Student ID: ___________________
;;  
;; An equivalent answer file is produced locally and remotely (as set by the variables `testmacs-loc-ans-file-pt` and `testmacs-net-ans-file-pt`. The answer file will be similar to the follwing:
;;  
;;     exam-id:123
;;     seat:PC03
;;     given-name:John
;;     family-name:Doe
;;     student-id:1234567
;;     started-at:2020-01-29T11:03:10
;;     last-saved:2020-01-29T11:23:34
;;     ans-line:"b" "b" nil nil "b" nil "a" "b" nil "a" nil nil nil nil nil
;;  
;; The values after the colon for `exam-id`, `given-name`, `family-name`, and `student-id` depend on the respective values typed by the student for Test num., Given Name(s), Family Name and Student ID. 
;;
;; The remaining field are calculated.
;; `started-at` and `last-saved` are the time Testmacs is started and the last time the answer file has been saved. 
;; `ans-line` is clearly a list of the answer given `nil` being the answers not given.
;;  							       
;; ## Custom Entries
;; You can customise the fields adding the file `~/custfld.txt`. Note that Testmacs launcher redirects the home directory `~` to the subdirectory `data` found in Testmacs directory. Each file line has a custom-field entry with the format `Name:Width:Text`. `Name` is the field name as reported in the answer files.
;; `Witdh` is the width of the user typing area, but note that the initial width will dynamically expads as the user types. `Text` is the text describing the information to enter displayed on the screen to the left of the typing area.  However, if `Width` is 0, the field is only informative and there is no information to type. `Width` can be -1, in which case nothing is displayed on screen, just the the combination `Name:Text` is reported in the answer files for further processing.
;;
;; Example:
;;
;;     project-date:10:Date when you delivered the class project: %v \n
;;     disp-seat-name:0:Computer name is %c\n
;;     seat-name:-1:%c
;;  
;; \"project-date\" is an editable field and the text \"Date when you ...\" will be displayed replacing `%v' with an edititable area of 10-character width. Information entered is reported in the answer files as \"project-date:DATE\", where DATE is the value entered by the student. 
;; \"disp-seat-name\" displays on the subsequent line the screen text \"Computer name is foo\", replacing `%c' with  the computer where Testmacs is running, here assumed \"foo\". 
;; \"seat-name\" is similar to the preceding field, but it does not involve any screen display, only \"seat-name:foo\" is reported in the answer files.
;; To add line-breaks to TEXT use `\n` preceeded by a single slash.
;;  
;; Customs fields are displayed immediately after default fields area. If you include a default field in  `~/custfld.txt`, that field will be moved from default field area to custom fields area.
;;
;; Read the Elisp docstring of `testmacs-loc-cust-fld` for more information.
;;
;; ## Remote Commands
;; Emacs performs some actions if detects predefined command filenames in the
;;   remote directory `testmacs-net-data-pt`. See action for each command filename.
;; Command filename "exit007": Emacs will exit in 10 seconds.
;; Command filename "update007": Emacs updates `site-start.el' with the file `new-site-start.txt'
;; in the remote directory `testmacs-net-data-pt' and possibly the `custfld.txt' with remote `new-custfld.txt'.
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

(defconst testmacs-version  "0.6.1"
  "Current app version.")

(defconst testmacs-loc-server-ini  "~/server*.txt"
  "Local file whose first line has the path of the remote used by the variable `testmacs-net-data-pt'.
Note that the \"~\" is redirected by the Testemacs launcher to a subdirectory of the Testemacs package named \"data\". If the variable has wildcards, the first valid server path is used. See `set-server-share' for more.")

(defconst testmacs-net-init "INITFILE*.txt"
  "File name in the remoted share with values for `testmacs-max-time-active', and `quest-count' and `testmacs-course'.
If the variable has wildcards, the first path found is used.")

(defconst testmacs-default-fields
  '(("exam-id"       4   "Test num.: %v ")
    ("seat-disp"     0   " Seat: %c\n\n")
    ("seat"          -1  "%c")
    ("given-name"    30  "Given Name(s): %v ")
    ("family-name"   25  "Family Name(s): %v \n\n")
    ("student-id"    20  "Student ID: %v \n")
    ("started-at"    -1  "%b")
    ("last-saved"    -1  "%e")
    )

  "List used to represent the screen header area preceding the answer area, intended to collect and display non-question information (such as the student name) usually saved in the students' answer files.
The list can be overridden by `testmacs-custom-fields', which is obtained by the server-side file `testmacs-loc-cust-fld'. 

Each element of `testmacs-default-fields' is named a \"field\". There are three types of fields: edit-fields, text-fields, hidden-fields. Edit-fields are rendered by means of Emacs widgets which can collect user input (e.g. student's family name). Text-fields just display read-only text (e.g. \"Do not cheat\"). Hidden-fields contain information to be saved in the answer files, but not shown on screen (e.g. \"Finance 432\").

Each field is a list whose elements consist of the elements: NAME, WIDTH, and TEXT. NAME is a string denoting the field name. WIDTH is respectively positive, zero, -1 for edit, text, and hidden fields. For text and hidden fields, TEXT is respectively the string to be displayed on screen or saved to the answer file. For edit-fields, TEXT is a string containing `%v', presented on screen as a text where `%v' is replaced by a blank data enter area of width WIDTH (e.g \"Enrol date: %v. Use dd/mm/yy format\"). 

In TEXT, you can use special substrings replaced by computed values. The computed TEXT variable is the actual string displayed or saved. The special substrings are: `%c', replaced by the client computer name obtained from Windows environment variable \"COMPUTERNAME\"; `%b', replaced by time client starts in ISO format (but without time zone); `%%' replaced by a literal `%'.

For each editable or hidden field, an equivalent line is added to the local (`testmacs-loc-ans-file-pt') and the remote (`testmacs-net-ans-file-pt') answer file using the format NAME:VALUE. For edit fields, VALUE is the text entered by the student in the editable area; for hidden fields, VALUE is the computed TEXT. 

Edit and text fields are drawn on screen in the order they appear in `testmacs-default-fields' (possibly overridden by `testmacs-custom-fields'). You can use spaces or newlines in each TEXT variable.
WARNING: Due to a bug in the Emacs Widget Library, do not draw adjacent edit areas, without any character in the middle, e.g. consecutive fields whose TEXT is resp. \"text %v\" and \"%v text\".")
  
(defconst testmacs-loc-cust-fld "~/custfld.txt"
  "Local file with custom fields. If the file exists, it defines custom fields displayed immediately after the default fields, overriding default fields in `default-fields' with the same name. 
Each line of the file `testmacs-loc-cust-fld' has a custom-field entry with the format NAME:WIDTH:TEXT and an equivalent line is added to the local (`testmacs-loc-ans-file-pt') and the remote (`testmacs-net-ans-file-pt') answer file with the format NAME:VALUE. Parsed fields are added to the list `testmacs-custom-fields', therefore NAME, WIDTH, and TEXT are like the fields' elements of `testmacs-custom-fields'. 
Example:

project-date:10:Date when you delivered the class project: %v \\n
disp-seat-name:0:Computer name is %c
seat-name:-1:%c

\"project-date\" is an editable field and the text \"Date when you ...\" will be displayed replacing `%v' with an edititable area of 10-character width. Information entered is reported in the answer files as \"project-date:DATE\", where DATE is the value entered by the student. 
\"disp-seat-name\" displays on the subsequent line the screen text \"Computer name is foo\", where \"foo\" is the name of the computer where Testmacs is running. 
\"seat-name\" is similar to the preceding field, but it does not involve any screen display, only \"seat-name:foo\" is reported in the answer files.
To add line-breaks to TEXT use `n' preceeded by a single slash.")

(defconst testmacs-buffer-name "*Test*"
  "Name of the test buffer.")

(defconst testmacs-update-freq 10
  "Frequency of updates in seconds for countdown or saving.")

(defconst testmacs-no-answer-string "I do not answer."
  "Default value in case of missing answer.")

;;; === end of Customise Me
;;; =======================


;;; =================== ;;;
;;; === Global Vars === ;;;
;;; =================== ;;;

;;; We want global vars to work even if the buffer is not local
(defvar testmacs-net-ans-file-pt  nil
  "Path of remote answer file. The file is identical to the local answer file, whose format is described by the variable `testmacs-loc-ans-file-pt'.")

(defvar testmacs-loc-ans-file-pt  nil
  "Path of client local answer file.
Each line of the answer file (entry) has the format NAME:VALUE. The entries are the following:

DEFAULT ENTRIES
CUSTOM ENTRIES
ans-line:VALUE VALUE ...

DEFAULT ENTRIES contain student details entered by the student during the test or produced by the system.
They are set and documented by the variable `default-fields'. 
CUSTOM ENTRIES are optional and are defined in the file `testmacs-loc-cust-fld'.
\"ans-line\" contains answers entered. Each VALUE can be \"a\", \"b\" etc. (including quotes)  or `nil' (without quotes).")

(defvar testmacs-custom-fields nil
  "List of custom fields to insert on the screen answer sheet, with the same format as `testmacs-default-fields'.
If an `testmacs-custom-fields' field has the same name of an `testmacs-default-fields' field, the latter field is not showed on screen nor is added to the answer files. Definitions of fields are set in the file `testmacs-loc-cust-fld' and copied by the function `get-custom-fields' to `testmacs-custom-fields' list. 
Fields in `testmacs-custom-fields' cannot have duplicate names. See the function `parse-cust-field', for more information on acceptable field definitions.")

(defvar testmacs-custom-field-names nil
  "List of custom fields names, build with cars of element of `testmacs-custom-fields'.")

(defvar testmacs-header-fields nil
  "Alist to store header field names and values as strings. Header fields are those associated to the non-question area. Field names and values depends on the list structures `testmacs-default-fields' and `testmacs-custom-fields'. Each field pair NAME:VALUE is saved to the local (`testmacs-loc-ans-file-pt') and the remote (`testmacs-net-ans-file-pt') answer file every `testmacs-update-freq' seconds.")

(defvar testmacs-header-edit-names nil
  "Subset of keys in `testmacs-header-fields' alist including only field names associated to edit-fields. The names are used to set `testmacs-header-filled'.")

(defvar testmacs-header-filled nil
  "Non-nil if in `testmacs-header-fields' alist all the variables listed in `testmacs-header-edit-names' are set. This variable is updated every time the cursor leaves the edit widgets in the header areas by the hook function `testmacs-process-head'.")

(defvar testmacs-net-data-pt nil
  "Path of the remote share containing program data (answers, init and command files etc.). 
The path is read from a local server file identified by `testmacs-loc-server-ini'. If this variable is a wildcard and more server files are identified, the first valid path is used.")

(defvar testmacs-ans-text nil
  "The content to be saved in the answer file. This is a string updated by `testmacs-make-answer-text' whenever an `testmacs-header-fields' value is updated or an answer is given.")

(defvar testmacs-remaining-secs nil
  "Current countdown value in seconds as a number.")

(defvar testmacs-cmd-cache nil
  "Used for storing remote commands.")

(defvar testmacs-cmd-update-performed nil
  "Non-nil if an update has been performed from the remote data dir.")

(defvar testmacs-running-id  nil
  "Random number used written in `testmacs-running-cookie-pt' to detect multiple local app instances.")

(defvar testmacs-running-cookie-pt  nil
  "Path of client cookie with random `testmacs-running-id'. Used to detect multiple local app instances.")

(defvar testmacs-scheduler nil
  "Timer object to run scheduled tasks in `testmacs-schedule-hook' every `testmacs-update-freq' seconds.
To be used in case one needs to cancel timer.")

(defvar testmacs-scheduler-wait nil
  "Non-nil if the user is prompted  with a question. In this case some tasks in `testmacs-schedule-hook' might be postpones, until the user complete the answer.")


(defvar testmacs-net-course-pt nil
  "Path of course related net folder inside `testmacs-net-data-pt'.")

(defvar testmacs-answered-ones  nil
  "Total answered questions.")

(defvar testmacs-max-time-active nil
  "Maximum allowed time in minutes to complete the currently active test. Its initial value applies to multiple-choice (time for entering answers) and is retrieved from `testmacs-net-init' file. When the R test is running, its value is set to the value of `testmacs-max-time-r'")

(defvar testmacs-max-time-r nil
  "Maximum allowed time in minutes to complete the R test is running")

(defvar quest-count nil
  "Number of available questions. Retrieved from `testmacs-net-init' file.")

(defvar testmacs-course nil
  "Name of the course. Retrieved from `testmacs-net-init' file.")

(defvar testmacs-answers-given nil
  "Answer vector given by the students.")


;;; Buffer local vars used during the init phase or on click events
;;; ---------------------------------------------------------------


(defvar-local question-widgets nil
  "List of question widgets.")


;;; R configuration 
;;; ---------------------------------------------------------------
(defvar testmacs-r-executable (concat (file-name-directory (directory-file-name invocation-directory)) ; up one
				  "app/bin/i386/Rterm.exe")
  "R executable relative to Emacs invocation directory.")

(defvar testmacs-r-running-p nil 
  "Non-nil when R part of the exam is running.")


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
  "Expand wildcards in `testmacs-loc-server-ini' and use the first expanded path as a server configuration file. 
The first line of the conf file contains the Windows UNC path of the remote datadir, e.g.: 
\"\\\\server-name\\path-to\\data-dir\". The UNC path should be written in Windows style, without escaping backslashes. If wildcard expansion gives no file or the UNC path is nonexistent, throw an error, otherwise return UNC path."

  (let (serverp data-dir
	(loc-files (file-expand-wildcards testmacs-loc-server-ini)))
    (dolist (s loc-files)
      (when (not serverp)
	(setq data-dir
	      (car (split-string
		    (with-temp-buffer (insert-file-contents s) (buffer-string))
		    "\n"))
	      serverp (file-exists-p data-dir))))

    (when (not loc-files)
      (testmacs-err "File(s) `%s' not found." testmacs-loc-server-ini)
      (throw 'test t))
	
    (when (not serverp)
      (testmacs-err "No valid server/share in files %s" (mapconcat 'identity loc-files ", "))
      (throw 'test t))
    data-dir))


(defun set-running-id ()
  "Assign random value to `testmacs-running-id' and set cookie path."

  (setq testmacs-running-cookie-pt
	(make-path (file-name-directory testmacs-loc-server-ini) "RUNNING"))	
  (let (id)  
    (dotimes (_ 3 id)
      (setq id (cons (random 999999) id)))
    (setq testmacs-running-id (mapconcat 'number-to-string id "-"))))

(defun single-instance-init ()
  "On startup sequence, detect running instances if `testmacs-running-cookie-pt' cookie is found.
If none detected write the random `testmacs-running-id' to cookie periodic detection."

  (cond
   
   ;; A local cookie exists
   ((file-exists-p  testmacs-running-cookie-pt)
    (let ((ans (testmacs-choice 3 
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
   ((not (file-writable-cross-p  testmacs-running-cookie-pt))    
    (testmacs-err-cookie "Unable to write to local file `%s.'" testmacs-running-cookie-pt)
    (throw 'test t)))

  ;; If no concurrency detected, write random running-id used for periodic detection
  (with-temp-file testmacs-running-cookie-pt  (insert testmacs-running-id)))

(defun single-instance-update ()
  "On scheduled hook, if the cookie file is externally deleted, restore it; if its value does not match `testmacs-running-id', raise a concurrency error."

  ;; Restore if missing
  ;; use again file-writable-cross-p ?
  (unless (file-exists-p testmacs-running-cookie-pt)
    (with-temp-file testmacs-running-cookie-pt  (insert testmacs-running-id)))
  
  ;; Read cookie value
  (let (ans (id (with-temp-buffer
		  (insert-file-contents testmacs-running-cookie-pt)
		  (buffer-string))))

    ;; On mismatch raise error
    (unless (string= id testmacs-running-id)
      (setq testmacs-scheduler-wait t)
      (setq ans (testmacs-choice 3 "Local cookie mismatch. A concurrent app is running.\n
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
        (setq testmacs-scheduler-wait nil))

    (with-temp-file testmacs-running-cookie-pt  (insert testmacs-running-id)))
      
(defun delete-cookie ()
  "Safe delete `testmacs-running-cookie-pt' cookie"

  ;; Delete cookie and test result
  (if (file-exists-p testmacs-running-cookie-pt)
      (delete-file testmacs-running-cookie-pt))
  (let ((removed (not (file-exists-p  testmacs-running-cookie-pt))))
    (unless removed (testmacs-err-cookie "I am unable to delete the cookie `%s'. Try to do it manually."
				     testmacs-running-cookie-pt))
    removed))





;;; === end of FS Helpers
;;; =====================



;;; ======================== ;;;
;;; === Widget Functions === ;;;
;;; ======================== ;;;

(defun testmacs-process-head (widget var-name)
  "On updated head fields hook."
  (setcdr (assoc var-name testmacs-header-fields) (widget-value widget))
  (testmacs-make-answer-text)
  (testmacs-header-filled-set)
  (if testmacs-header-filled
      (testmacs-question-activation :activate)
    (testmacs-question-activation :deactivate)))

(defun testmacs-header-filled-set ()
  "Check whether edit-fields in the header area were filled and update `testmacs-header-filled' accordingly."
  (setq testmacs-header-filled
	(seq-every-p #'(lambda (elt) (< 0 (length (cdr (assoc elt testmacs-header-fields)))))
			     testmacs-header-edit-names)))

; 	(not (seq-filter 'null
; 			 (mapcar #'(lambda (elt) (> (length (cdr (assoc elt testmacs-header-fields))) 0))
; 				 testmacs-header-edit-names)))))

(defun testmacs-question-activation (status)
  "If STATUS is `:activate' or `:deactivate', activate or deactivate question widgets."
  (mapc #'(lambda (widget) 
	    (while widget
	      (widget-apply widget status)
	      (setq widget (widget-get widget :parent))))
	question-widgets))

(defun testmacs-process-answer (widget ith-quest)
  "On click answer hook."
  (let* ((ans (widget-value widget))
	 (ans-no-nil (if ans ans testmacs-no-answer-string)))
    (message "You clicked \"%s\"." ans-no-nil)
    (aset testmacs-answers-given (1- ith-quest) ans))
  (setq testmacs-answered-ones (length (remove nil testmacs-answers-given)))
  (testmacs-make-answer-text))

(defvar testmacs-mode-map
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

(defun testmacs-exit-ahead (&rest _)
  "Called by widget to query user to exit ahead of time.
In case of confirmation save form and exit."

  ;; The funct below is used to create an experience similar to C-x C-c
  ;; It will trigger related kill-emacs-query-functions
  (if testmacs-r-running-p  
      (save-buffers-kill-terminal)
    (if (testmacs-exit-hook) (testmacs-r-run))))

(defun testmacs-exit-hook ()
  "Hook called whenerever users asks to exit."
  (testmacs-save-test)
  (let (yes msg)
    (setq msg
	  (replace-regexp-in-string "\"" ""
				    (progn
				      (string-match "\\(ans-line:\\)\\(.+\\)" testmacs-ans-text)
				      (substring testmacs-ans-text  (match-end 1) (match-end 2)))))
    (setq msg
	  (concat  (unless testmacs-r-running-p  "Your current answers are:\n" msg)
		   "\n\nAre you **absolutely sure** you want to finish your test now?"))       
    ;; Works only for Linux GUI (setq yes (y-or-n-p-with-timeout msg testmacs-remaining-secs nil))
    (setq yes (y-or-n-p msg)) 
    (if yes (delete-cookie)
      (message "Exit canceled!"))
    yes))

(defun testmacs-exit-forced ()
  "Save answer string and exit. Dangerous for debugging, since unsaved material is lost!."
  (testmacs-save-test)
  (delete-cookie)
  (if testmacs-r-running-p  
      (kill-emacs)
    (testmacs-r-run)))

(defsubst testmacs-schedule-hook ()
  "Maintenance tasks run at form setup and every subsequent `testmacs-update-freq' seconds.
A) Decrement `testmacs-remaining-secs' by the value in `testmacs-update-freq' and force headeline update.
B) Save answer string locally and remote. C) Check for concurrent instance of the exam app.
D) Check for remote commands.

Note that variables used here shoul not be buffer local."

  ;; Exit when time is over
  (if (< testmacs-remaining-secs 0) (testmacs-exit-forced))

  ;; Or update countdown
  (setq testmacs-remaining-secs  (- testmacs-remaining-secs testmacs-update-freq))
  (force-mode-line-update t)

  ;;Test for single instance
  (single-instance-update)
  
  ;; Save answers-given
  (testmacs-save-test))

(defun testmacs-save-test ()
  "Save answer string. Note that variables used here are not buffer local.
Note that variables used here are not buffer local."

  (testmacs-set-last-saved)
  (with-temp-file testmacs-loc-ans-file-pt  (insert testmacs-ans-text))
  (with-temp-file testmacs-net-ans-file-pt  (insert testmacs-ans-text))
  (testmacs-remote-cmds))

(defun testmacs-set-last-saved ()
  "Update \"last-saved\" field in `testmacs-ans-text' string."
  (setcdr (assoc "last-saved" testmacs-header-fields) (format-time-string "%FT%T"))
  (testmacs-make-answer-text))

(defun testmacs-remote-cmds ()
  "Execute remote commands."
  
  ;; Manage remote exit command
  (when (string= testmacs-cmd-cache "exit007")
    (delete-cookie)
    (kill-emacs)) 
  (when (file-exists-p (make-path testmacs-net-data-pt  "exit007"))
    (setq testmacs-cmd-cache "exit007")
    (message "Exit in 10 seconds"))

  ;; Manage remote update command
  (if (file-exists-p (make-path testmacs-net-data-pt  "update007"))
      (remote-update)))

(defun testmacs-err (str &rest pars)
  "Critical message, involving subsequent user exit. The string STR can be formatted with PARS parameters. 
Remove the cookie, kill hooks and possibly the close answer form and stop its timer, without saving answer files. If necessary, call `testmacs-save-test' before this."
  (testmacs-err_ t str pars))

(defun testmacs-err-cookie (str &rest pars)
  "Like `testmacs-err' but leaves the cookie."
  (testmacs-err_ nil str pars))

(defun testmacs-err_ (remove-cookie str &rest pars)
  "Workhorse for `testmacs-err' and `testmacs-err-cookie'. REMOVE-COOKIE is non-nil if cookie is to be removed."
  
  (switch-to-buffer "blank")
  (setq inhibit-read-only t)
  (erase-buffer)
  (insert "Report Issue to the Instructor\n------------------------------\n\n")
  (let ((mess (apply 'format str (car pars))))
    (insert mess))
  (setq inhibit-read-only nil)
  (cleanup)
  (if remove-cookie (delete-cookie)))

(defun testmacs-choice (choice-count str &rest pars)
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

(define-derived-mode testmacs-mode nil "Test"
  "Major mode for playing `test'.

The key bindings for `testmacs-mode' are:

\\{testmacs-mode-map}"

  (define-key widget-field-keymap (kbd "C-x") 'do-nothing)
  (define-key widget-field-keymap (kbd "C-c") 'do-nothing)
  (setq truncate-lines  nil)
  (buffer-disable-undo))

(defun testmacs-mode-header (max-time)
  "Set the header-line for test mode and initialize countdown timer."

  ;; Set header-line
  (setq header-line-format
	'(:eval
	  (format " Residual minutes: %s | Answered: %d out of %d      Ver. %s"
		  (format "%02d"  (+ (/ testmacs-remaining-secs 60) 1)) ; countdown as a minute string
		  testmacs-answered-ones ;(buffer-local-value 'testmacs-answered-ones (get-buffer testmacs-buffer-name))
		  quest-count ;(buffer-local-value 'quest-count (get-buffer testmacs-buffer-name))
		  testmacs-version
		  )))

  ;; Init countdown
  (setq testmacs-remaining-secs  (* max-time 60))

  ; (setq testmacs-scheduler (run-with-timer 0 testmacs-update-freq 'testmacs-schedule-hook))
  )

(defun read-inits ()
  "Obtain remte data-dir from the local file `testmacs-loc-server-ini' and read there init values from `testmacs-net-init' file. Wildcards are expanded, if any,  and the first (valid) path is used."

  ;; Set server paths local init file 
  (setq testmacs-net-data-pt (get-data-dir))   

  ;; Set remote init file
  (let*  (init-file-pt txt ans-file-name)
   
    ;; Take the first expanded path 
    (setq init-file-pt
	  (car 
	   (file-expand-wildcards
	    (make-path testmacs-net-data-pt testmacs-net-init))))
    
    (when (not init-file-pt)
      (testmacs-err "No file matching `%s'."  (make-path testmacs-net-data-pt testmacs-net-init))
      (throw 'test t))
    
    ;; Read init file vars
    (setq txt
	  (split-string
	   (with-temp-buffer
	     (insert-file-contents init-file-pt)
	     (buffer-string)) "\n")
	  txt (mapcar 'split-string  (butlast txt))
	  txt (cl-pairlis (car txt) (cadr txt))

	  testmacs-max-time-active
	  (string-to-number (cdr (assoc "time" txt)))

	  testmacs-max-time-r
	  (string-to-number (cdr (assoc "time-r" txt)))
	  
	  quest-count
	  (string-to-number (cdr (assoc "questcount" txt)))
	  testmacs-course  (cdr (assoc "course" txt))
	  testmacs-net-course-pt
	  (make-path testmacs-net-data-pt (concat testmacs-course "-answers"))
	  ans-file-name (concat testmacs-course "-ans-" (downcase (getenv "COMPUTERNAME")) ".txt")	  
	  testmacs-net-ans-file-pt (make-path testmacs-net-course-pt ans-file-name)
	  testmacs-loc-ans-file-pt (make-path (file-name-directory testmacs-loc-server-ini) ans-file-name))))

(defun testmacs-make-answer-text ()
  "When a field is updaded this syncs `testmacs-ans-text' with header field values and answers."
  (let ((ans-line
	 (format "ans-line:%s" (replace-regexp-in-string  "[][]" "" (prin1-to-string testmacs-answers-given))))
	(head-fields
	 (mapconcat (lambda (elt) (format "%s:%s\n" (car elt) (cdr elt)))  testmacs-header-fields "")))
    (setq testmacs-ans-text (concat head-fields ans-line))))


(defun testmacs-make-dirs ()
  "Make remote course dir in `testmacs-net-data-pt' and test for local and remote write access. If remote answer file `ans-file-name' exits, throw an error. If remote course dir exists (possibly with some answer files), prompt to proceed."

  ;; Test access to remote data dir
  (when (not (file-accessible-directory-p  testmacs-net-data-pt))    
      (testmacs-err "Unable to write to remote dir `%s.'" testmacs-net-data-pt)
      (throw 'test t))

  ;; Do not overwrite answer file
  ;; It seems better to test answer file error before answer dir warning
  (when (file-exists-p testmacs-net-ans-file-pt)
    (testmacs-err "Remote answer file `%s' alredy exists!"  
	     (file-name-nondirectory testmacs-net-ans-file-pt))
    (throw 'test t))

;  ;; Confirm to go if answer dir exists
;  (when (file-directory-p testmacs-net-course-pt)
;    (save-excursion 
;      (testmacs-err "Remote answer directory already exists.
;Answer to the question below to proceed.")
;      (unless
; 	  (yes-or-no-p "Do you want to proceed? ")
; 	(kill-emacs))))
  (make-directory testmacs-net-course-pt t)
  
  ;; Test access to remote course dir
  (when (not (file-accessible-directory-p  testmacs-net-course-pt))    
      (testmacs-err "Unable to write to remote dir `%s.'" testmacs-net-course-pt)
      (throw 'test t))
  
  ;; Test access to remote answer file  
  (when (not (file-writable-cross-p testmacs-net-ans-file-pt))
      (testmacs-err "Unable to write to remote file `%s.'" testmacs-net-ans-file-pt)
      (throw 'test t))
  (with-temp-file testmacs-net-ans-file-pt (insert "Test write"))

  ;; Test access to local answer file  
  (when (not (file-writable-cross-p  testmacs-loc-ans-file-pt))    
    (testmacs-err "Unable to write to local file `%s.'" testmacs-loc-ans-file-pt)
    (throw 'test t))
  (with-temp-file testmacs-loc-ans-file-pt  (insert "Test write")))

(defun make-head-notify (field-varname)
  "Make the notify property to be added to the edit fields in the header area of the test form.
The property triggers the function `testmacs-process-head' each time a key is pressed in the edit area.
The property is a lambda whose body contains the name of the field riceived by FIELD-VARNAME."
  (list 'lambda `(widget &rest _) (list 'testmacs-process-head `widget field-varname)))

(defun add-edit-field (name width text)
  "Add the edit field with name NAME, width WIDTH and text TEXT."
  (widget-create 'editable-field
		  :size width
		  :format text
		  :notify (make-head-notify name)
		  ""))
;; Add-edit-field generalizes
;; (widget-create 'editable-field
;;  	       :size 10
;;  	       :format "Some text: %v "
;;  	       :notify (lambda (widget &rest _) (testmacs-process-head widget 'varname))
;;  	       "")
		     
(defun testmacs-insert-header ()
  "Insert test header used to collect student details or display information."
  
  (let* ((def-field-names (mapcar 'car testmacs-default-fields))
	 (def-names-str (mapconcat 'identity def-field-names " "))
	 unique-fields common-fld-names)

    ;; Check for duplication errors in setting `testmacs-default-fields' 
    (when (dups-p def-field-names)
      (testmacs-err
       "The constant `testmacs-default-fields', set by the main program module, has duplicate field names:\n%s"
       def-names-str)
      (throw 'test t))

    ;; Build custom field list
    (get-custom-fields) ; fills testmacs-custom-fields, testmacs-custom-field-names

    (setq common-fld-names (seq-intersection  testmacs-custom-field-names def-field-names))


;    (mapcar (lambda (elt) ; Build unique list with default fields possibly overridden by custom fields 
; 	      (if (member (car elt)  common-fld-names)	       
; 		  (add-to-list 'unique-fields (assoc (car elt) testmacs-custom-fields) t)
; 		(add-to-list 'unique-fields elt t)))
; 	    testmacs-default-fields)

    ;; Create unique list with default fields not redefined as custom + custom fields
    (setq unique-fields
	  (append unique-fields
		  (seq-filter (lambda (elt) (not (member (car elt) common-fld-names)))
			      testmacs-default-fields)
		  testmacs-custom-fields))
    
    ;(setq unique-fields   ; Append remaining (non common) custom fields to unique field list 
    ; 	  (append unique-fields
    ; 		  (seq-filter (lambda (elt) (not (member (car elt) common-fld-names)))
    ; 				  testmacs-custom-fields)))

    ;; Create alist with field names
    (setq testmacs-header-fields nil
	  testmacs-header-edit-names nil)
    (mapc (lambda (elt) (add-to-list 'testmacs-header-fields (list (car elt)) t))
	  unique-fields)

    ;; For each element of unique-fields add an edit field 
    (widget-insert "\n")    
    (let* (w
	   (wds unique-fields)
	   (comp-name (downcase (getenv "COMPUTERNAME")))
	   (begin-time  (format-time-string "%FT%T"))

	   name width text
	   
	   ;; Replace %c with compname and escape %%
	   (rep (lambda (s)  
		  (thread-last 
		      (replace-regexp-in-string "%\\{1\\}c" comp-name s  nil 'literal)
		      (replace-regexp-in-string "%\\{1\\}b" begin-time)
		      (replace-regexp-in-string "%\\{1\\}e" begin-time)
		    (replace-regexp-in-string "%%" "%" )))))

    
      (while (setq w (pop wds))
	(setq name  (nth 0 w)
	      width (nth 1 w)
	      text  (funcall rep (nth 2 w)))

	(cond 
	 ;; Add text only
	 ((eq width 0)
	  (assq-delete-all name testmacs-header-fields) ; name points to value, so works with assq
	  (widget-insert text))
	 	 
	 ;; Add store hidden fields
	 ((eq width -1)
	    (setcdr (assoc name testmacs-header-fields) text))

	 ;; Add editable field widget
	 ((> width 0)
	  (add-to-list 'testmacs-header-edit-names name 'append); Store edit field names 
	  (add-edit-field name width text))))
      
      (widget-insert "\n"))))
    
(defun testmacs-insert-question (ith-quest)
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
  (add-to-list 'question-widgets  
	       (widget-create 'radio-button-choice
			      :value nil
			      :notify (lambda  (widget &rest _)
					(testmacs-process-answer widget ith-quest))
			      '(item "a") '(item "b") '(item "c") '(item "d") '(item "e")
			      (list 'item :tag testmacs-no-answer-string :value nil))
	     'append)
  (insert "\n"))

(defun testmacs-insert-finish ()
  "Insert the finish button for the QUESTIONS."
  (widget-create 'push-button
                 :notify 'testmacs-exit-ahead
                 :help-echo "Click if you don't want to continue. You have to confirm your wish."
                 "Exit now!"))

;;; === end of Main Form Setup Functions
;;; ====================================


;;; ======================= ;;;
;;; === Remote Commands === ;;;
;;; ======================= ;;;

(defun remote-update ()
  "Update local \"site-start.el\" and possibly the local custom-field file with equivalent remote files  \"new-site-start.txt\" and \"new-custfld.txt\" in `testmacs-net-data-pt'. 
Update results are written in the folder  \"update-performed\" in `testmacs-net-data-pt'.
The name of local custom file is set in `testmacs-loc-cust-fld' the remote name is obtained adding the \"new-\" prefix."

  (catch 'update 
    ;; Update already done
    (if testmacs-cmd-update-performed (throw 'update t))

    (if (not (file-exists-p (make-path testmacs-net-data-pt  "update007")))
	(throw 'update t))
    
    (message "Updating `site-start.el'") 
    (let* ((site-dir  (expand-file-name "../share/emacs/site-lisp" invocation-directory))
	   (original-site-start (make-path site-dir "site-start.el"))
	   (local-new-site-start (make-path site-dir "new-site-start.txt"))
	   (remote-new-site-start (make-path testmacs-net-data-pt "new-site-start.txt"))
	   (update-dir-pt (make-path testmacs-net-data-pt "update-performed"))
	   (remote-result-file  (concat "updated-" (downcase (getenv "COMPUTERNAME")) ".txt"))
	   (remote-result-file-pt (make-path update-dir-pt remote-result-file))	     	     
	   new-content old-content res-content

	   ;; Custom fileds
	   (new-custom-flds (concat "new-" (file-name-nondirectory testmacs-loc-cust-fld)))
	   (remote-new-custom-flds (make-path testmacs-net-data-pt new-custom-flds))
	   (local-new-custom-flds (make-path (file-name-directory testmacs-loc-cust-fld) new-custom-flds)))

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
	(copy-file local-new-custom-flds testmacs-loc-cust-fld t)

	;; Overwrite original file with local copy
	(setq new-content
	      (with-temp-buffer (insert-file-contents local-new-custom-flds) (buffer-string)))
	(setq old-content
	      (with-temp-buffer (insert-file-contents testmacs-loc-cust-fld) (buffer-string))) 
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
      (setq testmacs-cmd-update-performed t))))


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
  "When reading `testmacs-loc-cust-fld', return statically sets and return the current line number. 
An optional ACTION argument is accepted. Before returning line number, if ACTION is 'init, the value is set to zero; if ACTION is 'inc, the value is incremented by one.")


;; "Possibly fill `testmacs-custom-fields' and `testmacs-custom-field-names' with data from `testmacs-loc-cust-fld'."

(defun get-custom-fields () 
      "Read custom field file `testmacs-loc-cust-fld'  and create a list of custom fields. 
Each file line has the format NAME:WIDTH:TEXT, whose meaning is that of the elements of `testmacs-custom-fields'.
Blank lines, if any, are skipped. If no errors are detected, `testmacs-custom-fields' and `testmacs-custom-field-names' are filled. Errors include duplicate field names. See `parse-cust-field' acceptable field definitions."

      (setq testmacs-custom-fields nil
	    testmacs-custom-field-names nil)
      (when (file-exists-p testmacs-loc-cust-fld)
	(let ((cust-flds-buf (split-string
			      (with-temp-buffer (insert-file-contents testmacs-loc-cust-fld) (buffer-string))
			      "\n"))
	      custflds entry)

	  ;; Init cursor 
	  (custom-field-cursor 'init)

	  ;; Fill custom field list
	  (while (setq entry (pop cust-flds-buf))
	    (custom-field-cursor 'inc)
	    (if (setq entry (parse-cust-field entry))	 
		(push entry custflds)))
	  (setq testmacs-custom-fields (reverse custflds)))

	;; Test duplicates
	(setq testmacs-custom-field-names (mapcar 'car testmacs-custom-fields))
	(if (dups-p testmacs-custom-field-names)
	    (parse-err "Duplicate custom fields:\n%s" (mapconcat 'identity testmacs-custom-field-names " ")))))

(defun parse-cust-field (line)
      "Parse a line from the custom field file `testmacs-loc-cust-fld' and return a list (NAME WIDTH TEXT). 
The function `get-custom-fields' uses the returned list to fill the list `testmacs-custom-fields' and the car, NAME, to fill `testmacs-custom-field-names'. 
NAME can only have alphanumeric characters or the four literals `-_.'.  WIDTH should be non-negative and not more than 100. 
See the variable `testmacs-custom-fields' for the meaning of the returned list elements." 

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
See `testmacs-err' for more safe belts."
  (let ((errmess "Error in custom field file `%s', line %d\n")
	(cursor  (list testmacs-loc-cust-fld (custom-field-cursor))))
    (apply 'testmacs-err (concat errmess msg) (append cursor ags)))
  (throw 'test t))

(defun parse-err (msg &rest ags)
  "A version of `parse-err-ln ' not printing the number of the line parsed."
  (let ((errmess "Error in custom field file `%s'\n"))    
    (apply 'testmacs-err (concat errmess msg) (append (list testmacs-loc-cust-fld) ags)))
  (throw 'test t))

;;; === end of Get Custom Fields
;;; ============================


;;; ============= ;;;
;;; === Main  === ;;;
;;; ============= ;;;

(defun setup-form ()
  "Main widget setup function."

  (let ((buffer (get-buffer-create testmacs-buffer-name)))
    (with-current-buffer buffer

      ;; The first thing as this mode kills any buffer local var
      (testmacs-mode)

      ;; Init vars and make dirs
      (read-inits)
      (setq testmacs-answered-ones 0)
      (setq testmacs-answers-given (make-vector quest-count nil))
;      (testmacs-make-answer-text)
      (testmacs-make-dirs)
      
      ;; Set header-line (will start timed functions)
      (testmacs-mode-header testmacs-max-time-active)

      ;;Make form 
      (testmacs-insert-header)
      (cl-loop for i from 1 to quest-count
	       do (testmacs-insert-question i))
      (testmacs-insert-finish) ;)
      (widget-setup) ;  adds a read-only mode outside widgets
      (testmacs-question-activation :deactivate)
      (widget-forward 1)

      ;; Update countdown and save answers every testmacs-update-freq seconds
      (testmacs-make-answer-text)
      (setq testmacs-scheduler (run-with-timer 0 testmacs-update-freq 'testmacs-schedule-hook)))

    (switch-to-buffer buffer))

  (run-at-time "1 sec" nil (lambda () (message "Good luck with your test!")))

  ;; Better as last item, so we can easily close Emacs in case of failures
  (add-hook 'kill-emacs-query-functions 'testmacs-exit-hook))

(defun cleanup ()
  "Kill possilbe reserved buffers, timer and kill hooks except the message buffer \"blank\". 
For debug scenarios or after raising exceptions."

  (set 'kill-emacs-query-functions nil)
  (if (timerp testmacs-scheduler) (cancel-timer testmacs-scheduler)) 
  (if (get-buffer testmacs-buffer-name)
      (kill-buffer testmacs-buffer-name)))
  
(defun test ()
  "Generate the multiple choice test based on `testmacs-net-init'."
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



;;; ================= ;;;
;;; === Manage R  === ;;;
;;; ================= ;;;

(defun testmacs-r-run ()
  "Run R"
  (message "Starting second part of the test...")
  (setq testmacs-r-running-p  t)
  (require 'ess-r-mode)
  ;; No smart comma ess-handy-commands
  (define-key inferior-ess-mode-map (kbd ",")  nil )

  (setq inferior-R-program-name testmacs-r-executable)
  (setq ess-ask-for-ess-directory nil) ; Don't prompt for data dir
  (setq ess-use-tracebug nil) ; no debug
  ;; History
  (let ((hfile (concat "~/" testmacs-course "-hst-" (downcase (getenv "COMPUTERNAME")) ".txt")))
    (write-region "" nil hfile)
    (setq ess-history-file hfile))
  (setq default-directory (expand-file-name "~"))
  (R)
  (delete-other-windows)
  (kill-buffer "*Test*")
  (testmacs-mode-header testmacs-max-time-r)
  (cua-mode)
  
  ;; Capture R buffer to messages and clean if last R commmand is: message("Success")
  (let* ((rstart-buf (buffer-substring-no-properties (point-max) (point-min)))
	 (rstart-buf-list (split-string rstart-buf "\n"))
	  ;; R Testmacs script should end with "Success\n> setwd('path/to/testmacs/data')\n> "
	 (succ-line (car (last rstart-buf-list 3))))
    (message (concat "===R STARTUP===\n" rstart-buf "===end R STARTUP\n"))
    (if (not (string-equal succ-line "Success"))
	(message "An error occurred!")	
      (comint-clear-buffer)
      (ess-eval-linewise "message(\"Run the command: info() or giveup()\")" 'invis)
      (message "You are ready to go!"))))

;; Kill on exit R
(advice-add 'ess-process-sentinel :after #'testmacs-r-exit-function)
(defun testmacs-r-exit-function (proc message)
  "Kill Emacs on R exit"
  (delete-cookie)

  ;; Copy local rds
  (let ((loc-ans-rds-pt (concat (file-name-sans-extension testmacs-loc-ans-file-pt)  ".rds"))
	(net-ans-rds-pt (concat (file-name-sans-extension testmacs-net-ans-file-pt)  ".rds")))


    (delete-file net-ans-rds-pt)
    (if (file-exists-p net-ans-rds-pt) (delete-file net-ans-rds-pt)) ; 2nd attempt

    ;; copy only if previous local copy was deleted  
    (copy-file loc-ans-rds-pt net-ans-rds-pt t)
    (if (not (file-exists-p net-ans-rds-pt)) (copy-file loc-ans-rds-pt net-ans-rds-pt t)))


  ;;for debug
  ;;(with-temp-file "~/kill-hook"  (insert "kill hook called"))

  
  (kill-emacs))


  

;;; === end of Manage R 
;;; ===================



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
      (cancel-timer testmacs-scheduler)
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
  ;; (setq testmacs-remaining-secs 1000)
  ;; (cancel-timer testmacs-scheduler)
  ;; (kill-emacs)
  
)

;;; === end of Debug Functions
;;; ==========================

;;; Main, Main Form Setup Functions;
;;; Customise Me, Global Vars, Style
;;; FS Helpers, Widget Functions, Stop Hooks, Remote Commands, Get Custom Fields, Debug Functions


;;; FIRE!
(test)

