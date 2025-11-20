
# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)
pkgs <- c("tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", "targets", "dplyr", "glue", "digest")

tar_source()


# prefix <- "sentinel-2-c1-l2a"
#rootdir <- "/perm_storage/home/data/_targets_locationtifs"

set_gdal_envs()

ncpus <- 24
log_directory <- "_targets/logs"

tar_option_set(
  controller = if (ncpus <= 1) NULL else crew_controller_local(workers = ncpus
      ,options_local = crew_options_local(log_directory  = "log_directory")
      ),
  format = "qs",
  packages =pkgs
)

tar_assign(
  {
    bucket <- "estinel" |> tar_target()
    rootdir <- sprintf("/vsis3/%s", bucket) |> tar_target()
    endpoint <- "https://projects.pawsey.org.au" |> tar_target()
    
    ## "sentinel-2-l2a",
    #provider <- #c("https://planetarycomputer.microsoft.com/api/stac/v1/search", 
    provider <- c("https://earth-search.aws.element84.com/v1/search") |> tar_target()
    collection <- c( "sentinel-2-c1-l2a") |> tar_target()
    tabl <-  build_locations_table() |> tar_target()
    daterange <- format(as.POSIXct(c(as.POSIXct("2015-01-01 00:00:00", tz = "UTC"), Sys.time()))) |> tar_target()
    spatial_window <- mk_spatial_window(tabl) |> tar_target(pattern = map(tabl))
    qtable1 <- modify_qtable_yearly(spatial_window, daterange[1L], daterange[2L], provider, collection) |> tar_target()
    querytable <- getstac_query(qtable1) |> tar_target( pattern = map(qtable1))
    ## at this point the set reduces, because not every query has assets (we either return a list with json results, or a NULL so the dataframe collation blats them out)
    stac_json_list <- getstac_json(querytable) |> tar_target(pattern = map(querytable), iteration = "list")
    stac_json_table <- join_stac_json(querytable, stac_json_list) |> tar_target()
    stac_tables <- process_stac_table2(stac_json_table) |> 
      tar_target( pattern = map(stac_json_table))
    images_table <- tidyr::unnest(stac_tables |> dplyr::select(-js), cols = c(assets)) |> 
       dplyr::group_by(location, solarday, provider) |> 
       tar_group() |> tar_target( iteration = "group")
     scl_tifs <- build_scl_dsn(images_table,  root = rootdir) |> 
       tar_target( pattern = map(images_table))
    scl_clear <- filter_fun(read_dsn(scl_tifs)) |> tar_target(pattern = map(scl_tifs), iteration = "vector")
   # filter_table  <- images_table |> mutate(scl_tif = scl_tifs[tar_group], clear_test = scl_clear[tar_group])  |>  tar_target()
    group_table <- images_table |> mutate(scl_tif = scl_tifs[tar_group], clear_test = scl_clear[tar_group]) |> 
      make_group_table_providers(provider, collection) |>
        group_by(location, solarday, collection) |> tar_group() |>
        tar_target(iteration = "group")
    dsn_table <- build_image_dsn(group_table, rootdir = rootdir)  |> tar_target(pattern = map(group_table))
    pngs <- build_image_png(dsn_table$outfile) |> tar_target(pattern = map(dsn_table))
    thumbs <- build_thumb(pngs) |> tar_target(pattern = map(pngs)) 
    viewtable <- mutate(dsn_table, outpng = pngs, thumb = thumbs) |>
      mutate(outfile = gsub("/vsis3", endpoint, outfile),
             outpng = gsub("/vsis3", endpoint, outpng),
             scl_tif = gsub("/vsis3", endpoint, scl_tif), 
             thumb = gsub("/vsis3", endpoint, thumb)) |>
      dplyr::filter(!is.na(outfile), !is.na(outpng)) |> 
      tar_target()
}
  )

