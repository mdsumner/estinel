
# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)
pkgs <- c("tarchetypes", "crew", "reproj", "sds", "jsonlite", "vapour", "targets", "dplyr")

tar_source()

bucket <- "geotar0"
prefix <- "_targets-geotar"
rootdir <- sprintf("/vsis3/%s/%s", bucket, prefix)
#rootdir <- "/perm_storage/home/data/_targets_locationtifs/sentinel-2-c1-l2a"
endpoint <- "https://projects.pawsey.org.au"
## key/secret for GDAL and paws-r, REGION for paws-r, endpoint, vsil, virtual for GDAl
Sys.setenv(AWS_ACCESS_KEY_ID = Sys.getenv("PAWSEY_AWS_ACCESS_KEY_ID"),
           AWS_SECRET_ACCESS_KEY = Sys.getenv("PAWSEY_AWS_SECRET_ACCESS_KEY"),
           AWS_REGION = "",
           AWS_S3_ENDPOINT = gsub("^https://", "", endpoint),
           CPL_VSIL_USE_TEMP_FILE_FOR_RANDOM_WRITE = "YES",
           AWS_VIRTUAL_HOSTING = "NO")


ncpus <- 28
#log_directory <- "_targets/logs"
# Set target options:
laws <- list(repository = "aws",
             resources = tar_resources(
               aws = tar_resources_aws(
                 bucket = bucket,prefix = prefix,
                 endpoint = endpoint
                 
               )
             ))

tar_option_set(
  controller = if (ncpus <= 1) NULL else crew_controller_local(workers = ncpus),
  format = "qs",
  packages =pkgs
)


tar_assign(
  {
  tabl <-  rbind(
    data.frame(location = "Davis", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600)), 
                                 data.frame(location = "Casey", 
                                           lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)), 
                                 data.frame(location = "Heard", lon = 73 + 30/60 + 30/3600, lat = -(53 + 0 + 0/3600)),
                                 data.frame(location = "Mawson", lon = 62 + 52/60 + 27/3600, lat = -(67 + 36/60 + 12/3600)),
                                 data.frame(location = "Macquarie", lon = 158.93835, lat = -54.49871)
                                , cleanup_table() 
  ) |> tar_target()
  
  radiusy <- 3000 |> tar_target()
  radiusx <- radiusy |> tar_target()
  daterange <- format(as.POSIXct(c(as.POSIXct("2015-06-23 00:00:00", tz = "UTC"), Sys.time()))) |> tar_target()
  lon <- tabl$lon |> tar_target()
  lat <- tabl$lat |> tar_target() 
  location <- tabl$location |> tar_target()
  crs <- mk_crs(lon, lat) |> tar_target( pattern = map(lon, lat), iteration = "vector")
  ## note that mkextent and unproj are vectorized over matrix rows
  extent <- mkextent(cbind(lon, lat), radiusy, radiusx, cosine = FALSE) |> tar_target()
  ll_extent <- unproj(extent, source = crs) |> tar_target()
  ## this table now has everything we've created so far
  qtable <-  dplyr::mutate(tabl, start = daterange[1], end = daterange[2], 
                           crs = crs,
                           xmin = extent[,1L], xmax = extent[,2L], ymin = extent[,3L], ymax = extent[,4L], 
                  lonmin = ll_extent[,1L], lonmax = ll_extent[,2L], latmin = ll_extent[,3L], latmax = ll_extent[,4L], 
                  xmin = extent[,1L], xmax = extent[,2L], ymin = extent[,3L], ymax = extent[,4L]) |> tar_target()
  
  stac_json <- getstac_json(qtable) |> tar_target( pattern = map(qtable), iteration = "list")
  stac_tables <- process_stac_table(stac_json, ll_extent, location, crs, extent) |> tar_target( pattern = map(stac_json, ll_extent, location, crs, extent), iteration = "list")
  
  images_table <- dplyr::bind_rows(stac_tables) |> dplyr::group_by(location, solarday) |> tar_group() |> tar_target( iteration = "group")
  cloud_tifs <- build_cloud(images_table, res = 10, div = 2) |> tar_target( pattern = map(images_table))

  cloud_filter <- filter_fun(read_dsn(cloud_tifs)) |> tar_target(pattern = map(cloud_tifs), iteration = "vector")
  
  filter_table  <- images_table |> mutate(clear_test = cloud_filter[tar_group])  |>  tar_target()
  group_table <- filter_table |> 
    group_by(location, solarday) |> tar_group() |> 
    tar_target(iteration = "group")
  dsn_table <- build_image_dsn(group_table, res = 10, 
                                        root = rootdir)  |> tar_target(pattern = map(group_table))
  
  pngs <- build_image_png(dsn_table$outfile) |> tar_target(pattern = map(dsn_table))
 scenes <- mutate(dsn_table, outpng = pngs) |> tar_target()
  viewtable <- mutate(scenes, outfile = gsub("/vsis3", endpoint, outfile), outpng = gsub("/vsis3", endpoint, outpng)) |> tar_target()
}
  )

