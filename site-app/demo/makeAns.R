send.sample  <- function(...){
    L <- list(...)
    rds  <- path("-send.rds")
    if(file.exists(rds)) file.remove(rds)
    saveRDS(L, rds)
}


r <- P1/P0 - 1

send.sample(r=r)

