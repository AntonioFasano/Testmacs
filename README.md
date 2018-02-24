# Testmacs
Administer classroom tests over a LAN 


Testmacs implements a simple multiple-choice test.
The test header lines ask for test ID and student details.
Questions are without question-text like: Question N; a), b) c) ... I do not know.
The student is given a separate paper-sheet with a test ID and the question text.
The test shows a mode line with answered questions and a countdown in minutes.
At countdown expiration Emacs exits, saving answers.
At predefined times (10 seconds) the answers are saved locally and remotely.

Answers are stored locally in the parent of `exam-loc-server-ini` and remotely in `exam-net-course-pt`.
To find the remote share, the file retrived from `exam-loc-server-ini` is used.
Emacs performs some actions if detects predefined command filenames in the remote directory `exam-net-data-pt`. See action for each command filename.
Command filename "exit007": Emacs will exit in 10 seconds.
Command filename "update007": Emacs updates `site-start.el` with the file `new-site-start.txt`
in the remote directory `exam-net-data-pt`. If this file is not found or there is a copy error
a non-critical error is displayed until the action succeeds or the command filename is removed.

Ansewer collected on the remote as text files can be easily parsed with any program to assign grades.

*This is still a beta*

