# Book Classifier data (ADHFAIS app 2, 10-type model, as deployed 2025-06-14) for the browser-only classifier
# (maximromanov/classifier). Converts the app's RDS files to Parquet under classifier/, keyed and sorted by bookID
# (data_BC/metadata_books.parquet). Shared tables (main_data, rolling_authors, comps_labels, metadata, labels) are
# not duplicated; the app reads them from data_BC/ and labels/.
#   classifier/rolling/          bookID, start (token offset), balagha ... tarajim: score x 10^4 as int16
#                                (the RDS scores are exact multiples of 1e-4, so this is lossless)
#   classifier/rolling_entropy/  bookID, start, ENTRPOYUNI, ENTROPYBI: entropy x 10^6 as int32 (the RDS values have
#                                at most 6 decimals; lossless)
#   classifier/tfidf/            bookID, book2 (bookID of the neighbour), distance (TF-IDF cosine, double): top 250
#   classifier/headers/          bookID, level (1, 2, 3), pos (token offset): from data_arrgegatedHeadersFilteredH3.rds,
#                                which contains all H1 and H2 rows of the H1 and H2 files (checked below)
#   classifier/entropy_complete.parquet   the RDS table unchanged, with bookID added as the first column
# Each table folder has part-NNN.parquet files (zstd, 16,384 rows per row group, statistics on bookID) and a
# manifest.parquet (file, id_min, id_max, rows, bytes, row_groups), as for the ngram tables.
# Run from the repository root:  Rscript scripts/derive_classifier.R <path to adhfais_app2_local_10types>   (needs arrow)
suppressMessages({ library(arrow); library(dplyr) })
args <- commandArgs(trailingOnly = TRUE)
src <- if (length(args)) sub("/?$", "/", args[1]) else stop("path to adhfais_app2_local_10types required")
meta <- read_parquet("data_BC/metadata_books.parquet") %>% select(bookID, bookURI)
RG <- 16384L; MAXB <- 95e6
types <- c("balagha", "chronicles", "fiqh", "greek", "hadith", "kalam", "medicine", "poetry", "tafsir", "tarajim")

stack <- function(dir) {
  fs <- list.files(paste0(src, "data_additional/", dir), "\\.rds$", full.names = TRUE)
  stopifnot(length(fs) == nrow(meta), all(sub("\\.rds$", "", basename(fs)) %in% meta$bookURI))
  bind_rows(lapply(fs, function(f) { x <- readRDS(f); if (!nrow(x)) return(NULL)
    x$bookID <- meta$bookID[match(sub("\\.rds$", "", basename(f)), meta$bookURI)]; x }))
}
write_table <- function(df, schema, name) {
  dir <- file.path("classifier", name); unlink(dir, recursive = TRUE); dir.create(dir, recursive = TRUE)
  df <- df[order(df$bookID, df[[names(schema)[2]]]), names(schema)]
  # split at bookID boundaries so that no part exceeds MAXB (estimated from a first full write)
  tmp <- tempfile(fileext = ".parquet"); write_parquet(arrow_table(df, schema = schema), tmp, compression = "zstd", chunk_size = RG)
  nparts <- max(1, ceiling(file.size(tmp) / (MAXB * 0.9))); unlink(tmp)
  ids <- sort(unique(df$bookID)); cuts <- split(ids, ceiling(seq_along(ids) * nparts / length(ids)))
  man <- bind_rows(lapply(seq_along(cuts), function(i) {
    part <- df[df$bookID %in% cuts[[i]], ]; f <- sprintf("part-%03d.parquet", i - 1)
    write_parquet(arrow_table(part, schema = schema), file.path(dir, f), compression = "zstd", chunk_size = RG)
    data.frame(file = f, id_min = min(part$bookID), id_max = max(part$bookID), rows = nrow(part),
               bytes = file.size(file.path(dir, f)), row_groups = ceiling(nrow(part) / RG))
  }))
  man$id_min <- as.integer(man$id_min); man$id_max <- as.integer(man$id_max); man$rows <- as.integer(man$rows)
  man$bytes <- as.integer(man$bytes); man$row_groups <- as.integer(man$row_groups)
  write_parquet(man, file.path(dir, "manifest.parquet"))
  message(sprintf("%-16s rows %9d  parts %d  bytes %s", name, nrow(df), nrow(man), paste(man$bytes, collapse = "+")))
}

# rolling type scores
r <- stack("books_rolling_rds")
r$start <- as.integer(r$start); stopifnot(identical(sort(setdiff(names(r), c("bookID", "start"))), types))
for (k in types) { q <- r[[k]] * 1e4; stopifnot(max(abs(q - round(q))) < 1e-6); r[[k]] <- as.integer(round(q)) }
write_table(r, schema(c(list(bookID = int32(), start = int32()), setNames(rep(list(int16()), 10), types))), "rolling")
# rolling entropy
e <- stack("books_rolling_entropy"); e$start <- as.integer(e$start)
for (k in c("ENTRPOYUNI", "ENTROPYBI")) { q <- e[[k]] * 1e6; stopifnot(max(abs(q - round(q))) < 1e-3); e[[k]] <- as.integer(round(q)) }
write_table(e, schema(bookID = int32(), start = int32(), ENTRPOYUNI = int32(), ENTROPYBI = int32()), "rolling_entropy")
# TF-IDF neighbours (top 250, as in the RDS files)
t <- stack("books_tfidf_rds"); t$book2 <- as.integer(t$book2)
t <- t %>% group_by(bookID) %>% mutate(rank = row_number()) %>% ungroup()   # keep the RDS row order within a book
t <- t[order(t$bookID, t$rank), ]; t$rank <- as.integer(t$rank)
write_table(t[, c("bookID", "rank", "book2", "distance")], schema(bookID = int32(), rank = int32(), book2 = int32(), distance = float64()), "tfidf")
# headers, all three levels
h <- lapply(1:3, function(i) readRDS(sprintf("%sdata_temp/data_arrgegatedHeadersFilteredH%d.rds", src, i)))
key <- function(x) paste(x$bookURI, x$header_typ, x$header_pos)
stopifnot(all(key(h[[1]]) %in% key(h[[3]])), all(key(h[[2]]) %in% key(h[[3]])))
hd <- h[[3]] %>% mutate(bookID = meta$bookID[match(bookURI, meta$bookURI)], level = as.integer(sub("h", "", header_typ)), pos = as.integer(header_pos))
stopifnot(!anyNA(hd$bookID))
hd <- hd[order(hd$bookID, hd$pos, hd$level), c("bookID", "pos", "level")]
write_table(hd, schema(bookID = int32(), pos = int32(), level = int8()), "headers")
# whole-text entropy (8,415 books), unchanged plus bookID
ec <- readRDS(paste0(src, "data/entropy_complete.rds"))
ec <- cbind(data.frame(bookID = meta$bookID[match(ec$bookURI, meta$bookURI)]), as.data.frame(ec))
stopifnot(!anyNA(ec$bookID)); ec$bookID <- as.integer(ec$bookID)
write_parquet(ec[order(ec$bookID), ], "classifier/entropy_complete.parquet", compression = "zstd")
message(sprintf("entropy_complete rows %d  bytes %d", nrow(ec), file.size("classifier/entropy_complete.parquet")))
