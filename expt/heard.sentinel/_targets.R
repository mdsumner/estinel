library(targets)
library(tarchetypes)
library(crew)

# Set target options:
tar_option_set(
  packages = c("reproj", "sds", "jsonlite", "targets", "dplyr"), # Packages that your targets need for their tasks.
   format = "qs", # Optionally set the default storage format. qs is fast.
   controller = crew_controller_local(workers = 30)
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source("../../R/functions.R")
# tar_source("other_functions.R") # Source other scripts as needed.

mk_extent0 <- function(x) {
 x[c("xmin", "xmax", "ymin", "ymax")]
}

unproj0 <- function(x, crs) {
  unproj(unlist(x), crs)
}
list(
  #tar_target(radiusy, 3000), tar_target(radiusx, radiusy),
  #tar_target(daterange, stac_date(365)),
  #tar_target(lon, tabl$lon), tar_target(lat, tabl$lat), tar_target(location, tabl$location),
  #tar_target(crs, mk_crs(lon, lat), pattern = map(lon, lat), iteration = "vector"),

  ## note that mkextent and unproj are vectorized over matrix rows
 tar_target(gridtabl, arrow::read_parquet("heardcoast.parquet") |> group_by(tar_group = row_number()) |> tar_group()),
 tar_target(gridcrs, "EPSG:3031"), 
 tar_target(gridextent, c(gridtabl$xmin, gridtabl$xmax, gridtabl$ymin, gridtabl$ymax), pattern = map(gridtabl), iteration = "list"),
 tar_target(gridxcentre, mean(gridextent[1:2]), pattern = map(gridextent)), 
 tar_target(gridycentre, mean(gridextent[3:4]), pattern = map(gridextent)),
 tar_target(gridllxy, reproj::reproj_xy(cbind(gridxcentre, gridycentre), "EPSG:4326", source = gridcrs),
            pattern = map(gridxcentre, gridycentre), iteration = "list"),
 tar_target(gridlon, gridllxy[,1], pattern = map(gridllxy)),
 tar_target(gridlat, gridllxy[,2], pattern = map(gridllxy)),
 tar_target(ll_extent, 
            gdalraster::transform_bounds(gridextent[c(1, 3, 2, 4)], srs_to = "EPSG:4326", srs_from = gridcrs)[c(1, 3, 2, 4)], 
            pattern = map(gridextent), iteration = "list"),
 tar_target(daterange, format(as.POSIXct(c(as.POSIXct("2023-06-23 00:00:00", tz = "UTC"), Sys.time())))),

  #tar_target(ll_extent, mkextent_crs(loncentre, latcentre, bufy = 3000, bufx = 3000, crs), pattern = map(loncentre, latcentre), iteration = "list"),
 tar_target(lonmin, ll_extent[1], pattern = map(ll_extent)), tar_target(lonmax, ll_extent[2], pattern = map(ll_extent)),
 tar_target(latmin, ll_extent[3], pattern = map(ll_extent)), tar_target(latmax, ll_extent[4], pattern = map(ll_extent)),
  ## this table now has everything we've created so far
  tar_target(qtable,
              dplyr::mutate(gridtabl, start = daterange[1], end = daterange[2],
                            crs = gridcrs,
                   lonmin = lonmin, lonmax = lonmax, latmin = latmin, latmax = latmax) |>
                dplyr::mutate(tar_group = dplyr::row_number())),
   tar_target(stac_json, getstac_json(qtable), pattern = map(qtable)),
  tar_target(location, as.character(qtable$cell)),
 ## this is using a global crs from a grid, unlike the emperors which have a local laea
   tar_target(stac_tables, process_stac_table(stac_json, ll_extent, location, gridcrs, gridextent), pattern = map(stac_json, ll_extent, location,  gridextent), iteration = "list"),
   tar_target(images_table, dplyr::bind_rows(stac_tables) |> dplyr::group_by(location, solarday) |> tar_group(), iteration = "group"),
    tar_target(cloud_tifs, build_cloud(images_table, res = 10, div = 2), pattern = map(images_table),  iteration = "list"),
# #   ## [[1]] because output of read_dsn() is a list (each has its own attributes, which you can't do on atomic vector)
   tar_target(cloud_filter, filter_fun(read_dsn(cloud_tifs)), pattern = map(cloud_tifs), iteration = "vector"),
   tar_target(filter_table,
               images_table |> dplyr::filter(tar_group %in% which(cloud_filter)) |>
                 dplyr::group_by(location, solarday) |> tar_group(),
               iteration = "group"),
  tar_target(images, build_image_dsn(filter_table , res = 10), pattern = map(filter_table), iteration = "list")

)
