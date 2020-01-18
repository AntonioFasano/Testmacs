idir <- Sys.glob("./", dirmark=TRUE)
assg.namesans  <- "mycourse"
path <- function(suff) paste0(assg.dir, assg.namesans, suff)

library('knitr')
knit.env <- new.env()
assg.env <- new.env()
assignment <- list()

## Obtain text
knit.env$purlsol <- FALSE
if(file.exists(path(".md"))) file.remove(path(".md"))
knit(path(".Rmd"), envir=knit.env)
txt <- readLines(path(".md"))
beg <- which(nzchar(txt))[1]
end <- rev(which(nzchar(txt)))[1]
txt <- txt[beg:end]
txt <- paste(txt, collapse="\n")
assignment$text <- txt

## Obtain input variables
knit.env$purlsol <- FALSE
if(file.exists(path(".R"))) file.remove(path(".R"))
purl(path(".Rmd"), envir=knit.env)
source(path(".R"), local=assg.env)
varnames <- assg.env$input.var.names
varnames <- strsplit(trimws(varnames), " +")[[1]]

## Obtain classes
assignment$classes <- assg.env$sol.classes
assignment$classes.opt <- assg.env$sol.classes.opt

## Save assignment no sol
assg.env$.assignment <- assignment
save(list=c(varnames, ".assignment"), file=path("-nosol.RData"), envir=assg.env)

## Obtain sol var names
knit.env$purlsol <- TRUE
if(file.exists(path(".R"))) file.remove(path(".R"))
purl(path(".Rmd"), envir=knit.env)
sol.env <- new.env()
source(path(".R"), local=sol.env)
varnames <- sol.env$sol.var.names
varnames <- strsplit(trimws(varnames), " +")[[1]]


## Add classes to sol environment
sol <- list()
sol$values  <- setNames(lapply(varnames, function(var) assign(var, get(var, sol.env))), varnames)
sol$classes <- assignment$classes
sol$classes.opt <- assignment$classes.opt

## Save sols
saveRDS(sol, path("-wsol.rds"))


info <- function(){

    txt <- paste0("\n", .assignment$text, "\n")

    ## Add mandatory vars
    nms <- names(.assignment$classes)
    vals <- .assignment$classes
    cls <- sapply(seq_along(nms), function(i)  paste(nms[i], "\t:\t", vals[i]  ) )
    cls <- paste(cls, collapse="\n")
    txt <- rbind(txt, "\nClasses:\n", cls, "\n")

    
    ## Add optional vars
    nms <- names(.assignment$classes.opt)
    vals <- .assignment$classes.opt
    cls <- sapply(seq_along(nms), function(i)  paste(nms[i], "\t:\t", vals[i]  ) )
    cls <- paste(cls, collapse="\n")
    txt <- rbind(txt, "\nOptional variables:\n", cls, "\n")

    message(txt)
    
}

lapply(1:3, print)
sapply(1:3, print)
cbind(1:3, 11:13)
data.frame(x=1:3)
