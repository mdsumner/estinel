# Estinel Targets Pipeline - Annotated with Pattern/Iteration Controls
# Shows exactly where and how dynamic branching and iteration work

library(targets)
library(tarchetypes)
library(crew)

pkgs <- c("tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", 
          "targets", "dplyr", "glue", "digest", "gdalraster")

tar_source()
set_gdal_envs()

ncpus <- 24

tar_option_set(
  controller = crew_controller_local(workers = ncpus),
  format = "qs",
  packages = pkgs
)

tar_assign({
  
  # =========================================================================
  # STATIC TARGETS (no pattern, computed once)
  # =========================================================================
  
  bucket <- "estinel" |> 
    tar_target()
    # No pattern: single value
  
  rootdir <- sprintf("/vsis3/%s", bucket) |> 
    tar_target()
    # No pattern: derived from bucket
  
  endpoint <- "https://projects.pawsey.org.au" |> 
    tar_target()
    # No pattern: single URL
  
  provider <- c("https://earth-search.aws.element84.com/v1/search") |> 
    tar_target()
    # No pattern: single STAC provider
  
  collection <- c("sentinel-2-c1-l2a") |> 
    tar_target()
    # No pattern: single collection
  
  tabl <- define_locations_table() |> 
    tar_target()
    # No pattern: returns single data frame with all locations
  
  # =========================================================================
  # FIRST DYNAMIC BRANCHING (map over locations)
  # =========================================================================
  
  spatial_window <- mk_spatial_window(tabl) |> 
    tar_target(pattern = map(tabl))
    # pattern = map(tabl): Creates one branch per ROW in tabl
    # If tabl has 20 rows → 20 branches of spatial_window
    # Each branch processes one location independently
  
  # =========================================================================
  # MARKER WORKFLOW (back to static)
  # =========================================================================
  
  markers <- read_markers(bucket, spatial_window) |> 
    tar_target()
    # No pattern: reads ALL markers in one go
    # Takes spatial_window as input (all branches combined)
  
  query_specs <- prepare_queries(
    spatial_window, 
    markers,
    default_start = "2015-01-01",
    now = Sys.time()
  ) |> 
    tar_target()
    # No pattern: prepares queries for ALL locations in one data frame
    # Returns data frame with one row per location
  
  # =========================================================================
  # SECOND DYNAMIC BRANCHING (map over query specs)
  # =========================================================================
  
  querytable <- getstac_query_adaptive(query_specs, provider, collection) |> 
    tar_target(pattern = map(query_specs))
    # pattern = map(query_specs): One branch per ROW in query_specs
    # Each branch builds STAC query for one location
    # Parallelizes STAC query construction
  
  stac_json_list <- getstac_json(querytable) |> 
    tar_target(pattern = map(querytable), iteration = "list")
    # pattern = map(querytable): One branch per query
    # iteration = "list": Each branch returns a list (JSON results)
    # "list" iteration preserves list structure through aggregation
  
  stac_json_table <- join_stac_json(querytable, stac_json_list) |> 
    tar_target()
    # No pattern: Combines ALL branches back into single data frame
    # Takes all querytable branches + all stac_json_list branches
  
  stac_tables <- process_stac_table2(stac_json_table) |> 
    tar_target(pattern = map(stac_json_table))
    # pattern = map(stac_json_table): One branch per ROW
    # Each branch extracts assets from one location's STAC results
  
  stac_tables_new <- filter_new_solardays(stac_tables) |> 
    tar_target()
    # No pattern: Filters ALL branches in one operation
    # Returns combined data frame of only new dates
  
  # =========================================================================
  # THIRD DYNAMIC BRANCHING (tar_group custom grouping)
  # =========================================================================
  
  images_table <- tidyr::unnest(stac_tables_new |> dplyr::select(-js), 
                                cols = c(assets)) |> 
    dplyr::group_by(location, solarday, provider) |> 
    tar_group() |> 
    tar_target(iteration = "group")
    # tar_group(): Creates custom groups via group_by()
    # iteration = "group": Each branch is one GROUP
    # Group = unique combination of (location, solarday, provider)
    # If 20 locations × 5 days → up to 100 branches
    # Each branch processes one location-date combination
  
  # =========================================================================
  # IMAGE PROCESSING (map over groups)
  # =========================================================================
  
  scl_tifs <- build_scl_dsn(images_table, root = rootdir) |> 
    tar_target(pattern = map(images_table))
    # pattern = map(images_table): One branch per GROUP from images_table
    # Each branch builds SCL layer for one location-date
  
  scl_clear <- filter_fun(read_dsn(scl_tifs)) |> 
    tar_target(pattern = map(scl_tifs), iteration = "vector")
    # pattern = map(scl_tifs): One branch per scl_tif
    # iteration = "vector": Each branch returns a single value (clear %)
    # "vector" combines results into atomic vector
  
  # =========================================================================
  # FOURTH DYNAMIC BRANCHING (regroup after adding SCL results)
  # =========================================================================
  
  group_table <- images_table |> 
    mutate(scl_tif = scl_tifs[tar_group],      # Match by tar_group index
           clear_test = scl_clear[tar_group]) |>  # Match by tar_group index
    make_group_table_providers(provider, collection) |>
    group_by(location, solarday, collection) |> 
    tar_group() |>
    tar_target(iteration = "group")
    # tar_group() again: Regroup after adding scl results
    # iteration = "group": Each branch is one (location, solarday, collection)
    # This regrouping is needed after adding provider dimension
  
  # =========================================================================
  # RGB PROCESSING (map over groups)
  # =========================================================================
  
  dsn_table <- build_image_dsn(group_table, rootdir = rootdir) |> 
    tar_target(pattern = map(group_table))
    # pattern = map(group_table): One branch per group
    # Each branch builds RGB GeoTIFF for one location-date
  
  # =========================================================================
  # PNG GENERATION (3 types × map)
  # =========================================================================
  
  view_q128 <- build_image_png(dsn_table, force = FALSE, type = "q128") |> 
    tar_target(pattern = map(dsn_table))
    # pattern = map(dsn_table): One branch per dsn
    # Each branch creates q128 stretch PNG
  
  view_histeq <- build_image_png(dsn_table, force = FALSE, type = "histeq") |> 
    tar_target(pattern = map(dsn_table))
    # pattern = map(dsn_table): Same as above, different stretch
  
  view_stretch <- build_image_png(dsn_table, force = FALSE, type = "stretch") |> 
    tar_target(pattern = map(dsn_table))
    # pattern = map(dsn_table): Same as above, different stretch
  
  # =========================================================================
  # THUMBNAIL GENERATION (map over PNGs)
  # =========================================================================
  
  thumb_q128 <- build_thumb(view_q128, force = FALSE) |> 
    tar_target(pattern = map(view_q128))
    # pattern = map(view_q128): One branch per PNG
  
  thumb_histeq <- build_thumb(view_histeq, force = FALSE) |> 
    tar_target(pattern = map(view_histeq))
    # pattern = map(view_histeq): One branch per PNG
  
  thumb_stretch <- build_thumb(view_stretch, force = FALSE) |> 
    tar_target(pattern = map(view_stretch))
    # pattern = map(view_stretch): One branch per PNG
  
  # =========================================================================
  # OUTPUT AGGREGATION (back to static with tar_force)
  # =========================================================================
  
  viewtableNA <- mutate(
    dsn_table,  # Uses ALL branches of dsn_table
    view_q128 = view_q128,      # Uses ALL branches
    view_histeq = view_histeq,  # Uses ALL branches
    view_stretch = view_stretch,  # Uses ALL branches
    thumb_q128 = thumb_q128,    # Uses ALL branches
    thumb_histeq = thumb_histeq,  # Uses ALL branches
    thumb_stretch = thumb_stretch  # Uses ALL branches
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
    # tar_force(force = TRUE): Always rebuild this target
    # No pattern: Combines all branches into final table
  
  viewtable <- viewtableNA |> 
    dplyr::filter(!is.na(outfile), !is.na(view_q128)) |>
    tar_force(force = TRUE)
    # tar_force(force = TRUE): Always rebuild
    # Filters out failed processing
  
  # =========================================================================
  # WEB CATALOG (static with tar_force)
  # =========================================================================
  
  json <- write_react_json(viewtable) |> 
    tar_force(force = TRUE)
    # tar_force(force = TRUE): Always rebuild catalog JSON
  
  web <- update_react(json, rootdir) |> 
    tar_force(force = TRUE)
    # tar_force(force = TRUE): Always update web interface
  
  # =========================================================================
  # MARKER UPDATE (static - writes all markers)
  # =========================================================================
  
  updated_markers <- update_markers(viewtable) |> 
    tar_target()
    # No pattern: Processes entire viewtable at once
    # Extracts max(solarday) per location
  
  marker_status <- write_markers(bucket, updated_markers) |> 
    tar_target()
    # No pattern: Writes ALL markers in one operation
    # Returns vector of success/fail per marker
})

# ============================================================================
# PATTERN/ITERATION QUICK REFERENCE
# ============================================================================

# pattern = map(dependency)
#   - Creates one branch per ROW in dependency target
#   - Most common pattern for parallelization
#   - Example: map(tabl) with 20 rows → 20 branches
#
# pattern = cross(dep1, dep2)
#   - Creates branches for EVERY COMBINATION of dep1 and dep2
#   - Example: cross(locations, dates) → locations × dates branches
#   - Not used in this pipeline
#
# iteration = "vector"
#   - Each branch returns a single atomic value
#   - Results combined into vector
#   - Example: scl_clear returns clear % per image
#
# iteration = "list"
#   - Each branch returns a list
#   - Results combined into list of lists
#   - Example: stac_json_list returns JSON per location
#
# iteration = "group"
#   - Used with tar_group() for custom grouping
#   - Each branch is one GROUP defined by group_by()
#   - Example: group_by(location, solarday) → one branch per unique combo
#
# tar_force(force = TRUE)
#   - Always rebuilds target, even if inputs unchanged
#   - Used for final outputs that need URL rewriting
#   - Not part of pattern system, but controls target behavior
#
# No pattern
#   - Target computed once (static)
#   - Uses ALL branches of dependencies automatically
#   - Example: markers reads results from all spatial_window branches

# ============================================================================
# BRANCHING FLOW DIAGRAM
# ============================================================================

# tabl (1) 
#   ↓ map (20 branches)
# spatial_window (20)
#   ↓ aggregate
# markers (1)
#   ↓
# query_specs (1)
#   ↓ map (20 branches)
# querytable (20)
#   ↓ map (20 branches)
# stac_json_list (20)
#   ↓ aggregate
# stac_json_table (1)
#   ↓ map (20 branches)
# stac_tables (20)
#   ↓ aggregate & filter
# stac_tables_new (1)
#   ↓ tar_group (100 branches = 20 locations × 5 days)
# images_table (100)
#   ↓ map (100 branches)
# scl_tifs (100)
#   ↓ map (100 branches)
# scl_clear (100)
#   ↓ aggregate & regroup (100 branches)
# group_table (100)
#   ↓ map (100 branches)
# dsn_table (100)
#   ↓ map (100 branches each)
# view_q128, view_histeq, view_stretch (100 each)
#   ↓ map (100 branches each)
# thumb_q128, thumb_histeq, thumb_stretch (100 each)
#   ↓ aggregate
# viewtableNA (1)
#   ↓
# viewtable (1)
#   ↓
# json (1)
#   ↓
# web (1)
#   ↓
# updated_markers (1)
#   ↓
# marker_status (1)

# Total maximum branches in pipeline:
# - spatial_window: 20
# - querytable/stac_json_list: 20
# - stac_tables: 20
# - images_table/scl/group_table/dsn_table: 100
# - views: 300 (3 types × 100)
# - thumbs: 300 (3 types × 100)
#
# Maximum parallelization: ~100 image processing tasks + 300 PNG/thumb tasks
# With 24 workers: processes in batches
