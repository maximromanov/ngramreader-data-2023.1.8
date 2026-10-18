# Release-pinned book links for the browser-only NgramReader (ngramreader-data-2023.1.8).
# For every book in data_BC/metadata_books.parquet, the primary version ("pri") of that book in the official
# OpenITI release metadata (OpenITI/RELEASE, tag v2023.1.8, OpenITI_metadata_2023-1-8.csv), and its path in that
# tag. The app links to https://raw.githubusercontent.com/OpenITI/RELEASE/v2023.1.8/<path>, which is frozen at the
# release. Books without a primary version in the release metadata get an empty path (the app then falls back to
# the R app's link from data_BC/metadata_books_urls.parquet).
# Run from the repository root:  Rscript scripts/derive_book_links.R      (needs R with arrow; network access)
suppressMessages(library(arrow))
RELEASE_TAG <- "v2023.1.8"
src <- sprintf("https://raw.githubusercontent.com/OpenITI/RELEASE/%s/OpenITI_metadata_2023-1-8.csv", RELEASE_TAG)
rel <- read.delim(src, sep = "\t", quote = "", stringsAsFactors = FALSE, encoding = "UTF-8", colClasses = "character")
pri <- rel[rel$status == "pri", c("book", "version_uri", "local_path")]
stopifnot(!anyDuplicated(pri$book))
books <- read_parquet("data_BC/metadata_books.parquet")
m <- match(books$bookURI, pri$book)
out <- data.frame(bookURI = books$bookURI,
                  version_uri = ifelse(is.na(m), "", pri$version_uri[m]),
                  path = ifelse(is.na(m), "", sub("^\\.\\./", "", pri$local_path[m])),
                  stringsAsFactors = FALSE)
dir.create("derived", showWarnings = FALSE)
write.table(out, "derived/book_links.tsv", sep = "\t", quote = FALSE, row.names = FALSE, fileEncoding = "UTF-8")
message(sprintf("books %d; with release path %d; without %d (source: %s)", nrow(out), sum(out$path != ""), sum(out$path == ""), src))
