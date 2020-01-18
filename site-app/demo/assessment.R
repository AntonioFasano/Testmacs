check.names <- function(result.prof, result.stud)
    sapply(names(result.prof), function(nm) !is.null(result.stud[[nm]]))

check.classes <- function(result, classes)
    sapply(names(result), function(nm) classes[[nm]] == class(result[[nm]]))

check.values <- function(result.prof, result.stud)
    sapply(names(result.prof), function(nm) all.equal(result.prof[[nm]], result.stud[[nm]]))

sol <- readRDS(path("-wsol.rds"))
prof <- sol$values
classes <- sol$classes
classes.opt <- sol$classes.opt
stud <- readRDS(path("-send.rds"))

## prof <- list(r=P1/P0 - 1)
## stud <- list(R=P1/P0 - 1)
assesm.names <- check.names(prof, stud)
assesm.classes <- if(all(assesm.names)) check.classes(stud, classes) else NA
assesm.values <- if(isTRUE(assesm.classes)) check.values(prof, stud) else NA
assesm <- list(passed=isTRUE(assesm.values),
               names.official=assesm.names,
               names.given=if(all(assesm.names)) "OK" else names(stud),
               classes.official=if(all(assesm.names)) sapply(prof, class) else NA,
               classes.given=if(isTRUE(assesm.classes)) "OK" else if(all(assesm.names)) sapply(stud, class) else NA,
               values=if(isTRUE(assesm.classes)) values=list(official=prof, given=stud) else NA)
assesm


