
# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)
pkgs <- c("unjoin", "tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", "targets", "dplyr", "glue", "digest")

tar_source()


ncpus <- 24
tar_option_set(
  controller = if (ncpus <= 1) NULL else 
    crew_controller_local(workers = ncpus,
                          options_local = crew_options_local(log_directory  = "_targets/logs")),
  format = "qs",packages =pkgs, 
  error = "trim", 
  workspace_on_error = TRUE
)

tar_assign(
  {
    bucket <- "estinel" |> tar_target()
    rootdir <- sprintf("/vsis3/%s", bucket) |> tar_target()
    #rootdir <- "/perm_storage/home/data/_targets_location_opts" |> tar_target()
    endpoint <- "https://projects.pawsey.org.au" |> tar_target()
    
    provider <- c("https://earth-search.aws.element84.com/v1/search") |> tar_target()
    collection <- c( "sentinel-2-c1-l2a") |> tar_target()
    tabl <-  define_locations_table()[c(1:10), ] |> tar_target()
    daterange <- format(as.POSIXct(c(as.POSIXct("2015-12-15 00:00:00", tz = "UTC"), Sys.time()))) |> tar_target()
    spatial_window <- mk_spatial_window(tabl) |> tar_target(pattern = map(tabl))
    qtable1 <- modify_qtable_yearly(spatial_window, daterange[1L], daterange[2L], provider, collection) |> tar_target()
    querytable <- getstac_query(qtable1) |> tar_target( pattern = map(qtable1))
    # ## at this point the set reduces, because not every query has assets (we either return a list with json results, or a NULL so the dataframe collation blats them out)
    stac_json_list <- getstac_json(querytable) |> tar_target(pattern = map(querytable), iteration = "list")
    stac_json_table <- join_stac_json(querytable, stac_json_list) |> tar_target()
    stac_tables <- process_stac_table2(stac_json_table) |> tar_target( pattern = map(stac_json_table))
    images_table <- tidyr::unnest(stac_tables |> dplyr::select(-js), cols = c(assets)) |> 
      
      ## EXPLORE ME WE DROP NA tifs here
      dplyr::filter(!is.na(red)) |> 
       dplyr::group_by(location, solarday, provider) |> 
       tar_group() |> tar_target( iteration = "group")
    scl_tifs_markers <- build_scl_dsn(images_table,  root = rootdir) |> 
       tar_target( pattern = map(images_table), format = "file")
    scl_tifs <- get_s3_path(scl_tifs_markers) |> tar_target(pattern = map(scl_tifs_markers))
    scl_clear <- filter_fun(read_dsn(scl_tifs)) |> tar_target(pattern = map(scl_tifs), iteration = "vector")
    group_table <- images_table |> mutate(scl_tif = scl_tifs[tar_group], clear_test = scl_clear[tar_group]) |> 
       make_group_table_providers(provider, collection) |>
       group_by(location, solarday, collection) |> tar_group() |>
       tar_target(iteration = "group")
    
    ## ALL markers 
    dsn_file_markers <- build_image_dsn(group_table, rootdir = rootdir) |> tar_target(pattern = map(group_table), format = "file")
    # dsn_table <- build_image_dsn(group_table, rootdir = rootdir)  |> tar_target(pattern = map(group_table))
    #dsn_file <- get_s3_path(dsn_file_markers) |> tar_target(pattern = map(dsn_file_markers))
    view_q128 <- build_image_png(get_s3_path(dsn_file_markers), type = "q128") |> tar_target(pattern = map(dsn_file_markers))
    view_histeq <- build_image_png(get_s3_path(dsn_file_markers),  type = "histeq") |> tar_target(pattern = map(dsn_file_markers))
    view_stretch <- build_image_png(get_s3_path(dsn_file_markers), type = "stretch") |> tar_target(pattern = map(dsn_file_markers))
    thumb_q128 <- build_thumb(get_s3_path(view_q128)) |> tar_target(pattern = map(view_q128)) 
    thumb_histeq <- build_thumb(get_s3_path(view_histeq)) |> tar_target(pattern = map(view_histeq )) 
    thumb_stretch <- build_thumb(get_s3_path(view_stretch)) |> tar_target(pattern = map(view_stretch)) 
    
    dsn_table_two <- unjoin::unjoin(group_table, location, lon, lat, resolution, radiusx, radiusy, purpose, SITE_ID, crs, lonmin, lonmax, latmin, latmax, xmin, xmax, ymin, ymax, start, end, provider, collection, query, solarday,  scl_tif, clear_test) |> 
      tar_target()
    new_dsn <- lapply(list(outfile = dsn_file_markers, view_q128 = view_q128, view_histeq = view_histeq, view_stretch = view_stretch, 
                           thumb_q128 = thumb_q128, thumb_histeq = thumb_histeq, thumb_stretch = thumb_stretch), 
                      get_s3_path) |> tibble::as_tibble() |> 
      tar_target(pattern = map(dsn_file_markers, view_q128, view_histeq, view_stretch, thumb_q128, thumb_histeq, thumb_stretch))
    
    dsn_table <- bind_cols(new_dsn, 
                dsn_table_two[[1]] |> mutate(assets = split(dsn_table_two[[2]], dsn_table_two[[2]]$tar_group))) |> tar_target()
    
    viewtableNA <- dsn_table |>
      mutate(outfile = gsub("/vsis3", endpoint, outfile),
             view_q128 = gsub("/vsis3", endpoint, view_q128),
             view_histeq = gsub("/vsis3", endpoint, view_histeq),
             view_stretch = gsub("/vsis3", endpoint, view_stretch),
             scl_tif = gsub("/vsis3", endpoint, scl_tif),
             thumb_q128 = gsub("/vsis3", endpoint, thumb_q128),
             thumb_histeq = gsub("/vsis3", endpoint, thumb_histeq),
             thumb_stretch = gsub("/vsis3", endpoint, thumb_stretch)) |> tar_target()
    viewtable <- viewtableNA |>   dplyr::filter(!is.na(outfile), !is.na(view_q128)) |>
       tar_target()
    #json <- write_react_json(viewtable) |> tar_force(force = T)
    #web <- update_react(json, rootdir) |> tar_force(force = T)
    
  }
)

