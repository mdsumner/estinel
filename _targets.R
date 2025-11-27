
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

## missing values
## the region we look at might be missing (it's off-swath, then clear_test will be NA because all NaN)
## there are some very few missing assets on element84

tar_assign(
  {
    bucket <- "estinel" |> tar_target()
    rootdir <- sprintf("/vsis3/%s", bucket) |> tar_target()
    #rootdir <- "/perm_storage/home/data/_targets_location_opts" |> tar_target()
    endpoint <- "https://projects.pawsey.org.au" |> tar_target()
    
    
    # 2025-11-18 02:06:44    1661036 sentinel-2-c1-l2a/2018/01/05/Hobart_2018-01-05.tif
    # 2025-11-18 02:06:44    1574875 sentinel-2-c1-l2a/2018/01/10/Hobart_2018-01-10.tif
    # 2025-11-18 02:06:45    1827288 sentinel-2-c1-l2a/2018/01/15/Hobart_2018-01-15.tif
    # 2025-11-21 04:18:28     512442 sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20.png
    # 2025-11-21 04:18:29       1852 sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20.png.aux.xml
    # 2025-11-18 02:06:46    1645541 sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20.tif
    # 2025-11-18 21:41:46       9803 sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20_scl.tif
    # 2025-11-18 02:06:48    1856319 sentinel-2-c1-l2a/2018/01/25/Hobart_2018-01-25.tif
    # 2025-11-18 02:06:49    1792761 sentinel-2-c1-l2a/2018/01/30/Hobart_2018-01-30.tif
    # 2025-11-20 00:30:38      14092 thumbs/sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20.png
    # 
    # 
    ## "sentinel-2-l2a",
    #provider <- #c("https://planetarycomputer.microsoft.com/api/stac/v1/search", 
    provider <- c("https://earth-search.aws.element84.com/v1/search") |> tar_target()
    collection <- c( "sentinel-2-c1-l2a") |> tar_target()
    tabl <-  define_locations_table() |> tar_target()
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
    view_q128 <- build_image_png(dsn_table, force = F, type = "q128") |> tar_target(pattern = map(dsn_table))
    view_histeq <- build_image_png(dsn_table, force = F, type = "histeq") |> tar_target(pattern = map(dsn_table))
    view_stretch <- build_image_png(dsn_table, force = F, type = "stretch") |> tar_target(pattern = map(dsn_table))
#      
    thumb_q128 <- build_thumb(view_q128, force = F) |> tar_target(pattern = map(view_q128)) 
    thumb_histeq <- build_thumb(view_histeq, force = F) |> tar_target(pattern = map(view_histeq )) 
    thumb_stretch <- build_thumb(view_stretch, force = F) |> tar_target(pattern = map(view_stretch)) 
    viewtableNA <- mutate(dsn_table, view_q128 = view_q128, view_histeq = view_histeq, view_stretch = view_stretch, 
                          thumb_q128 = thumb_q128, thumb_histeq = thumb_histeq, thumb_stretch = thumb_stretch) |>
      mutate(outfile = gsub("/vsis3", endpoint, outfile),
             view_q128 = gsub("/vsis3", endpoint, view_q128),
             view_histeq = gsub("/vsis3", endpoint, view_histeq),
             view_stretch = gsub("/vsis3", endpoint, view_stretch),
             scl_tif = gsub("/vsis3", endpoint, scl_tif),
             thumb_q128 = gsub("/vsis3", endpoint, thumb_q128), 
             thumb_histeq = gsub("/vsis3", endpoint, thumb_histeq), 
             thumb_stretch = gsub("/vsis3", endpoint, thumb_stretch)) |> tar_force(force = T)
    viewtable <- viewtableNA |>   dplyr::filter(!is.na(outfile), !is.na(view_q128)) |>
      tar_force(force = T)
    json <- write_react_json(viewtable) |> tar_force(force = T)
   web <- update_react(json, rootdir) |> tar_force(force = T)
    
 }
  )

