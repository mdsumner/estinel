# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)
pkgs <- c("tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", "targets", 
          "dplyr", "glue", "digest", "gdalraster", "minioclient")

tar_source()

set_gdal_envs()

ncpus <- as.integer(Sys.getenv("SLURM_JOB_CPUS_PER_NODE"))
if (is.na(ncpus)) ncpus <- 1

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
  # === SETUP ===
  bucket <- "estinel" |> tar_target()
  rootdir <- sprintf("/vsis3/%s", bucket) |> tar_target()
  endpoint <- "https://projects.pawsey.org.au" |> tar_target()
  
  provider <- c("https://earth-search.aws.element84.com/v1/search") |> tar_target()
  collection <- c("sentinel-2-c1-l2a") |> tar_target()
  
  # === LOCATION SETUP ===
  # Define locations from code and Excel files
  tabl <- define_locations_table()   |>  tar_target()
  
  # Compute spatial windows (UTM CRS, extents in projected and lonlat)
  spatial_window <- mk_spatial_window(tabl) |> 
    tar_target(pattern = map(tabl))
  
  # === MARKER-BASED INCREMENTAL PROCESSING ===
  # Read existing markers (returns full table, one row per location)
  markers <- read_markers_all(bucket, spatial_window) |> tar_target()
  
  # Prepare queries with chunking (returns expanded table with all chunks)
  query_specs <- prepare_queries_chunked_all(
    spatial_window, 
    markers,
    default_start = "2015-01-01",
    now = Sys.time(),
    chunk_threshold_days = 365
  ) |> tar_target()  # Single target, no mapping
  
  # === STAC QUERIES ===
  # Build STAC query URLs (adds query column to all rows)
  querytable <- getstac_query_adaptive_all(query_specs, provider, collection) |> 
    tar_target()  # Single target, no mapping
  
  # Branch here for parallel STAC fetching
  # Need to group querytable first
  querytable_grouped <- querytable |> 
    dplyr::mutate(row_id = dplyr::row_number()) |>
    tar_group() |>
    tar_target(iteration = "group")
  
  # Execute STAC queries (one per row)
  stac_json_list <- getstac_json(querytable_grouped) |> 
    tar_target(pattern = map(querytable_grouped), iteration = "list")
  
  # Join results back (by key, not position)
  stac_json_table <- join_stac_results(querytable, stac_json_list) |> 
    tar_target()
  
  # Process STAC results: extract asset URLs, compute solarday
  stac_tables <- process_stac_table2(stac_json_table) |> 
    tar_target(pattern = map(stac_json_table))
  
  stac_tables_consolidated <- consolidate_chunks(stac_tables) |> tar_target()
  
  # Filter to only NEW solardays (> last processed)
  # This is critical for incremental processing
  stac_tables_new <- filter_new_solardays(stac_tables_consolidated) |> tar_target()
  # Unnest assets into flat table for parallel processing
  images_table <- tidyr::unnest(stac_tables_new |> dplyr::select(-js), 
                                cols = c(assets)) |> 
    dplyr::group_by(location, solarday, provider) |> 
    tar_group() |> 
    tar_target(iteration = "group")
  
  # === IMAGE PROCESSING ===
  # Build Scene Classification Layer (SCL) for cloud detection
  scl_tifs <- build_scl_dsn(images_table, root = rootdir) |> 
    tar_target(pattern = map(images_table))
  
  # Compute clear-sky percentage
  scl_clear <- filter_fun(read_dsn(scl_tifs)) |> 
    tar_target(pattern = map(scl_tifs), iteration = "vector")
  
  # Add SCL results and group by location/solarday/collection
  group_table <- images_table |> 
    mutate(scl_tif = scl_tifs[tar_group], 
           clear_test = scl_clear[tar_group]) |> 
    make_group_table_providers(provider, collection) |>
    group_by(location, solarday, collection) |> 
    tar_group() |>
    tar_target(iteration = "group")
  
  # Build RGB composite GeoTIFFs
  # dsn_table <- build_image_dsn(group_table, rootdir = rootdir) |> 
  #   tar_target(pattern = map(group_table))
  # 
  ## AFTER (with CAS tracking):
  dsn_table_tracked <- build_image_dsn_tracked(group_table, rootdir = rootdir) |> 
     tar_target(pattern = map(group_table))
  # 
  # Validate markers
  #dsn_validation <- validate_all_markers(dsn_table_tracked) |> tar_target()
  # 
  # # Extract paths for downstream use
  #dsn_table <- extract_s3_paths(dsn_table_tracked, "outfile") |> tar_target()
  dsn_table <- dsn_table_tracked |> tar_target()
  # Generate PNG views with different stretches
  view_q128 <- build_image_png(dsn_table, force = FALSE, type = "q128") |> 
    tar_target(pattern = map(dsn_table))
  view_histeq <- build_image_png(dsn_table, force = FALSE, type = "histeq") |> 
    tar_target(pattern = map(dsn_table))
  view_stretch <- build_image_png(dsn_table, force = FALSE, type = "stretch") |> 
    tar_target(pattern = map(dsn_table))
  
  # Generate thumbnails
  thumb_q128 <- build_thumb(view_q128, force = FALSE) |> 
    tar_target(pattern = map(view_q128)) 
  thumb_histeq <- build_thumb(view_histeq, force = FALSE) |> 
    tar_target(pattern = map(view_histeq)) 
  thumb_stretch <- build_thumb(view_stretch, force = FALSE) |> 
    tar_target(pattern = map(view_stretch))
  
  # === OUTPUT PREPARATION ===
  # Combine all outputs and convert /vsis3 paths to HTTP URLs
  viewtableNA <- mutate(
    dsn_table, 
    view_q128 = view_q128, 
    view_histeq = view_histeq, 
    view_stretch = view_stretch, 
    thumb_q128 = thumb_q128, 
    thumb_histeq = thumb_histeq, 
    thumb_stretch = thumb_stretch
  ) |>
    mutate(
      outfile = gsub("/vsis3", endpoint, outfile),
      view_q128 = gsub("/vsis3", endpoint, view_q128),
      view_histeq = gsub("/vsis3", endpoint, view_histeq),
      view_stretch = gsub("/vsis3", endpoint, view_stretch),
      scl_tif = gsub("/vsis3", endpoint, scl_tif),
      thumb_q128 = gsub("/vsis3", endpoint, thumb_q128), 
      thumb_histeq = gsub("/vsis3", endpoint, thumb_histeq), 
      thumb_stretch = gsub("/vsis3", endpoint, thumb_stretch)
    ) |> 
    tar_force(force = TRUE)
  
  # Filter out failed processing (NA outputs)
  viewtable <- viewtableNA |> 
    dplyr::filter(!is.na(outfile), !is.na(view_q128)) |>
    tar_force(force = TRUE)
  
  
  catalog_table <- build_catalog_from_s3(bucket, "sentinel-2-c1-l2a", tabl, wait_for = viewtable) |> tar_force(force = TRUE)
  catalog_audit <- audit_catalog_locations(catalog_table, tabl) |> tar_force(force = TRUE)

  # === WEB INTERFACE ===
  # Write catalog JSON for React frontend
  pagejson <- write_react_json(catalog_table) |> tar_force(force = TRUE)
  web <- update_react(pagejson, rootdir) |> tar_force(force = TRUE)
  
#  browser_update <- check_and_update_browser(
#    local_path = "inst/docs/catalog-browser.html",
#    remote_url = "https://projects.pawsey.org.au/estinel/catalog/catalog-browser.html",
#    bucket = "estinel"
#  ) |>
#    tar_target(
#      cue = tar_cue(mode = "always")  # Always check (but only upload if needed)
#    )
  
  # === UPDATE MARKERS ===
  # After successful processing, update markers with latest solarday
  # This enables the next run to start from where we left off
  updated_markers <- update_markers(viewtable) |> tar_target()
  marker_status <- write_markers(bucket, updated_markers) |> tar_target()
 
  
  # Upload catalog to GitHub Release (replaces git tracking)
  catalog_release <- upload_catalog_to_release(
    pagejson, 
    repo = "mdsumner/estinel",
    tag = "catalog-data"
  ) |> 
    tar_target(
      cue = tar_cue(mode = "always")  # Always upload when catalog changes
    )
  
})
