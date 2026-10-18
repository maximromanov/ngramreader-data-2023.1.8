# Derived plain-text files for the browser-only NgramReader (ngramreader-data-2023.1.8).
# Generated from this repository's own Parquet files; run from the repository root:
#   Rscript scripts/derive_text.R
# Requires R with the packages arrow and data.table.
#
# Outputs, per ngram order n = 1, 2, 3 (UTF-8, "\n" line ends, line number = ngram ID, IDs 1..N contiguous):
#   derived/vocab_{n}gram/part-NNN.txt   one ngramTR (simplified Buckwalter) per line
#   derived/counts_{n}gram/part-NNN.txt  "<total in all texts>\t<total in clean texts>" per line, i.e. the sum of
#                                        `count` over all books, and over books with CLEAN == "CLEAN", in
#                                        data_additional/ngrams_per_book/books_{n}gram/ (used by the match preview)
#   derived/{vocab,counts}_{n}gram/manifest.tsv   file, id_min, id_max, lines, bytes (tab-separated, header)
# Files are split at line boundaries so that none exceeds MAX_BYTES.
suppressMessages({ library(arrow); library(data.table) })
MAX_BYTES <- 90e6

readParts <- function(dir) {
  man <- read_parquet(file.path(dir, "manifest.parquet"))
  rbindlist(lapply(man$file, function(f) as.data.table(read_parquet(file.path(dir, f)))))
}

writeSplit <- function(lines, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  unlink(list.files(dir, full.names = TRUE))
  bytes <- nchar(lines, type = "bytes") + 1                 # + newline
  cum <- cumsum(as.numeric(bytes))
  part <- floor((cum - 1) / MAX_BYTES) + 1
  man <- list()
  for (p in unique(part)) {
    idx <- which(part == p); f <- sprintf("part-%03d.txt", p)
    con <- file(file.path(dir, f), open = "wb"); writeLines(enc2utf8(lines[idx]), con, sep = "\n", useBytes = TRUE); close(con)
    man[[p]] <- data.frame(file = f, id_min = min(idx), id_max = max(idx), lines = length(idx), bytes = file.size(file.path(dir, f)))
  }
  man <- do.call(rbind, man)
  stopifnot(all(man$bytes <= MAX_BYTES), sum(man$lines) == length(lines))
  write.table(man, file.path(dir, "manifest.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
  man
}

meta <- as.data.table(read_parquet("data_BC/metadata_books.parquet"))
cleanBooks <- meta[CLEAN == "CLEAN", bookID]
for (n in 1:3) {
  ids <- readParts(sprintf("data/data_%dgrams2up_HI", n))
  stopifnot(identical(ids$ID, seq_len(nrow(ids))), !anyNA(ids$ngramTR), !any(grepl("[\t\n\r]", ids$ngramTR)))
  m1 <- writeSplit(ids$ngramTR, sprintf("derived/vocab_%dgram", n))
  books <- readParts(sprintf("data_additional/ngrams_per_book/books_%dgram", n))
  tot <- books[, .(all = sum(as.numeric(count)), clean = sum(as.numeric(count[bookID %in% cleanBooks]))), by = ID]
  allTot <- numeric(nrow(ids)); cleanTot <- numeric(nrow(ids))
  allTot[tot$ID] <- tot$all; cleanTot[tot$ID] <- tot$clean
  m2 <- writeSplit(sprintf("%.0f\t%.0f", allTot, cleanTot), sprintf("derived/counts_%dgram", n))
  message(sprintf("order %d: vocab %d lines in %d file(s), %.1f MB; counts %.1f MB; IDs with zero total: %d",
                  n, nrow(ids), nrow(m1), sum(m1$bytes) / 1e6, sum(m2$bytes) / 1e6, sum(allTot == 0)))
}
