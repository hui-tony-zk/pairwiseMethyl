cores_to_use <- 30

#' Divide cores
#'
#' @description Utility function to help parallelize jobs in R with less overhead.
#'     Likely wouldn't ever be used by the user.
#' @param total Total number of jobs to parallelize
#' @param ncores CPUs to parallelize over (must be >1)
#'
#' @return Returns a data.frame with two columns (from and to) and rows equal to the number of cores
#' @export
#'
#' @examples divide_cores(total = 100, ncores = 2)
#'
divide_cores <- function(total, ncores = cores_to_use) {
  if (cores_to_use <= 1) stop("ncores <=1 - make sure to use 2 or more cores for parallelization")
  if (total <= ncores){
    return(data.frame(from=1:(total),to=1:(total)))
  } else if (total <= ncores*2) {
    from=c(1:(total-1))
    from=c(from)[seq(from = 1,to=length(from), by=2)]
    to=c(1:total)
    to=c(to)[seq(from = 2,to=length(to), by=2)]
    df = data.frame(from, to)
    if (total %% 2 == 1) {
      df[nrow(df),2]<- total
    }
    return(df)
  } else {
    batch = total %/% ncores
    from = seq(from = 1, to = total-batch, by = batch)[1:ncores-1]
    to = c(seq(from = batch, to = total, by = batch), total)[1:length(from)]
    total_batch <- data.frame(cbind(from, to))
    # Add on the remainder
    total_batch <- rbind(total_batch, data.frame(
      from=max(total_batch$to)+1,
      to=total)
    )
  }
  return(total_batch)
}

#' Create pairwise comparisons
#'
#' @description Create pairwise comparisons between single-cells
#' @param cpg A list of named data frames containing CpG calls. See details for required format of dataframes. Required.
#' @param digital Whether or not to discard non-binary CpG calls. Useful in single-cells as it's very unlikely that a single-cell contains a heterozygous methylation call. Defaults to TRUE.
#' @param ncores Number of cores to parallelize over. Defaults to 1
#' @param calcdiff Whether or not to directly calculate the average difference (if TRUE), or to return a list of dataframes containing pairwise common CpGs (if FALSE). Defaults to TRUE.
#'
#' @return A list of dataframes if \code{calcdiff} is FALSE. Otherwise, a dataframe containing the pairwise dissimiarlties if \code{calcdiff} is TRUE.
#' @export
#' @import foreach dplyr
#'
#' @details
#' Each dataframe containing CpG calls must have the following four columns:
#' 1. Chromsome column, named "V1"
#' 2. Start/Position column, named "V2"
#' 3. Percentage methylation column, named "V4" (between 0-100)
#'
#' @examples
#' \dontrun{
#' create_pairwise_master(cpg = cpg_list, digital = TRUE, ncores = 30,
#'     calcdiff = TRUE)
#' }
#'
create_pairwise_master <- function(cpg, digital = TRUE, ncores = 2, calcdiff = TRUE){
  doMC::registerDoMC(ncores)
  # Generate combinations
  comb <- combn(length(names(cpg)),2)
  comb.names <- combn(names(cpg),2)
  total_batch <- divide_cores(ncol(comb.names), ncores)
  # Combine
  pairwise <- foreach(i=1:nrow(total_batch), .combine = c) %dopar% {
    start <- total_batch[i,1]
    end <- total_batch[i,2]
    merge_bind=vector("list", end-start+1)
    for (f in start:end) {
      name1 <- comb.names[1,f]
      name2 <- comb.names[2,f]
      one <- cpg[[name1]] %>% select(1,2,4)
      two <- cpg[[name2]] %>% select(1,2,4)
      if (digital) {
        one <- filter(one, V4 == 0 | V4 == 100)
        two <- filter(two, V4 == 0 | V4 == 100)
      }
      merge_temp <- inner_join(one, two, by=c("V1", "V2")) %>% setnames(c("chr","pos",paste0(name1), paste0(name2)))
      if (calcdiff) {
        merge_temp <- get_diff_df(merge_temp)
      }
      merge_bind[[f-start+1]] <- merge_temp
      names(merge_bind)[f-start+1] <- paste0(name1,"_",name2)
    }
    merge_bind
  }
  if (calcdiff) {
    pairwise <- suppressWarnings(bind_rows(pairwise))
  }
  return(pairwise)
}

#' Get manhattan distance from pairwise common data frame
#'
#' @param df A dataframe containing the pairwise common CpGs. Required.
#'
#' @return A 1-row dataframe containing the pairwise dissimilarity
#' @export
#'
#' @details
#' Typically this function is not used by the user. It is called by \code{create_pairwise_master} when \code{calc_diff} is TRUE.
#'
#' The input dataframe requires four columns in the specific order:
#' 1. Chromosome
#' 2. Start
#' 3. Name of the 1st comparitor (e.g. cell1)
#' 4. Name of the 2nd comparitor (e.g. cell2)
#'
get_diff_df <- function(df) {
  diff.temp <- data.frame(
    x = names(df)[3],
    y = names(df)[4],
    total = nrow(df),
    pear_corr = c(cor(df[[3]], df[[4]], method = "pearson")),
    manhattan_dist = sum(abs(df[[3]]-df[[4]]))
  ) %>%
    mutate(
      manhattan_dist_scaled = manhattan_dist/total
    )
  return(diff.temp)
}

#' Convert pairwise dissimilarity data.frame to a pairwise matrix
#'
#' @param master_diff The data.frame containing pairwise dissimilarites. Typically the output of \code{create_pairwise_master}. See details for format of this data.frame. Required.
#' @param measure The name of the column to use as the values for the pairwise dissimilarity matrix. Defaults to the manhanttan distance. Can be changed if user wants another measure (e.g. correlation, etc).
#' @param diag The value to put in the diagonal. Defaults to NA.
#' @param sample_subset A character vector of sample names to subset. Optional.
#'
#' @return A data.matrix representing the pairwise dissimilarites between every cell
#' @export
convert_to_distance_matrix <- function(master_diff, measure = "manhattan_dist_scaled", diag = NA, sample_subset = NULL) {
  if (! is.null(sample_subset)) {
    master_diff <- master_diff %>% filter(x %in% sample_subset, y %in% sample_subset)
  }
  test <- data.frame(master_diff)[,c("x","y",measure)]
  colnames(test)[3] <- "value"
  list_samples <- unique(c(as.character(test$x), as.character(test$y)))
  test.rev <- test %>% transform(x=y,y=x,value=value)
  test.same <- data.frame(x=list_samples,y=list_samples,value=diag)
  test <- unique(rbind(test.same, test, test.rev))

  x <- data.matrix(spread(test, key = y, value = value)[,-1])
  rownames(x) <- colnames(x)

  return(x)
}

merge_cpgs <- function(cluster_members, cpg_all) {
  # usage: bssmooth_list <- mclapply(cluster_groupings, merge_cpgs)
  tmp <- cpg_all[get(cluster_members)]
  tmp <- lapply(seq_along(tmp), function(i) {
    x = tmp[[i]]
    y = BSseq(M = as.matrix(x$V4/100), Cov = as.matrix(rep(1, nrow(x))), chr = x$V1, pos = x$V2, sampleNames = names(tmp)[[i]])
    return(y)
  })
  tmp2 = tmp[[1]]
  for (i in 2:length(tmp)) {
    cat(paste(i, "\r"))
    tmp2 = combineList(list(tmp2, tmp[[i]]))
    samples = sampleNames(tmp2)
    tmp2 = collapseBSseq(tmp2, columns = rep(cluster_members, length(samples)) %>% setNames(samples))
    gc()
  }
  return(tmp2)
}