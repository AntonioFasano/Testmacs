<!--

pandoc README.md -o README.html

//-->



<!-- Not supported in GitHub

<style>
body {
    background-color: linen;
}

h1 {
    color: maroon;
    margin-left: 40px;
}

img { width: 100%;
	 
     border:1px solid #021a40;
}

</style>

//-->

# Testmacs

<!-- Not supported in GitHub
Administer classroom tests over a LAN 
//-->

Testmacs is intended as an e-learnig support tool, in particular for finance students. 


The application can implement  classroom  tests and is incorporating R extensions. 

The student is given a paper-sheet with a test ID and the questions' text.   
On screen, Testmacs asks for test ID plus some  personal student details.
Questions are without question-text, e.g.: 

    Question N:
    [] a
    [] b 
    [] c 
    ... 
    [] I do not know.

The test shows a mode line with answered questions and a countdown in minutes.
At countdown expiration Testmacs exits, saving answers.
At predefined times (10 seconds) the answers are saved locally and remotely.

![Program screenshot](figs/screen.png)

The paper test may look like follows (click for equivalent PDF):

[![Sample test image](figs/test.png)](testmk/R/finance101-template/finance101.pdf)

After the test, a result PDF can be automatically produced (click for equivalent PDF):

[![Resulting PDF image](figs/result.png)](figs/results/result.pdf)



## Other Features and Customisations

Answers are stored locally in the parent of `exam-loc-server-ini` and remotely in `exam-net-course-pt`.
To find the remote share, the file retrived from `exam-loc-server-ini` is used.   
Answers collected on the remote folder as text files can be easily parsed with any program to assign grades.

### Default Entries
Before the question area, the computer screen reports some fields to collect student details. By default they are:
 
    Test num.: _______
    Given Name(s): _______________________  Family Name: _____________________________
    Student ID: ___________________
 
An equivalent answer file is produced locally and remotely (as set by the variables `exam-loc-ans-file-pt` and `exam-net-ans-file-pt`. The asnwer file will be similar to the follwing:
 
    exam-id:123
    given-name:John
    family-name:Doe
    student-id:1234567
    ans-string:"b" "b" nil nil "b" nil "a" "b" nil "a" nil nil nil nil nil
 
The values after the colon for `exam-id`, `given-name`, `family-name`, and `student-id` depend on the respective values typed by the student for Test num., Given Name(s), Family Name and Student ID. 
 
`ans-string` is clearly a list of the answer given `nil` being the answers not given.
 							       
### Custom Entries
You can customise the fields adding the file `~/custfld.txt`. Note that the Windows launcher redirects the home directory `~` to the subdirectory `data` found in Testmacs package. Each line in this file has a custom-field entry with the format `Name:Width:Text`.    
`Name` is the field name as reported in the answer files.   
`Witdh` is the width of the user typing area, but note that the initial width will dynamically expads as the user types.    
`Text` is the text describing the information to be entered, displayed on the screen to the left of the typing area.  However, if `Width` is 0, the field is only informative and there is no information to type. `Width` can be -1, in which case the nothing is displayed on screen, just the the combination `Name:Text` is reported in the answer files for further processing.

Example:

    project-date:10:Date when you delivered the class project: %v \n
    disp-seat-name:0:Computer name is %c\n
    seat-name:-1:%c
 
`project-date` is an editable field and the text `Date when you ...` will be displayed replacing `%v` with an edititable area of 10-character width. Information entered is reported in the answer files as `project-date:DATE`, where DATE is the value typed by the student. 
`disp-seat-name` displays on the subsequent line the screen text "Computer name is foo", where "foo" is the name of the computer where Testmacs is running. 
`seat-name` is similar to the preceding field, but it does not involve any screen display, only `seat-name:foo` is reported in the answer files.
To add line-breaks to `Text` use `\n` with a single slash.
 
Customs fields are displayed immediately after default fields area. If you include a default field in  `~/custfld.txt`, that field will be removed from default field area.

Read the Elisp docstring of `exam-loc-cust-fld` for more information.

### Remote Commands
Testmacs performs some actions if detects predefined command filenames in the
  remote directory `exam-net-data-pt`. See action for each command filename.
Command filename "exit007": Emacs will exit in 10 seconds.   
Command filename "update007": Emacs updates `site-start.el` with the file `new-site-start.txt`
in the remote directory `exam-net-data-pt` and possibly the file `custfld.txt` with remote `new-custfld.txt`.
If `new-site-start.txt` is not found or there is a copy error a non-critical error is displayed
until the action succeeds or the command filename is removed. Read the docstring of `remote-update` function for more information. 


## R test

### Students side: submitting the R test

After exiting the MCQ test, an R console shows up, also the displayed timer is reset.  
If you don't want to continue with the R test, type `giveup()` to close Testmacs.

To work out your R test, start by getting its prompt with:

```r
info()
```

Read the prompt, and in particular your test's input variables, which come preloaded in your R environment.   
Determine what are the output variables that you should calculate and send.  
Make your calculations in the R console and, when you are done, assuming you want to send the variables `a` and `b`, use:

```r
send(a=a, b=b) 
```

Make sure the sent variables match exactly the names and classes required by the prompt.
At this point, your test solution is sent and Testmacs closes.   
Testmacs closes anyway if the time expires.



### Instructor side: creating the R test

To be done


## Intallation notes

To be done

