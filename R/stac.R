# ==============================================================================
# STAC Query Functions
# ==============================================================================
# Fetches assets from STAC queries with automatic pagination
# ==============================================================================

#' Get assets from STAC query URLs
#'
#' Wrapper around sds::stacit() that fetches results and extracts assets.
#' Handles anti-meridian splits and pagination automatically.
#'
#' @param bbox Bounding box [lonmin, lonmax, latmin, latmax]
#' @param dates Date range c(start, end)
#' @param collection STAC collection name
#' @param provider STAC provider URL
#' @param limit Results per page (default 300)
#' @return Tibble with asset URLs and metadata
#' @export
#'
#' @examples
#' # Single location
#' assets <- get_assets(
#'   bbox = c(162, 164, -78, -77),
#'   dates = c("2024-01-01", "2024-12-31"),
#'   collection = "sentinel-2-c1-l2a"
#' )
#'
#' # Crosses anti-meridian (automatically handled)
#' assets <- get_assets(
#'   bbox = c(174, 182, -22, -15),  # Fiji
#'   dates = c("2024-01-01", "2024-12-31")
#' )
get_assets <- function(bbox, 
                       dates, 
                       collection = "sentinel-2-c1-l2a",
                       provider = "https://earth-search.aws.element84.com/v1/search",
                       limit = 300) {
  
  # Build query URL(s) with sds::stacit()
  # Returns 1 URL normally, 2 URLs if crosses anti-meridian
  query_urls <- sds::stacit(
    bbox,
    date = dates,
    limit = limit,
    collections = collection,
    provider = provider
  )
  
  # Fetch assets
  get_assets_from_urls(query_urls)
}

#' Get assets from pre-built query URLs
#'
#' @param query_urls Query URL(s) from sds::stacit()
#' @return Tibble with asset URLs and metadata
#' @export
get_assets_from_urls <- function(query_urls) {
  
  if (length(query_urls) > 1) {
    # Multiple queries (anti-meridian case)
    results <- lapply(query_urls, get_assets_single)
    dplyr::bind_rows(results)
  } else {
    get_assets_single(query_urls)
  }
}

#' Internal: Fetch single STAC query with pagination
#'
#' @param query_url STAC query URL
#' @return Tibble with assets + metadata
get_assets_single <- function(query_url) {
  
  # Fetch STAC results
  json <- tryCatch(
    jsonlite::fromJSON(query_url),
    error = function(e) {
      warning("Failed to fetch STAC results: ", e$message)
      return(NULL)
    }
  )
  
  if (is.null(json) || length(json$features) == 0) {
    return(NULL)
  }
  
  # Process each feature (features is a data frame)
  # Split into rows and lapply over them
  results <- lapply(
    split(json$features, seq_len(nrow(json$features))), 
    process_feature
  )
  
  # Convert to tibble
  df <- dplyr::bind_rows(lapply(results, tibble::as_tibble))
  
  # Pagination: fetch next page if it exists
  if (!is.null(json$links)) {
    next_link <- json$links[json$links$rel == "next", ]
    if (nrow(next_link) > 0) {
      next_url <- next_link$href[1]
      next_results <- get_assets_single(next_url)
      if (!is.null(next_results)) {
        df <- dplyr::bind_rows(df, next_results)
      }
    }
  }
  
  df
}

#' Internal: Extract assets and metadata from single feature
#'
#' @param feature Single STAC feature (one row from features data frame)
#' @return Named list with assets + metadata
process_feature <- function(feature) {
  
  # Extract asset URLs
  assets <- feature$assets
  
  # Asset types to extract (imagery + masks, no metadata files)
  asset_names <- c(
    "red", "green", "blue", "visual", "nir", "swir22",
    "rededge2", "rededge3", "rededge1", "swir16", "wvp",
    "nir08", "scl", "aot", "coastal", "nir09", "cloud", "snow", "preview"
  )
  
  asset_list <- lapply(asset_names, function(name) {
    if (!is.null(assets[[name]])) assets[[name]]$href else NA_character_
  })
  names(asset_list) <- asset_names
  
  # Extract metadata from properties
  props <- feature$properties
  
  # Datetime
  datetime_str <- props$datetime
  datetime_utc <- if (!is.null(datetime_str)) {
    as.POSIXct(datetime_str, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  } else {
    as.POSIXct(NA)
  }
  
  # Scene ID
  scene_id <- feature$id
  
  # Centroid (from proj:centroid or compute from bbox)
  if (!is.null(props$`proj:centroid`)) {
    centroid_lat <- props$`proj:centroid`$lat
    centroid_lon <- props$`proj:centroid`$lon
  } else if (!is.null(feature$bbox)) {
    bbox <- feature$bbox
    centroid_lon <- (bbox[1] + bbox[3]) / 2
    centroid_lat <- (bbox[2] + bbox[4]) / 2
  } else {
    centroid_lon <- NA_real_
    centroid_lat <- NA_real_
  }
  
  # Solarday (local date at centroid)
  if (!is.na(datetime_utc) && !is.na(centroid_lon)) {
    offset_hours <- centroid_lon / 15
    solarday <- as.Date(round(datetime_utc - offset_hours * 3600, "days"))
  } else {
    solarday <- as.Date(NA)
  }
  
  # Additional metadata
  metadata_list <- list(
    datetime = datetime_utc,
    scene_id = scene_id,
    centroid_lon = centroid_lon,
    centroid_lat = centroid_lat,
    solarday = solarday,
    cloud_cover = props$`eo:cloud_cover`,
    platform = props$platform,
    mgrs_grid_square = props$`mgrs:grid_square`,
    mgrs_latitude_band = props$`mgrs:latitude_band`,
    mgrs_utm_zone = props$`mgrs:utm_zone`,
    epsg = props$`proj:epsg`
  )
  
  c(asset_list, metadata_list)
}

# ==============================================================================
# DUCKDB (from v2 barebones)
# ==============================================================================

#' Write assets to DuckDB with deduplication
write_assets_to_duckdb <- function(assets_df, db_path = "assets.duckdb") {
  
  if (is.null(assets_df) || nrow(assets_df) == 0) {
    message("No assets to write")
    return(db_path)
  }
  
  # Validate required columns
  required_cols <- c("location", "solarday", "collection")
  missing <- setdiff(required_cols, names(assets_df))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }
  
  # Add timestamp
  assets_df$created_at <- Sys.time()
  
  # Connect to DuckDB
  con <- duckdb::dbConnect(duckdb::duckdb(), db_path)
  on.exit(duckdb::dbDisconnect(con))
  
  # Create table if doesn't exist
  duckdb::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS assets (
      location TEXT NOT NULL,
      solarday DATE NOT NULL,
      collection TEXT NOT NULL,
      red TEXT,
      green TEXT,
      blue TEXT,
      nir TEXT,
      scl TEXT,
      swir16 TEXT,
      swir22 TEXT,
      nir08 TEXT,
      coastal TEXT,
      rededge1 TEXT,
      rededge2 TEXT,
      rededge3 TEXT,
      datetime TIMESTAMP,
      scene_id TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (location, solarday, collection)
    )
  ")
  
  # Create temp table with new data
  duckdb::dbWriteTable(con, "assets_new", assets_df, overwrite = TRUE, temporary = TRUE)
  
  # Merge: Insert new or update existing
  duckdb::dbExecute(con, "
    INSERT INTO assets
    SELECT * FROM assets_new
    ON CONFLICT (location, solarday, collection) 
    DO UPDATE SET
      red = EXCLUDED.red,
      green = EXCLUDED.green,
      blue = EXCLUDED.blue,
      nir = EXCLUDED.nir,
      scl = EXCLUDED.scl,
      swir16 = EXCLUDED.swir16,
      swir22 = EXCLUDED.swir22,
      nir08 = EXCLUDED.nir08,
      coastal = EXCLUDED.coastal,
      rededge1 = EXCLUDED.rededge1,
      rededge2 = EXCLUDED.rededge2,
      rededge3 = EXCLUDED.rededge3,
      datetime = EXCLUDED.datetime,
      scene_id = EXCLUDED.scene_id,
      created_at = EXCLUDED.created_at
    WHERE EXCLUDED.created_at > assets.created_at
  ")
  
  # Get counts
  n_new <- nrow(assets_df)
  n_total <- duckdb::dbGetQuery(con, "SELECT COUNT(*) as n FROM assets")$n
  
  message(sprintf("✓ Wrote %d assets (total: %d)", n_new, n_total))
  
  db_path
}



#' Consolidate all Parquet files into DuckDB with deduplication
#'
#' @param parquet_files Vector of parquet file paths
#' @param db_path Path to DuckDB database
#' @return Path to database
consolidate_assets_to_duckdb <- function(parquet_files, db_path) {
  
  # Remove NA files (from locations with no data)
  parquet_files <- parquet_files[!is.na(parquet_files)]
  
  if (length(parquet_files) == 0) {
    warning("No parquet files to consolidate")
    return(db_path)
  }
  
  message(sprintf("Consolidating %d parquet files into DuckDB...", 
                  length(parquet_files)))
  
  # Connect to DuckDB
  con <- duckdb::dbConnect(duckdb::duckdb(), db_path)
  on.exit(duckdb::dbDisconnect(con))
  
  # Create table if doesn't exist
  duckdb::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS assets (
      location TEXT NOT NULL,
      solarday DATE NOT NULL,
      collection TEXT NOT NULL,
      red TEXT,
      green TEXT,
      blue TEXT,
      nir TEXT,
      scl TEXT,
      swir16 TEXT,
      swir22 TEXT,
      datetime TIMESTAMP,
      scene_id TEXT,
      cloud_cover DOUBLE,
      platform TEXT,
      mgrs_grid_square TEXT,
      mgrs_latitude_band TEXT,
      mgrs_utm_zone INTEGER,
      epsg INTEGER,
      centroid_lon DOUBLE,
      centroid_lat DOUBLE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (location, solarday, collection)
    )
  ")
  
  # Read and insert each parquet file
  n_inserted <- 0
  n_updated <- 0
  
  for (parquet_file in parquet_files) {
    
    # Read parquet
    assets_df <- arrow::read_parquet(parquet_file)
    
    if (nrow(assets_df) == 0) next
    
    # Add timestamp
    assets_df$created_at <- Sys.time()
    
    # Write to temp table
    duckdb::dbWriteTable(con, "assets_temp", assets_df, 
                         overwrite = TRUE, temporary = TRUE)
    
    # Count new vs updates
    existing <- duckdb::dbGetQuery(con, "
      SELECT COUNT(*) as n 
      FROM assets a
      JOIN assets_temp t 
      ON a.location = t.location 
      AND a.solarday = t.solarday 
      AND a.collection = t.collection
    ")$n
    
    n_new <- nrow(assets_df) - existing
    n_updated <- n_updated + existing
    n_inserted <- n_inserted + n_new
    
    # Merge with deduplication
    duckdb::dbExecute(con, "
      INSERT INTO assets
      SELECT * FROM assets_temp
      ON CONFLICT (location, solarday, collection) 
      DO UPDATE SET
        red = EXCLUDED.red,
        green = EXCLUDED.green,
        blue = EXCLUDED.blue,
        nir = EXCLUDED.nir,
        scl = EXCLUDED.scl,
        swir16 = EXCLUDED.swir16,
        swir22 = EXCLUDED.swir22,
        datetime = EXCLUDED.datetime,
        scene_id = EXCLUDED.scene_id,
        cloud_cover = EXCLUDED.cloud_cover,
        platform = EXCLUDED.platform,
        mgrs_grid_square = EXCLUDED.mgrs_grid_square,
        mgrs_latitude_band = EXCLUDED.mgrs_latitude_band,
        mgrs_utm_zone = EXCLUDED.mgrs_utm_zone,
        epsg = EXCLUDED.epsg,
        centroid_lon = EXCLUDED.centroid_lon,
        centroid_lat = EXCLUDED.centroid_lat,
        created_at = EXCLUDED.created_at
      WHERE EXCLUDED.created_at > assets.created_at
    ")
    
    message(sprintf("  ✓ Processed %s (%d assets)", 
                    basename(parquet_file), nrow(assets_df)))
  }
  
  # Get final count
  n_total <- duckdb::dbGetQuery(con, "SELECT COUNT(*) as n FROM assets")$n
  
  message(sprintf("
✓ Consolidation complete:
  - Inserted: %d new assets
  - Updated: %d existing assets
  - Total in database: %d assets
", n_inserted, n_updated, n_total))
  
  db_path
}