#pt <- cbind(86.53, -66.08); 

library(targets)
library(tarchetypes)
library(crew)
tar_option_set(
  controller = crew_controller_local(workers = parallelly::availableCores())
)

library(reproj)
library(sds)
library(jsonlite)

# mksquash <- function(from = c(1000, 15000)) {
#   function(x) {
#   val <- scales::rescale(x, to = c(0, 1), from = from)
#   val <- x
#   val[val < 0] <- 0
#   val[val > 1] <- 1
#   val
#   }
# }
# # squash <- function(x) {
# #   val <- x
# #   val[val < 0] <- 0
# #   val[val > 1] <- 1
# #   val
# # }



tabl <- rbind(data.frame(location = "Davis", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600)), 
              data.frame(location = "Casey", 
                    lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)), 
              data.frame(location = "Heard", lon = 73 + 30/60 + 30/3600, lat = -(53 + 0 + 0/3600)),
              data.frame(location = "Mawson", lon = 62 + 52/60 + 27/3600, lat = -(67 + 36/60 + 12/3600)),
              data.frame(location = "Macquarie", lon = 158.93835, lat = -54.49871),
              readxl::read_excel("Emperor penguin colony locations_all_2024.xlsx", skip = 2) |> 
  dplyr::rename(location = colony, lon = long) |> dplyr::select(-date))

tabl <- tabl[3, ]

source("R/functions.R")
list(
  tar_target(bufy, 3000),
  tar_target(daterange, c(as.Date("2025-01-01"), Sys.Date())),
  tar_target(lon, tabl$lon), tar_target(lat, tabl$lat), tar_target(location, tabl$location),
  tar_target(extent, mkextent(lon, lat, bufy), pattern = map(lon, lat)), 
  tar_target(xmin, extent[1], pattern = map(extent)),
  tar_target(xmax, extent[2], pattern = map(extent)),
  tar_target(ymin, extent[3], pattern = map(extent)),
  tar_target(ymax, extent[4], pattern = map(extent)),
  
  tar_target(crs, mk_crs(lon, lat), pattern = map(lon, lat)),
  tar_target(llex, mk_ll_extent(c(xmin, xmax, ymin, ymax), crs), pattern = map(xmin, xmax, ymin, ymax, crs)),
  tar_target(stac_json, getstac(llex, daterange, location, crs), pattern = map(llex, location, crs)),
  tar_target(assets,  stac_json |> dplyr::arrange(location, datetime) |>   
               dplyr::group_by(location, solarday) |> tar_group(), iteration = "group")
  , tar_target(cloud, build_cloud(assets, 10, c(-1, 1, -1, 1) * 3000),  pattern = map(assets),  iteration = "list")
  , tar_target(cloud_filter, unlist(lapply(cloud, filter_fun), use.names = F))
  , tar_target(assets_to_image, assets |> dplyr::filter(tar_group %in% which(cloud_filter)), iteration = "group")
  , tar_target(assets_crs, assets_to_image |> dplyr::mutate(crs = purrr::map_chr(crs, gdalraster::srs_to_wkt)))
  , tar_target(image, build_image(assets_crs, 10, c(-3000, 3000, -3000, 3000)), pattern = map(assets_crs), iteration = "list")
)
  


  
  

# for (i in seq_len(length(udate))) {
# 
#   idx <- alldates == udate[i]
#   red <- sprintf("/vsicurl/%s", json$features$assets$red$href[idx])
#   green <- sprintf("/vsicurl/%s", json$features$assets$green$href[idx])
#   blue <- sprintf("/vsicurl/%s", json$features$assets$blue$href[idx])
#   cloud <- sprintf("/vsicurl/%s", json$features$assets$scl$href[idx])
#   
#   ccloud <- vapour::gdal_raster_data(cloud, target_crs= prj, target_res = 10, target_ext = c(-bf, bf, -bf, bf)*2)
#   if (!all(is.nan(ccloud[[1]])) && mean(ccloud[[1]] %in%  c(0, 1, 2, 3, 8, 9, 10)) < .4) {
#   rred <- vapour::gdal_raster_data(red, target_crs= prj, target_res = 10, target_ext = ex)
#   ggreen <- vapour::gdal_raster_data(green, target_crs= prj, target_res = 10, target_ext = ex)
#   bblue <- vapour::gdal_raster_data(blue, target_crs= prj, target_res = 10, target_ext = ex)
# mtrx <- function(x) {
#   as.vector(matrix(x[[1]], attr(x, "dimension")[2], byrow = TRUE))
# }
#   col0 <- cbind(mtrx(rred), mtrx(ggreen), mtrx(bblue))
#   squash <- mksquash(quantile(col0, c(0.2, .75)))
#   col <- squash(col0)
#   #col <- scales::rescale(col0)
#   dm <- attr(rred, "dimension")
#   label <- sprintf("%s: %s", location, format(as.Date(udate[i])))
#   #png(sprintf("%s.png", gsub(" ", "_", label)), width = 1024, height = 1024)
#   ximage::ximage(array(col, c(attr(rred, "dimension")[2:1], 3L)), ex, asp = 1)
#   title(label)
# 
#   rect(-bf, -bf, bf, bf, lty = 2, border = "hotpink", col = NA)
#   points(cbind(c(-bf, 0, bf, 0), c(0, -bf, 0, bf)), pch = "+")
#   #dev.off()
#   #maxar <- vapour::gdal_raster_nara(sds::wms_googlehybrid_tms(), target_crs= prj, target_res = .5, target_ext = c(-bf, bf, -bf, bf)*2)
#   #ximage::ximage(maxar)
#   }
# }
#     
# }
