#Modified from the package pcalg
#Reference https://CRAN.R-project.org/package=pcalg 

skeleton_mod = function (suffStat, indepTest, alpha, labels, p, method = c("stable", 
                                                            "original", "stable.fast"), m.max = Inf, fixedGaps = NULL, 
          fixedEdges = NULL, NAdelete = TRUE, numCores = 1, verbose = FALSE) 
{
  cl <- match.call()
  if (!missing(p)) 
    stopifnot(is.numeric(p), length(p <- as.integer(p)) == 
                1, p >= 2)
  if (missing(labels)) {
    if (missing(p)) 
      stop("need to specify 'labels' or 'p'")
    labels <- as.character(seq_len(p))
  }
  else {
    stopifnot(is.character(labels))
    if (missing(p)) 
      p <- length(labels)
    else if (p != length(labels)) 
      stop("'p' is not needed when 'labels' is specified, and must match length(labels)")
  }
  seq_p <- seq_len(p)
  method <- match.arg(method)
  if (is.null(fixedGaps)) {
    G <- matrix(TRUE, nrow = p, ncol = p)
  }
  else if (!identical(dim(fixedGaps), c(p, p))) 
    stop("Dimensions of the dataset and fixedGaps do not agree.")
  else if (!identical(fixedGaps, t(fixedGaps))) 
    stop("fixedGaps must be symmetric")
  else G <- !fixedGaps
  diag(G) <- FALSE
  if (any(is.null(fixedEdges))) {
    fixedEdges <- matrix(rep(FALSE, p * p), nrow = p, ncol = p)
  }
  else if (!identical(dim(fixedEdges), c(p, p))) 
    stop("Dimensions of the dataset and fixedEdges do not agree.")
  else if (!identical(fixedEdges, t(fixedEdges))) 
    stop("fixedEdges must be symmetric")
  stopifnot((is.integer(numCores) || is.numeric(numCores)) && 
              numCores > 0)
  if (numCores > 1 && method != "stable.fast") {
    warning("Argument numCores ignored: parallelization only available for method = 'stable.fast'")
  }
  if (method == "stable.fast") {
    if (identical(indepTest, gaussCItest)) 
      indepTestName <- "gauss"
    else indepTestName <- "rfun"
    options <- list(verbose = as.integer(verbose), m.max = as.integer(ifelse(is.infinite(m.max), 
                                                                             p, m.max)), NAdelete = NAdelete, numCores = numCores)
    res <- .Call("estimateSkeleton", G, suffStat, indepTestName, 
                 indepTest, alpha, fixedEdges, options)
    G <- res$amat
    sepset <- lapply(seq_p, function(i) c(lapply(res$sepset[[i]], 
                                                 function(v) if (identical(v, as.integer(-1))) NULL else v), 
                                          vector("list", p - length(res$sepset[[i]]))))
    pMax <- res$pMax
    n.edgetests <- res$n.edgetests
    ord <- length(n.edgetests) - 1L
  }
  else {
    pval <- NULL
    sepset <- lapply(seq_p, function(.) vector("list", p))
    pMax <- matrix(-Inf, nrow = p, ncol = p)
    pScor <- matrix(0, nrow = p, ncol = p)
    diag(pMax) <- 1
    done <- FALSE
    ord <- 0L
    rScor <- 0  #add pScor if that ind test result is used.
    rScor_count <- 0 # count the times when rScor is changed
    n.edgetests <- numeric(1)
    while (!done && any(G) && ord <= m.max) {
      n.edgetests[ord1 <- ord + 1L] <- 0
      done <- TRUE
      ind <- which(G, arr.ind = TRUE)
      ind <- ind[order(ind[, 1]), ]
      remEdges <- nrow(ind)
      if (verbose) 
        cat("Order=", ord, "; remaining edges:", remEdges, 
            "\n", sep = "")
      if (method == "stable") {
        G.l <- split(G, gl(p, p))
      }
      for (i in 1:remEdges) {
        if (verbose && (verbose >= 2 || i%%100 == 0)) 
          cat("|i=", i, "|iMax=", remEdges, "\n")
        x <- ind[i, 1]
        y <- ind[i, 2]
        if (G[y, x] && !fixedEdges[y, x]) {
          nbrsBool <- if (method == "stable") 
            G.l[[x]]
          else G[, x]
          nbrsBool[y] <- FALSE
          nbrs <- seq_p[nbrsBool]
          length_nbrs <- length(nbrs)
          if (length_nbrs >= ord) {
            if (length_nbrs > ord) 
              done <- FALSE
            S <- seq_len(ord)
            repeat {
              n.edgetests[ord1] <- n.edgetests[ord1] + 
                1
              pval <- indepTest(x, y, nbrs[S], suffStat)
              if (is.na(pval)) 
                pval <- as.numeric(NAdelete)
              if (pMax[x, y] < pval){
                pMax[x, y] <- pval
                pSc_nbr <- abs(log(pval) - log(alpha))#adding score to each pMax value
                if (pSc_nbr > 500) {pScor[x, y] <- 500} #set limit to eliminate effect of very lagrge nbr
                else {pScor[x, y] <- pSc_nbr}
              }
              if (verbose) 
                cat("x=", x, " y=", y, " S=", nbrs[S], 
                    ": pval =", pval, "; pMax = ", pMax[x, y],
                    ", pScor = ", pScor[x, y],"\n")
              if (pval >= alpha) {
                G[x, y] <- G[y, x] <- FALSE
                sepset[[x]][[y]] <- nbrs[S]
                rScor <- rScor + pScor[x, y] #add pScor of [x,y] 
                pScor[x, y] <- 0
                rScor_count <- rScor_count + 1 #add count
                break
              }
              else {
                nextSet <- getNextSet(length_nbrs, ord, 
                                      S)
                if (nextSet$wasLast) 
                  break
                S <- nextSet$nextSet
              }
            }
          }
        }
      }
      ord <- ord + 1L
    }
    for (i in 1:(p - 1)) {
      for (j in 2:p) pMax[i, j] <- pMax[j, i] <- max(pMax[i, 
                                                          j], pMax[j, i])
      for (j in 2:p) pScor[i, j] <- pScor[j, i] <- max(pScor[i, 
                                                          j], pScor[j, i])
    }
  }
  Gobject <- if (sum(G) == 0) {
    new("graphNEL", nodes = labels)
  }
  else {
    colnames(G) <- rownames(G) <- labels
    as(G, "graphNEL")
  }
  pca <- new("pcAlgo", graph = Gobject, call = cl, n = integer(0), 
      max.ord = as.integer(ord - 1), n.edgetests = n.edgetests, 
      sepset = sepset, pMax = pMax, zMin = matrix(NA, 1, 1))
  #print(as(pca@graph, "matrix"))
  list(pc_alg = pca, pScor = pScor, rScor = rScor, rScor_count = rScor_count) #return a list containing all data
}
