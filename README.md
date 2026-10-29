# ngramreader-data-2023.1.8

Data for the browser-only **OpenITI NgramReader** (`maximromanov/ngramreader`, https://maximromanov.github.io/ngramreader/), built from **OpenITI release 2023.1.8**. One repository per OpenITI release: a later release goes into a new repository named the same way (e.g. `ngramreader-data-2025.1.9`), and the app switches to it by configuration.

- **Source:** the Parquet data of the NgramReader R app, 2026 Parquet version (`adhfais_app1_local_2026_parquet`, commit `825b4bb`). Files are copied unchanged, in the same folder layout; `SHA256SUMS` lists their hashes.
- **Format:** Apache Parquet, zstd-compressed, no R-specific metadata. Large tables are split at ID boundaries into `part-NNN.parquet` files; each table folder has a `manifest.parquet` (`file`, `id_min`, `id_max`, `rows`, `bytes`[, `row_groups`]).
- **Access:** the app reads `https://raw.githubusercontent.com/maximromanov/ngramreader-data-2023.1.8/<commit>/<path>`, pinned to a commit. Vocabularies are fetched whole (browser-cached); per-book rows and Arabic strings by HTTP range requests (row groups only).

| Path | Contents |
|---|---|
| `data/data_{n}grams2up_HI/` | ID tables (n = 1, 2, 3): `ID` int32, `ngramTR` string (simplified Buckwalter); 804,988 / 4,811,336 / 4,018,539 rows |
| `data/data_{n}grams2up_HI_AR/` | Arabic script: `ID` int32, `ngram` string (UTF-8) |
| `data/metadata_bookID_bookURI_frozen.parquet` | `bookID` int32, `bookURI` string (8,468 books) |
| `data_additional/ngrams_per_book/books_{n}gram/` | counts per ngram per book: `ID`, `bookID`, `count` int32; sorted by `ID`, `bookID`; 262,144 rows per row group; parts ≤ 88.3 MB |
| `data_BC/` | book metadata (`metadata_books.parquet`: token counts, CLEAN flag), links (`metadata_books_urls.parquet`), book-type scores (`main_data.parquet`), type labels (`comps_labels.parquet`, `types_final.tsv`), author type scores (`rolling_authors.parquet`) |

| `derived/vocab_{n}gram/` | **derived**: the vocabulary as plain text, one `ngramTR` per line, line number = `ID` (UTF-8, `\n`); `manifest.tsv` lists the parts. Served gzip-compressed by raw.githubusercontent.com (bigrams: 52.7 MB file, 26.5 MB transferred). The app loads this instead of the Parquet ID table (faster to decode, half the download). |
| `derived/counts_{n}gram/` | **derived**: per-ID corpus totals, `<all texts>\t<clean texts>` per line, line number = `ID` (sum of `count` over all books / over books with `CLEAN == "CLEAN"`); used by the match preview |
| `derived/book_links.tsv` | **derived**: for each `bookURI`, the primary version in the official release metadata (OpenITI/RELEASE tag `v2023.1.8`) and its path in that tag; empty for 120 books not listed there. The app links to `https://raw.githubusercontent.com/OpenITI/RELEASE/v2023.1.8/<path>`. |
| `labels/book_labels.tsv` | **labels**: readable working labels per book: `bookURI`, `label` (transliterated, title in `*…*` italics markup), `titleAR`, `authorAR`, `ambiguous` (0/1), `ambiguousNote` (the source's reason when ambiguous); 8,387 of the 8,468 books (see *Labels* below) |
| `labels/author_labels.tsv` | **labels**: per `authorURI` (book URI up to the first dot): `authorName` (transliterated, extracted from the book labels), `authorAR`, `deathCE` (when it parses), `nBooks` (labelled books), `variants` (distinct parsed names; 0 = no name, `authorName` is then the `authorURI`); 3,255 authors |
| `scripts/` | `derive_text.R` (vocabulary and totals, from this repository's Parquet files), `derive_book_links.R` (from the release metadata) and `derive_labels.R` (labels, from the source file named below); run from the repository root |

Size: about 1.45 GB, above GitHub's recommended 1 GB per repository and well under the 5 GB limit; accepted for a single release repository. No file exceeds 100 MB; no Git LFS.

## Labels

Book titles and author names in `labels/` are **working labels and may contain errors; the URI is authoritative.**

- **Source:** `OpenITI_WorkingLabels.tsv` (Maxim Romanov, file dated 2026-07-22; 8,641 rows, one per book URI; SHA-256 `36863ca8…64b25`). Its columns are `URI`, `generated_label_Opus47`, `AuthorAR`, `TitleAR` and `Ambiguous`.
- **How they were made:** the transliterated labels were **generated with a language model** (source column `generated_label_Opus47`) from OpenITI metadata; 1,733 source rows carry an `Ambiguous` reason (1,665 of them among this release's books).
- **What was derived here** (`scripts/derive_labels.R`): the labels, Arabic title and Arabic author name are copied unchanged for the release's books. The transliterated author name is the part of the label after the italic title and " of ", up to a final death-date parenthesis `(d. …)` or a life span `(YYYY–YYYY)`; `deathCE` is the CE year in `d. AH/CE`, `d. c. …`, `d. YYYY CE`, or the second year of a life span. Translations (`… (trans. …)`) and labels without " of " give no author name. Per author the most frequent name is used (ties: the name from the alphabetically first book URI).
- **Coverage:** 8,387 of 8,468 books have a label (81 have none; the source uses other URIs for some of them); 254 source URIs are not books of this release and are left out. 3,164 of 3,255 authors have a parsed name.
- **License:** the labels are part of this repository and are released under its license, CC BY-NC-SA 4.0 (below).

## License

Derived from OpenITI release 2023.1.8, https://doi.org/10.5281/zenodo.10007820, under CC BY-NC-SA 4.0 (Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International, https://creativecommons.org/licenses/by-nc-sa/4.0/). The full license text is in [`LICENSE`](LICENSE). Corpus: Lorenz Nigst, Maxim Romanov, Sarah Bowen Savant, Masoumeh Seydi, Peter Verkinderen, Hamidreza Hakimi, *OpenITI: a Machine-Readable Corpus of Islamicate Texts*, release 2023.1.8 (Zenodo, 2023), https://doi.org/10.5281/zenodo.10007820.
