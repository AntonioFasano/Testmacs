## ----assign.input, purl=TRUE---------------------------------------------
    P0 <-  93
    P1 <- 100



## ----assign.misc.vars, purl=TRUE-----------------------------------------
## Avoid naming clash with assign.input vars

## input vars to save (string w. space sep)
input.var.names <- "P0 P1"

## sol var classes
sol.classes <- list(r = "numeric")
sol.classes.opt <- list(notes = "character")



## ----assign.sol, purl=purlsol--------------------------------------------

r <- P1/P0 - 1


## ----assign.sol.vars, purl=purlsol---------------------------------------

## sol vars to save (string w. space sep)
sol.var.names <- "r"


