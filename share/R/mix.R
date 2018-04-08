
## Parse an exam class TeX document based on multiple choices.
## Generate distinct PDFs with questions and extract related solution data file .
##
## Do not put non-question  material among \question commands!
## Such as: "Beginning of Maths question", that would become part of the preceding question
## Put \begin{document}  on a single line

## Customise
TIME=35            # Max time in minutes
NQ=15              # Questions to randomly extract from LaTeX template 
WDIST=c(`1`=15)    # Like c(`2`=10, `3`=7): 10 quests with weight 2 etc.
NOTPLWEIGHT=TRUE   # In LaTeX template set any \question[n] to \question, which means 1 point  
MULTI=2            # Weight factor. Useful if LaTeX "\question"-weights are missing/removed
OUTDIR="!tmpout"   # Output dir
PERLBDIR="c:\\strawberry\\perl\\bin"  # Perl bin dir


## Requitements:
## - an exam TeX doc with:
##     - solutions (\printasnwers uncommented),
##     - equal number of answers for each question,
## - Perl for TeX latexpand

## Globals
TESTCOUNT=NULL # Number of exams to generate. Found in TESTCOUNT.txt
COURSE=NULL    # Course processed. Found in TESTCOUNT.txt 
COURSEDIR=NULL # Course dir in OUTDIR with PDFs, sols and lisp initfile 


makeOutDir=function(){ # Create output dir
    if(dir.exists(OUTDIR)) unlink(OUTDIR, recursive=TRUE)
    if(dir.exists(OUTDIR)) stop("Unable to delete directory ", OUTDIR)
    dir.create(OUTDIR)
    if(!dir.exists(OUTDIR)) stop("Unable to create directory ", OUTDIR)
}

makeTemplate=function(){ # Create course dir and copy latexexapnd template

    dir.create(COURSEDIR)    

    ## Copy expanded as non-commented and without dependencies template
    src <- paste0(COURSE, "-template", "\\", COURSE, ".tex")
    exp <- paste0(COURSEDIR, "\\", COURSE, "-expd.tex")
    ags <- paste0("--empty-comments ", src, " --output ", exp)
               
    if(!grepl("strawberry", Sys.getenv("PATH"))) Sys.setenv(PATH=paste0(PERLBDIR, ";", Sys.getenv("PATH")))
    ret=system2("latexpand", ags, stdout=TRUE, stderr=TRUE)
    if(!is.null(attr(ret, "status"))) stop("pdflatex gave: ", paste(ret, collapse="\n"))   

    ## Get template tex file
    readLines(paste0(COURSEDIR, "/", COURSE, "-expd.tex"))
}

getQuestions=function(# Extract from TeX template 1,3 point questions and pre-question material (header) 
                      tex){

    ## Get lines with "\question" command 
    rx=which(grepl("^\\s*\\\\question", tex))
    rx=c(rx,  which(grepl("^\\s*\\\\end\\s*\\{questions\\}", tex)) ) # add line with "\end{questions}

    ## Identify header from first line to line before first question 
    hlines=tex[1:(rx[1]-1)]

    ## Extract questions as lines between two \question commands (including 1st \question cmd) 
    quests=mapply(function(i,j) tex[i:j], rx[-length(rx)], (rx-1)[-1])

    ## Remove weights
    if(NOTPLWEIGHT) {
        ## "\question[n]" becomes only "\question[n]"
        quests <- lapply(quests, function(q)
            sub("\\\\question *\\[ *[[:digit:]]+ *\\]", "\\\\question", q))
    }
    

    ## Get weights 
    ## "\question[n]" have weight n, the others weight 1
    w <- sapply(quests, function(q) sub("\\\\question", "", q[1]))
    w <- as.numeric(gsub("\\[|\\]", "", w))
    w[is.na(w)] <- 1

    ## Test WDIST var
    if(any(grepl("[[:alpha:]]", names(WDIST)))) stop("WDIST names are not all numeric.")
    if(!is.numeric(WDIST)) stop("WDIST values are not all numbers.")
    if(sum(WDIST)!=NQ){
        print(WDIST)
        stop("WDIST variable is not compatible with NQ=", NQ, " questions.")}

    ## Check if weight found in LaTeX template are sufficient for desired WDIST
    ## Accounting for NOTPLWEIGHT==TRUE
    x <- table(w)
    if(any(sapply(names(WDIST), function(wn) is.na(x[wn]) || x[wn] <= WDIST[[wn]]))){
        message("Template")
        print(table(dummy<-w))
        message("WDIST")
        print(WDIST)
        stop("WDIST values are not compatible with weights found in LaTeX template",
             " (given the value of NOTPLWEIGHT).")
    }
    
    ## Find solutions
    quests.sol <- data.frame(sol=findSol(quests), weight=w, stringsAsFactors=FALSE)    

    ## preamble + begin{document}
    x=grep("^\\s*\\\\begin\\s*\\{document\\}", hlines)
    preamble <- hlines[1:x]
    hlines <- hlines[-(1:x)] # after begin document

    list(preamble=preamble, 
         hlines=hlines,
         quests=quests,
         quests.sol=quests.sol)       
}

findSol=function(# Given the question list, find and return the correct choice letter
                 quests){
    pat="^\\s*\\\\CorrectChoice|^\\s*\\\\choice"
    sapply(quests, function(q) {
        x <- regmatches(q, regexpr(pat,  q))
        letters[1:length(x)][  grepl("\\\\CorrectChoice", x) ]
    })}
    


makeRandExam=function(# Extract rnadom questions distributed according to WDIST 
                     testid,      # Random testid
                     preamble,    #including being document
                     hlines,      # Pre-questions header lines
                     quests,      # question list
                     quests.sol   # solution's DF
                     ){
    
    ## Add Test ID after begin document
    x=sprintf("\n\n\\textbf{Test num. %02d}\\medskip", testid)
    hlines <- c(x, hlines)
    
    ## Set closing 
    foot=tex.qfoot()
    
    ## Split and order by weight 
    w <- quests.sol[["weight"]]
    oquests <- split(quests, w)
    oquests.sol <- split(quests.sol, w)

    ## Make a sample vector for each weight 
    f <- function(w, n){
        set.seed(testid)
        sample(length(oquests[[w]]), n)}
    smp=mapply(f, names(WDIST), WDIST, SIMPLIFY = FALSE)

    ## Extract random questions and related sol   
    f <- function(w, svec) {oquests[[w]][svec]}
    quests <- Reduce(c, mapply(f, names(smp), smp, SIMPLIFY=FALSE))
    f <- function(w, svec) {oquests.sol[[w]][svec,]}
    quests.sol <- Reduce(rbind, mapply(f, names(smp), smp, SIMPLIFY=FALSE))
           
    ## Permutate to remove the order induced by weight 
    set.seed(testid); x=sample(length(quests))
    quests <- quests[x]
    quests.sol <- quests.sol[x,]

    ## Scale with multiplier
    quests.sol$weight <- quests.sol$weight * MULTI
    
    ## Create output
    lines=c(hlines, unlist(quests), foot)                           
    list(quests=quests, quests.sol=quests.sol,
         preamble=preamble, hlines=hlines, flines=foot, lines=lines)    
}
      

buildPdf=function(# Build PDF
                  preamble,#including being document
                  lines,   # Tex body content 
                  testid,  # Random testid
                  nosol,   # add the NOSOL to file name
                  combo    # build the combo?
                  ){

    ## Make PDF out dir 
    out=paste0(COURSEDIR, "/", COURSE)
    if(nosol) out=paste0(out, "-nosol")
    if(!dir.exists(out)) {
        dir.create(out)
        lib <- paste0(COURSE, "-template", "/lib")
        file.copy(lib, COURSEDIR, recursive=TRUE)
    }
    
    ## Create the stem path without combo or version postifix
    fprfx=ifelse(nosol, "NOSOL-", "")    
    ftex.stem=sprintf("%s-%s", COURSE, fprfx)
    
    if(combo) {
        
        ## Build the combo
        ftex  =sprintf("%s\\!%scombo.tex", COURSEDIR, ftex.stem)
        ftex.c=sprintf("%s\\!%scombo-body.tex", COURSEDIR, ftex.stem)
        cat("\n\n\\end{document}", file=ftex.c, sep="\n", append=TRUE)
        writeLines(preamble, ftex)
        file.append(ftex, ftex.c)        

    } else {

        ## Save tex file with random questions
        fprfx=ifelse(nosol, "NOSOL-", "")
        ftex=sprintf("%s\\%sv%02d.tex", COURSEDIR, ftex.stem, testid)
        writeLines(c(preamble, lines, "\\end{document}"), ftex)

        ## Append to combo tex file
        ftex.c=sprintf("%s\\!%scombo-body.tex", COURSEDIR, ftex.stem)
        cat(c(lines, "\\newpage"), file=ftex.c, sep="\n", append=TRUE)
    }

    ## Build PDF
    libs <- paste0("--include-directory=", COURSE, "-template")
    out <- plat(out)
    ftex <- plat(ftex) 
    ags =paste0(libs, " -halt-on-error -output-directory=", out, " ", ftex)
    ret=system2("pdflatex", ags, stdout=TRUE, stderr=TRUE)
    if(!is.null(attr(ret, "status"))) stop("pdflatex gave: ", paste(ret, collapse="\n"))
    ## Second build
    ret=system2("pdflatex", ags, stdout=TRUE, stderr=TRUE)
    if(!is.null(attr(ret, "status"))) stop("pdflatex gave: ", paste(ret, collapse="\n"))

    ## Warn if more than 2 pages
    if(!combo) pageLength(ret, testid)
   
}

tex.qfoot <- function(){
    "\\end{questions}\n\n\n"
}

pageLength <- function(log, testid){ # Print a warning if a PDF is more than two page long

    log <- log[(length(log)-6):length(log)] # parse only last 6 

    ## Get material between Output written on/Transcript written on
    x=grep("^Output written on ", log)
    log <- log[x:length(log)]
    x=grep("^Transcript written on ", log)-1
    log <- log[1:x]
    log <- Reduce(paste0, log)

    ## Extract (n pages, xxx bytes).".  Only single digit pages assumed
    log <- regmatches(log, regexpr("\\([[:digit:]] page.*, +.+bytes\\)\\.", log))
    page <- regmatches(log, regexec("^\\(([[:digit:]]) page", log))[[1]][2]
    page <- as.numeric(page)

    ## print(paste("PDF num", testid, "is long", page, "pages."))

    if(page>2) print(paste("WARNING PDF num.", testid, "is long", page, "pages."))
}

makeRndPdf=function( # Make random PDF with sol                        
                     testid,     # random testid
                     preamble,   #including being document
                     hlines,     # Pre-questions header lines
                     quests,     # question list
                     quests.sol  # solution's DF
                     ){

    
    rndtex=makeRandExam(testid, preamble, hlines, quests, quests.sol)
    
    ## Build without sols => Comment \printanswers
    pat="^[ \t%]*\\\\printanswers"
    x <- which(grepl(pat, rndtex$preamble))
    rndtex$preamble[x]=sub(pat, "%\\\\printanswers", rndtex$preamble[x])
    buildPdf(rndtex$preamble, rndtex$lines, testid, nosol=TRUE, combo=FALSE)
    
    ## Build with sols => Remove comment from \\printanswers
    pat="^[ \t%]*\\\\printanswers"
    x <- which(grepl(pat, rndtex$preamble))
    rndtex$preamble[x]=sub(pat, "\\\\printanswers", rndtex$preamble[x])
    buildPdf(rndtex$preamble, rndtex$lines, testid, nosol=FALSE, combo=FALSE)

    ## Return question and solution lists
    with(rndtex,list(quests=quests, quests.sol=quests.sol))
}

plat <- function( # Path with proper slash for shell commands
                 pt){if(.Platform$OS.type=="windows") gsub("/", "\\\\", pt) else pt}

split_path <- function(x) # https://stackoverflow.com/a/29232017/1851270
    if (dirname(x)==x) x else c(basename(x),split_path(dirname(x)))
last4 <- function() # Last four getwd() components
    paste0(rev(split_path(getwd())[1:min(4, length(split_path(getwd())))]), collapse="/")

main=function(){

    ## Read course and n quests
    courses <- read.table("TESTCOUNT.txt", sep="=", header=TRUE, stringsAsFactors=FALSE, strip.white=TRUE)
    courses <- setNames(apply(courses, 1, as.list), courses$course)

    ## Safe make out dir
    makeOutDir()
    lapply(courses, function(curr) {

        ## Set globals
        COURSE    <<- curr$course
        TESTCOUNT <<- curr$ntest    
        COURSEDIR <<- paste0(OUTDIR, "/", COURSE, "-quests")

        ## Make template without comments in COURSEDIR
        message("Processing ", COURSE, ": ", TESTCOUNT)
        tex  <- makeTemplate()

        ## Get structured list with questions, weights, and solutions
        Q=getQuestions(tex)

        ## Generate and build random exams
        seeds <- sample(999, TESTCOUNT)
        sols=lapply(seq_along(seeds), function(nth){   
            message(nth, " -> ",  seeds[nth])            
            S <- makeRndPdf(seeds[nth], Q$preamble, Q$hlines, Q$quests, Q$quests.sol)})
        names(sols) = seeds

        #Make combos
        buildPdf(Q$preamble, NULL, testid, nosol=TRUE, combo=TRUE)
        buildPdf(Q$preamble, NULL, testid, nosol=FALSE, combo=TRUE)


        ## Save random questions with related weights and solutions, plus header/footer lines
        preamble <- Q$preamble; hlines <- Q$hlines; flines <- tex.qfoot()
        save(sols, preamble, hlines, flines, file=paste0(COURSEDIR, "/", COURSE, "-sols.RData"))

        ## Save init file
        x=data.frame(time=TIME, questcount=sum(WDIST), course=COURSE)
        write.table(x, paste0(COURSEDIR, "/INITFILE-", COURSE, ".txt"), row.names=FALSE, quote=FALSE)

        ## Clean pdf and pdf-nosol subdir
        x <- paste0(COURSEDIR, "/", COURSE)
        unlink(Sys.glob(paste0(x, "*/*.log")))
        unlink(Sys.glob(paste0(x, "*/*.aux")))
        unlink(Sys.glob(paste0(x, "*/*.tex")))

        ## Delete tex sources
        x=Sys.glob(paste0(COURSEDIR, "/*.tex"))    
        ## Leave *.-expd.tex for debug
        #x=x[x!=Sys.glob(paste0(COURSEDIR, "/*-expd.tex"))]                
        unlink(x)

        message()
        ## Show PDF count for dbg
        TESTCOUNT        
    }) -> x # print(x)

    ## Copy grade file and make readme
    message("Grade script and readme added to out dir.")
    file.copy("grade-tpl.txt", paste0(OUTDIR, "/grade.R")) -> x
    cat("Copy Emacs '*-answers' dirs here.\nRun grade.R\nLook for '*-results' dirs.",
        file=paste0(OUTDIR, "/ReadMe.txt"))
    message(last4())
}

