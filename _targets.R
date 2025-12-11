# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)
pkgs <- c("tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", "targets", 
          "dplyr", "glue", "digest", "gdalraster", "minioclient")

tar_source()

set_gdal_envs()

ncpus <- 24
log_directory <- "_targets/logs"
# Ensure credentials available to workers
if (Sys.getenv("AWS_ACCESS_KEY_ID") == "") {
  Sys.setenv(
    AWS_ACCESS_KEY_ID = Sys.getenv("PAWSEY_AWS_ACCESS_KEY_ID"),
    AWS_SECRET_ACCESS_KEY = Sys.getenv("PAWSEY_AWS_SECRET_ACCESS_KEY")
  )
}
tar_option_set(
  controller = if (ncpus <= 1) NULL else crew_controller_local(
    workers = ncpus,
    options_local = crew_options_local(log_directory = log_directory)
  ),
  format = "qs",
  packages = pkgs
)

tar_assign({
  
  # =============================================================================
  # CONFIGURATION
  # =============================================================================
  
  # S3 Configuration
  bucket <- "estinel" |> tar_target()
  endpoint <- "https://projects.pawsey.org.au" |> tar_target()
  
  # STAC Configuration
  provider <- "https://earth-search.aws.element84.com/v1/search" |> tar_target()
  collection <- "sentinel-2-c1-l2a" |> tar_target()
  
  # Output Configuration
  # OPTIONS:
  # - Local: tempdir()
  # - S3: sprintf("/vsis3/%s", bucket)
  rootdir <- tempdir() |> tar_target()  # Change to /vsis3/estinel for S3
  assets_parquet_store <- "_targets/assets_parquet" |> tar_target()
  
  # =============================================================================
  # LOCATIONS TABLE
  # =============================================================================
  
  # Single test location: Noville Peninsula
  #locations0 <- define_test_location() |> tar_target()
  #locations <- rbind(locations0, define_locations_table()) |> 
  #  distinct(location, SITE_ID, .keep_all = TRUE) |> tar_target()
  locations <- define_locations_table() |> clean_locations_table()  |> tar_target()
  #locations <- define_locations_clean() |> tar_target()
  
  
  # Compute spatial window (UTM CRS, bbox in projected + lonlat)
  spatial_window <- compute_spatial_window(locations) |> 
    tar_target(pattern = map(locations))
  
  # =============================================================================
  # QUERY GENERATION
  # =============================================================================
  query_specs <- prepare_query(spatial_window,start_date = "2022-01-01", 
                               end_date = "2022-06-30", collection, provider) |> 
                                 tar_target(pattern = map(spatial_window), iteration = "list")
  

  # Process assets (parallel, by location)
  assets_table <- get_assets_from_urls(query_specs) |>
     tar_target(pattern = map(query_specs))

  # =============================================================================
  # ADD KEYS (Minimal - just what's needed for join)
  # =============================================================================
  
  # Add SITE_ID for joining later
  # solarday already in assets_table from get_assets()
  assets_with_keys <- assets_table |>
    dplyr::mutate(
      SITE_ID = spatial_window$SITE_ID,
      collection = collection  # Add collection for completeness
    ) |> 
    tar_target(pattern = map(assets_table, spatial_window))
  
  # Write to Parquet (parallel, safe for concurrent writes)
  # Each branch gets its own file
  assets_parquet <- write_assets_to_parquet(
    assets_with_keys,
    output_dir = assets_parquet_store
  ) |>
    tar_target(
      pattern = map(assets_with_keys),
      format = "file"  # Track file path
    )

  # =============================================================================
  # SINGLE-THREAD: Consolidate with distinct()
  # =============================================================================
  
  # Read all parquets and deduplicate
  # Key: (SITE_ID, solarday) - uniquely identifies a scene for a location
  assets_consolidated <- consolidate_assets_distinct(
    parquet_dir = assets_parquet_store,
    parquet_files = assets_parquet
  ) |> 
    tar_target()
  
  # =============================================================================
  # RENDERING (Join with spatial_window when needed)
  # =============================================================================
  
  # Filter to assets we want to render (e.g., cloud cover < 30)
  # assets_to_render <- assets_consolidated |>
  #   dplyr::filter(cloud_cover < 30) |>
  #   tar_target()
  # 
  # # NOW join with spatial_window to get bbox, crs, resolution, etc.
  # render_specs <- assets_to_render |>
  #   dplyr::left_join(spatial_window, by = "SITE_ID") |>
  #   tar_target()
  # 
  # # Render images (has everything needed: assets + spatial metadata)
  # rgb_images <- render_rgb_composite(render_specs) |>
  #   tar_target(pattern = map(render_specs))
  # # === MARKER-BASED INCREMENTAL PROCESSING ===
  # # Read existing markers to determine start date per location
  # # If no marker exists, will start from 2015-01-01
  # markers <- read_markers(bucket, spatial_window) |> tar_target()
  # 
  # # Use chunked query preparation
  # query_specs <- prepare_queries_chunked(  # <-- Changed function!
  #   spatial_window, 
  #   markers,
  #   default_start = "2015-01-01",
  #   now = Sys.time(),
  #   chunk_threshold_days = 365  # Bootstrap chunks into years
  # ) |> tar_target()
  # 
  # # === STAC QUERIES ===
  # # Build STAC query URLs with per-location adaptive date ranges
  # # No more yearly chunking - queries are precise to what's needed
  # querytable <- getstac_query_adaptive(query_specs, provider, collection) |> 
  #   tar_target(pattern = map(query_specs))
  # 
  # # Execute STAC queries
  # stac_json_list <- getstac_json(querytable) |> 
  #   tar_target(pattern = map(querytable), iteration = "list")
  # 
  # # Join query metadata with results
  # stac_json_table <- join_stac_json(querytable, stac_json_list) |> 
  #   tar_target()
  # 
  # # Process STAC results: extract asset URLs, compute solarday
  # stac_tables <- process_stac_table2(stac_json_table) |> 
  #   tar_target(pattern = map(stac_json_table))
  # 
  # stac_tables_consolidated <- consolidate_chunks(stac_tables) |> tar_target()
  # 
  # # Filter to only NEW solardays (> last processed)
  # # This is critical for incremental processing
  # stac_tables_new <- filter_new_solardays(stac_tables_consolidated) |> tar_target()
  # # Unnest assets into flat table for parallel processing
  # images_table <- tidyr::unnest(stac_tables_new |> dplyr::select(-js), 
  #                               cols = c(assets)) |> 
  #   dplyr::group_by(location, solarday, provider) |> 
  #   tar_group() |> 
  #   tar_target(iteration = "group")
  # 
  # # === IMAGE PROCESSING ===
  # # Build Scene Classification Layer (SCL) for cloud detection
  # scl_tifs <- build_scl_dsn(images_table, root = rootdir) |> 
  #   tar_target(pattern = map(images_table))
  # 
  # # Compute clear-sky percentage
  # scl_clear <- filter_fun(read_dsn(scl_tifs)) |> 
  #   tar_target(pattern = map(scl_tifs), iteration = "vector")
  # 
  # # Add SCL results and group by location/solarday/collection
  # group_table <- images_table |> 
  #   mutate(scl_tif = scl_tifs[tar_group], 
  #          clear_test = scl_clear[tar_group]) |> 
  #   make_group_table_providers(provider, collection) |>
  #   group_by(location, solarday, collection) |> 
  #   tar_group() |>
  #   tar_target(iteration = "group")
  # 
  # # Build RGB composite GeoTIFFs
  # # dsn_table <- build_image_dsn(group_table, rootdir = rootdir) |> 
  # #   tar_target(pattern = map(group_table))
  # # 
  # ## AFTER (with CAS tracking):
  # dsn_table_tracked <- build_image_dsn_tracked(group_table, rootdir = rootdir) |> 
  #    tar_target(pattern = map(group_table))
  # # 
  # # Validate markers
  # dsn_validation <- validate_all_markers(dsn_table_tracked) |> tar_target()
  # # 
  # # # Extract paths for downstream use
  # #dsn_table <- extract_s3_paths(dsn_table_tracked, "outfile") |> tar_target()
  # dsn_table <- dsn_table_tracked |> tar_target()
  # # Generate PNG views with different stretches
  # view_q128 <- build_image_png(dsn_table, force = FALSE, type = "q128") |> 
  #   tar_target(pattern = map(dsn_table))
  # view_histeq <- build_image_png(dsn_table, force = FALSE, type = "histeq") |> 
  #   tar_target(pattern = map(dsn_table))
  # view_stretch <- build_image_png(dsn_table, force = FALSE, type = "stretch") |> 
  #   tar_target(pattern = map(dsn_table))
  # 
  # # Generate thumbnails
  # thumb_q128 <- build_thumb(view_q128, force = FALSE) |> 
  #   tar_target(pattern = map(view_q128)) 
  # thumb_histeq <- build_thumb(view_histeq, force = FALSE) |> 
  #   tar_target(pattern = map(view_histeq)) 
  # thumb_stretch <- build_thumb(view_stretch, force = FALSE) |> 
  #   tar_target(pattern = map(view_stretch))
  # 
  # # === OUTPUT PREPARATION ===
  # # Combine all outputs and convert /vsis3 paths to HTTP URLs
  # viewtableNA <- mutate(
  #   dsn_table, 
  #   view_q128 = view_q128, 
  #   view_histeq = view_histeq, 
  #   view_stretch = view_stretch, 
  #   thumb_q128 = thumb_q128, 
  #   thumb_histeq = thumb_histeq, 
  #   thumb_stretch = thumb_stretch
  # ) |>
  #   mutate(
  #     outfile = gsub("/vsis3", endpoint, outfile),
  #     view_q128 = gsub("/vsis3", endpoint, view_q128),
  #     view_histeq = gsub("/vsis3", endpoint, view_histeq),
  #     view_stretch = gsub("/vsis3", endpoint, view_stretch),
  #     scl_tif = gsub("/vsis3", endpoint, scl_tif),
  #     thumb_q128 = gsub("/vsis3", endpoint, thumb_q128), 
  #     thumb_histeq = gsub("/vsis3", endpoint, thumb_histeq), 
  #     thumb_stretch = gsub("/vsis3", endpoint, thumb_stretch)
  #   ) |> 
  #   tar_force(force = TRUE)
  # 
  # # Filter out failed processing (NA outputs)
  # viewtable <- viewtableNA |> 
  #   dplyr::filter(!is.na(outfile), !is.na(view_q128)) |>
  #   tar_force(force = TRUE)
  # 
  # 
  # catalog_table <- build_catalog_from_s3(bucket, "sentinel-2-c1-l2a", tabl, wait_for = viewtable) |> tar_force(force = TRUE)
  # catalog_audit <- audit_catalog_locations(catalog_table, tabl) |> tar_force(force = TRUE)
  # 
  # # === WEB INTERFACE ===
  # # Write catalog JSON for React frontend
  # pagejson <- write_react_json(catalog_table) |> tar_force(force = TRUE)
  # web <- update_react(pagejson, rootdir) |> tar_force(force = TRUE)
  # 
  # browser_update <- check_and_update_browser(
  #   local_path = "inst/docs/catalog-browser.html",
  #   remote_url = "https://projects.pawsey.org.au/estinel/catalog/catalog-browser.html",
  #   bucket = "estinel"
  # ) |>
  #   tar_target(
  #     cue = tar_cue(mode = "always")  # Always check (but only upload if needed)
  #   )
  # 
  # # === UPDATE MARKERS ===
  # # After successful processing, update markers with latest solarday
  # # This enables the next run to start from where we left off
  # updated_markers <- update_markers(viewtable) |> tar_target()
  # marker_status <- write_markers(bucket, updated_markers) |> tar_target()
  # 
  # 
  # # Upload catalog to GitHub Release (replaces git tracking)
  # catalog_release <- upload_catalog_to_release(
  #   pagejson, 
  #   repo = "mdsumner/estinel",
  #   tag = "catalog-data"
  # ) |> 
  #   tar_target(
  #     cue = tar_cue(mode = "always")  # Always upload when catalog changes
  #   )
  # 
})
