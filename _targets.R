# Created by use_targets().
# Follow the comments below to fill in this target script.
# Then follow the manual to check and run the pipeline:
#   https://books.ropensci.org/targets/walkthrough.html#inspect-the-pipeline

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(crew)

# Set target options:
tar_option_set(
  packages = c("reproj", "sds", "jsonlite", "targets"), # Packages that your targets need for their tasks.
   format = "qs", # Optionally set the default storage format. qs is fast.
   controller = crew_controller_local(workers = 30)
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()
# tar_source("other_functions.R") # Source other scripts as needed.



# Replace the target list below with your own:
list(
  tar_target(tabl, rbind(data.frame(location = "Davis", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600)), 
                                 data.frame(location = "Casey", 
                                            lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)), 
                                 data.frame(location = "Heard", lon = 73 + 30/60 + 30/3600, lat = -(53 + 0 + 0/3600)),
                                 data.frame(location = "Mawson", lon = 62 + 52/60 + 27/3600, lat = -(67 + 36/60 + 12/3600)),
                                 data.frame(location = "Macquarie", lon = 158.93835, lat = -54.49871),
                                 readxl::read_excel("Emperor penguin colony locations_all_2024.xlsx", skip = 2) |> 
                                   dplyr::rename(location = colony, lon = long) |> dplyr::select(-date))
  ),
  
  tar_target(radiusy, 3000), tar_target(radiusx, radiusy),
  tar_target(daterange, stac_date()),
  tar_target(lon, tabl$lon), tar_target(lat, tabl$lat), tar_target(location, tabl$location),
  tar_target(crs, mk_crs(lon, lat), pattern = map(lon, lat), iteration = "vector"),
  ## note that mkextent and unproj are vectorized over matrix rows
  tar_target(extent, mkextent(cbind(lon, lat), radiusy, radiusx, cosine = FALSE)),
  tar_target(ll_extent, unproj(extent, source = crs)),
  ## this table now has everything we've created so far
  tar_target(qtable, 
             dplyr::mutate(tabl, start = daterange[1], end = daterange[2], 
                           crs = crs,
                           xmin = extent[,1L], xmax = extent[,2L], ymin = extent[,3L], ymax = extent[,4L], 
                  lonmin = ll_extent[,1L], lonmax = ll_extent[,2L], latmin = ll_extent[,3L], latmax = ll_extent[,4L], 
                  xmin = extent[,1L], xmax = extent[,2L], ymin = extent[,3L], ymax = extent[,4L]) |> 
               dplyr::mutate(tar_group = dplyr::row_number())),
  tar_target(stac_json, getstac_json(qtable), pattern = map(qtable), iteration = "list"),
  tar_target(stac_tables, process_stac_table(stac_json, ll_extent, location, crs, extent), pattern = map(stac_json, ll_extent, location, crs, extent), iteration = "list"), 
  tar_target(images_table, dplyr::bind_rows(stac_tables) |> dplyr::group_by(location, solarday) |> tar_group(), iteration = "group"), 
  tar_target(images_table0, dplyr::filter(images_table, location == "Amundsen Bay") |> dplyr::group_by(location, solarday) |> tar_group(), iteration = "group")
,  tar_target(cloud_tifs, build_cloud(images_table0, res = 10), pattern = map(images_table0),  iteration = "list"),
  ## [[1]] because output of read_dsn() is a list (each has its own attributes, which you can't do on atomic vector)
tar_target(cloud_filter, filter_fun(read_dsn(cloud_tifs[[1]])), pattern = map(cloud_tifs), iteration = "vector")
, tar_target(filter_table, images_table0 |> dplyr::filter(tar_group %in% which(cloud_filter)) |> dplyr::group_by(location, solarday) |> tar_group(), iteration = "group")
,tar_target(images, build_image(images_table0 , res = 10), pattern = map(images_table0), iteration = "list")
)


if (FALSE) {
  tab <- cbind(1:20, scales::rescale(t(col2rgb(hcl.colors(20)))))
  xs <- 150
  ys <- 150
  tar_load(images)
  tar_load(cloud_tifs)
par(mfrow = c(12, 6), mar = rep(0, 4))
for (i in 1:24 ) {
gdalraster::plot_raster(images[[i]], xsize = xs, ysize = ys)
gdalraster::plot_raster(new(gdalraster::GDALRaster, cloud_tifs[[i]][[1]]), col_tbl = tab, xsize = xs, ysize = ys)

}

}

