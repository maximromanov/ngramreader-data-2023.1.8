# Readable book titles and author names for the release's books (ngramreader-data-2023.1.8), shared by the
# NgramReader and the Book Classifier.
# Source: OpenITI_WorkingLabels.tsv (columns URI, generated_label_Opus47, AuthorAR, TitleAR, Ambiguous), working
# labels generated with a language model; Ambiguous is "0" or a short prose reason. Labels are copied unchanged.
# Outputs (UTF-8 TSV; header and character fields in double quotes, embedded quotes doubled, missing values NA):
#   labels/book_labels.tsv    bookURI, label (with *italic* markup), titleAR, authorAR, ambiguous (0/1), ambiguousNote
#                             -- one row per book of data_BC/metadata_books.parquet that has a label
#   labels/author_labels.tsv  authorURI, authorName, authorAR, deathCE, nBooks, variants
#                             -- one row per authorURI (book URI up to the first dot) of those books
#   optional audit file (second argument): per labelled book the parse outcome, parsed name and death date
# Author name: the part of the label after "* of " (after the italic title), up to a final death-date parenthesis
# "(d. ...)" or a life span "(YYYY–YYYY)"; deathCE is the CE year in "d. AH/CE", "d. c. AH/CE", "d. [c.] YYYY CE",
# or the second year of a life span. Per author the most frequent parsed name is chosen (ties: the name of the
# alphabetically first book URI). Translations ("<original author> (trans. <translator>, d. ...)") give no name: the
# URI's author is the translator, not the author named after "of". variants = number of distinct parsed names; with none, authorName = authorURI.
# authorAR: the most frequent non-empty AuthorAR of the author's books (same tie rule).
# Run from the repository root:  Rscript scripts/derive_labels.R <path to OpenITI_WorkingLabels.tsv> [audit.tsv]   (needs arrow)
suppressMessages(library(arrow))
args <- commandArgs(trailingOnly = TRUE)
src <- if (length(args)) args[1] else "OpenITI_WorkingLabels.tsv"
lab <- read.delim(src, sep = "\t", quote = "", stringsAsFactors = FALSE, encoding = "UTF-8", colClasses = "character",
                  na.strings = character(0), check.names = FALSE)
stopifnot(identical(names(lab), c("URI", "generated_label_Opus47", "AuthorAR", "TitleAR", "Ambiguous")), !anyDuplicated(lab$URI))
lab[] <- lapply(lab, function(x) sub("\r$", "", x))
books <- read_parquet("data_BC/metadata_books.parquet")$bookURI
b <- lab[lab$URI %in% books, ]
b <- b[order(b$URI), ]

# author name and death date from the label
parse <- function(label) {
  rest <- sub("^'?\\*[^*]*\\*", "", label)                       # drop the italic title (some labels carry a stray ')
  if (identical(rest, label) || !startsWith(rest, " of ")) return(c("no_of", NA, NA))
  a <- sub("'$", "", substring(rest, 5))
  if (grepl("\\(trans", a)) return(c("translation", NA, NA))  # "X (trans. Y, d. ...)": the URI's author is the translator Y
  m <- regmatches(a, regexec("^(.*\\S)\\s*\\((d\\.[^()]*)\\)$", a))[[1]]
  if (length(m)) {
    d <- m[3]
    ce <- regmatches(d, regexec("^d\\. (?:c\\. )?\\d{1,4}/(\\d{1,4})$", d, perl = TRUE))[[1]]
    if (!length(ce)) ce <- regmatches(d, regexec("^d\\. (?:c\\. )?(\\d{1,4}) CE$", d, perl = TRUE))[[1]]
    return(c(if (length(ce)) "name_date" else "name_undated_d", m[2], if (length(ce)) ce[2] else NA))
  }
  m <- regmatches(a, regexec("^(.*\\S)\\s*\\((\\d{3,4})[–-](\\d{3,4})\\)$", a))[[1]]
  if (length(m)) return(c("name_lifespan", m[2], m[4]))
  c("name_only", a, NA)
}
p <- t(vapply(b$generated_label_Opus47, parse, character(3), USE.NAMES = FALSE))
b$outcome <- p[, 1]; b$authorName <- p[, 2]; b$deathCE <- suppressWarnings(as.integer(p[, 3]))
b$authorURI <- sub("\\..*$", "", b$URI)

book_labels <- data.frame(bookURI = b$URI, label = b$generated_label_Opus47, titleAR = b$TitleAR, authorAR = b$AuthorAR,
                          ambiguous = as.integer(b$Ambiguous != "0"), ambiguousNote = ifelse(b$Ambiguous == "0", "", b$Ambiguous),
                          stringsAsFactors = FALSE)
pick <- function(x, uris) { ok <- !is.na(x) & x != ""; if (!any(ok)) return(c(NA, 0))
  x <- x[ok]; uris <- uris[ok]; n <- table(x); top <- names(n)[n == max(n)]
  c(if (length(top) == 1) top else x[order(uris)][x[order(uris)] %in% top][1], length(n)) }
au <- do.call(rbind, lapply(split(b, b$authorURI), function(g) {
  nm <- pick(g$authorName, g$URI); ar <- pick(g$AuthorAR, g$URI)
  dc <- if (is.na(nm[1])) NA else g$deathCE[!is.na(g$authorName) & g$authorName == nm[1]][order(g$URI[!is.na(g$authorName) & g$authorName == nm[1]])]
  dc <- dc[!is.na(dc)]
  data.frame(authorURI = g$authorURI[1], authorName = if (is.na(nm[1])) g$authorURI[1] else nm[1], authorAR = ar[1],
             deathCE = if (length(dc)) names(sort(table(dc), decreasing = TRUE))[1] else NA, nBooks = nrow(g), variants = as.integer(nm[2]),
             stringsAsFactors = FALSE) }))
au$deathCE <- as.integer(au$deathCE)

dir.create("labels", showWarnings = FALSE)
w <- function(x, f) write.table(x, f, sep = "\t", quote = TRUE, qmethod = "double", na = "NA", row.names = FALSE, fileEncoding = "UTF-8")
w(book_labels, "labels/book_labels.tsv")
w(au, "labels/author_labels.tsv")
if (length(args) > 1) w(data.frame(bookURI = b$URI, authorURI = b$authorURI, outcome = b$outcome, authorName = b$authorName,
                                   deathCE = b$deathCE, label = b$generated_label_Opus47, stringsAsFactors = FALSE), args[2])
message(sprintf("source rows %d; release books %d; labelled %d; missing %d; extra (not in release) %d",
                nrow(lab), length(books), nrow(b), sum(!books %in% lab$URI), sum(!lab$URI %in% books)))
message("parse outcomes: ", paste(names(table(b$outcome)), table(b$outcome), sep = " ", collapse = "; "))
message(sprintf("authors %d; with a parsed name %d; with variant names %d", nrow(au), sum(au$variants > 0), sum(au$variants > 1)))
