
# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)
pkgs <- c("tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", "targets", "dplyr", "glue")

tar_source()

 bucket <- "estinel"
# prefix <- "sentinel-2-c1-l2a"
rootdir <- sprintf("/vsis3/%s", bucket)
#rootdir <- "/perm_storage/home/data/_targets_locationtifs"
 endpoint <- "https://projects.pawsey.org.au"
# ## key/secret for GDAL and paws-r, REGION for paws-r, endpoint, vsil, virtual for GDAl
Sys.setenv(
  GDAL_DISABLE_READDIR_ON_OPEN = "YES",
 AWS_ACCESS_KEY_ID = Sys.getenv("PAWSEY_AWS_ACCESS_KEY_ID"),
           AWS_SECRET_ACCESS_KEY = Sys.getenv("PAWSEY_AWS_SECRET_ACCESS_KEY"),
           AWS_REGION = "",
           AWS_S3_ENDPOINT = gsub("^https://", "", endpoint),
           CPL_VSIL_USE_TEMP_FILE_FOR_RANDOM_WRITE = "YES",
           AWS_VIRTUAL_HOSTING = "NO"
)


ncpus <- 12
#log_directory <- "_targets/logs"

tar_option_set(
  controller = if (ncpus <= 1) NULL else crew_controller_local(workers = ncpus
     # ,options_local = crew_options_local(log_directory  = "log_directory")
      ),
  format = "qs",
  packages =pkgs
)

tar_assign(
  {
    ## "sentinel-2-l2a",
    #provider <- #c("https://planetarycomputer.microsoft.com/api/stac/v1/search", 
    provider <- c("https://earth-search.aws.element84.com/v1/search") |> tar_target()
    collection <- c( "sentinel-2-c1-l2a") |> tar_target()
    tabl <-  bind_rows(
     ## first row is special, we include resolution and radiusx/y these are copied throughout if NA
     ## but other rows may have this value set also
     data.frame(location = "Hobart", lon = 147.3257, lat = -42.8826, resolution = 10, radiusx = 3000, radiusy=3000), 
     data.frame(location = "Dawson_Lampton_Ice_Tongue", lon  = -26.760, lat = -76.071),
     data.frame(location = "Davis_Station", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600)), 
     data.frame(location = "Casey_Station", lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)), 
     data.frame(location = "Heard_Island_Atlas_Cove", lon = 73.38681, lat = -53.024348),
     data.frame(location = "Mawson_Station", lon = 62 + 52/60 + 27/3600, lat = -(67 + 36/60 + 12/3600)),
     data.frame(location = "Macquarie_Island_Station", lon = 158.93835, lat = -54.49871),
     data.frame(location = "Scullin_Monolith", lon = 66.71886, lat = -67.79353), 
     data.frame(location = "Concordia_Station", lon = 123+19/60+56/3600, lat = -(75+05/60+59/3600) )
      , cleanup_table() ) |>  fill_values() |> tar_target()
    daterange <- format(as.POSIXct(c(as.POSIXct("2015-01-01 00:00:00", tz = "UTC"), Sys.time()))) |> tar_target()
    crslaea <- mk_crs(tabl$lon, tabl$lat) |> tar_target( pattern = map(tabl), iteration = "list")
    extentlaea <- mkextent(cbind(tabl$lon, tabl$lat), tabl$radiusy, tabl$radiusx, cosine = FALSE) |> tar_target(pattern = map(tabl), iteration = "list")
    crs <- mk_utm_crs(tabl$lon, tabl$lat) |> tar_target(pattern = map(tabl))
    resolution <- tabl$resolution |> tar_target()
    extent <- vaster::buffer_extent(reproj::reproj_extent(extentlaea, crs, source = crslaea), resolution) |> 
     tar_target(pattern = map(extentlaea, crs, crslaea, resolution), iteration = "list")
    ll_extent <- unproj(extent, source = crs) |> tar_target(pattern = map(extent, crs), iteration = "list")
    ## this table now has everything we've created so far
    qtable0 <-  dplyr::mutate(tabl, start = daterange[1], end = daterange[2],crs = crs,
                   lonmin = ll_extent[1L], lonmax = ll_extent[2L], latmin = ll_extent[3L], latmax = ll_extent[4L],
                   xmin = extent[1L], xmax = extent[2L], ymin = extent[3L], ymax = extent[4L]) |>
                tar_target(pattern = map(ll_extent, extent, crs, tabl))
    qtable1 <- modify_qtable_yearly(qtable0, daterange[1L], daterange[2L], provider, collection) |> tar_target()
    query_list <- getstac_query(qtable1) |> tar_target( pattern = map(qtable1), iteration = "list")
    query <- unname(unlist(query_list)) |> tar_target()
    stac_json0 <- getstac_json(query) |> tar_target(pattern = map(query), iteration = "list")
     bad <- (lengths(stac_json0) < 1) |> tar_target()
     qtable2 <- (qtable1[!bad, ]) |> tar_target()
     qtable <-  mutate(qtable2, js = stac_json0[!bad]) |> tar_target()
    stac_tables <- process_stac_table2(qtable) |> 
      tar_target( pattern = map(qtable), iteration = "list")
    images_table <- dplyr::bind_rows(stac_tables) |> 
      dplyr::group_by(location, solarday, provider) |> 
      tar_group() |> tar_target( iteration = "group")
    scl_tifs <- build_scl_dsn(images_table, res = resolution, root = rootdir) |> 
      tar_target( pattern = map(images_table))
    scl_filter <- filter_fun(read_dsn(scl_tifs)) |> tar_target(pattern = map(scl_tifs), iteration = "vector")
    filter_table  <- images_table |> mutate(scl_tif = scl_tifs[tar_group], clear_test = scl_filter[tar_group])  |>  tar_target()
    group_table <- filter_table |> make_group_table_providers(provider, collection) |>
        group_by(location, solarday, collection) |> tar_group() |>
        tar_target(iteration = "group")
    dsn_table <- build_image_dsn(group_table, res = resolution, rootdir = rootdir)  |> tar_target(pattern = map(group_table))
    pngs <- build_image_png(dsn_table$outfile) |> tar_target(pattern = map(dsn_table))
    viewtable <- mutate(dsn_table, outpng = pngs) |>
      mutate(outfile = gsub("/vsis3", endpoint, outfile),
             outpng = gsub("/vsis3", endpoint, outpng),
             scl_tif = gsub("/vsis3", endpoint, scl_tif)) |>
      tar_target()
}
  )

