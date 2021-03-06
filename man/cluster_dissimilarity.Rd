% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/scMeth_functions.R
\name{cluster_dissimilarity}
\alias{cluster_dissimilarity}
\title{Clustering dissimilarities}
\usage{
cluster_dissimilarity(dissimilarity_matrix, num_clusters)
}
\arguments{
\item{dissimilarity_matrix}{A matrix outputted by `convert_to_dissimilarity_matrix()`}

\item{num_clusters}{Number of clusters to divide into}
}
\value{
an list containing: 1) an hclust object and 2) cluster assignments of samples
}
\description{
Clustering dissimilarities
}

