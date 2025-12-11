#' Write assets to Parquet file
#'
#' @param assets_table Assets with SITE_ID and solarday
#' @param output_dir Directory for parquet files
#' @return Path to written parquet file
write_assets_to_parquet <- function(assets_table, output_dir) {
  
  if (is.null(assets_table) || nrow(assets_table) == 0) {
    return(NA_character_)
  }
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  # Use SITE_ID for filename (unique per location)
  site_id <- assets_table$SITE_ID[1]
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S_%OS3")
  
  parquet_file <- file.path(
    output_dir,
    sprintf("%s_%s.parquet", site_id, timestamp)
  )
  
  arrow::write_parquet(assets_table, parquet_file)
  
  message(sprintf("✓ Wrote %d assets to %s", 
                  nrow(assets_table), basename(parquet_file)))
  
  parquet_file
}
#' Consolidate parquet files with distinct()
#'
#' Deduplicates on (SITE_ID, solarday) - one scene per location per day
#'
#' @param parquet_dir Directory containing parquet files
#' @param parquet_files Vector of parquet paths (for dependency tracking)
#' @return Deduplicated assets data frame
consolidate_assets_distinct <- function(parquet_dir, parquet_files) {
  
  all_files <- fs::dir_ls(parquet_dir, glob = "*.parquet")
  
  if (length(all_files) == 0) {
    warning("No parquet files found in ", parquet_dir)
    return(tibble::tibble())
  }
  
  message(sprintf("Reading %d parquet files...", length(all_files)))
  
  # Read all parquets
  assets_all <- arrow::open_dataset(all_files) |>
    dplyr::collect()
  
  n_before <- nrow(assets_all)
  message(sprintf("  Total rows before dedup: %d", n_before))
  
  # Deduplicate on (SITE_ID, solarday)
  # Keep most recent by datetime
  assets_deduped <- assets_all |>
    dplyr::arrange(SITE_ID, solarday, dplyr::desc(datetime)) |>
    dplyr::distinct(SITE_ID, solarday, .keep_all = TRUE)
  
  n_after <- nrow(assets_deduped)
  message(sprintf("  Total rows after dedup: %d", n_after))
  message(sprintf("  Removed %d duplicates", n_before - n_after))
  
  # Summary by SITE_ID
  summary <- assets_deduped |>
    dplyr::count(SITE_ID, name = "n_scenes") |>
    dplyr::arrange(dplyr::desc(n_scenes))
  
  message("\nScenes per location:")
  print(summary)
  
  assets_deduped
}