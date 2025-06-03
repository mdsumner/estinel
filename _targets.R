#pt <- cbind(86.53, -66.08); 

library(targets)
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
                    lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)))
localproj <- function(x) {
  sprintf("+proj=laea +lon_0=%f +lat_0=%f", x[1], x[2])
}
## build the extent
mkextent <- function(lon, lat, bufy = 3000, bufx = NULL) {
  pt <- cbind(lon, lat)
  if (is.null(bufx)) {
    cs <- 1/cos(pt[2] * pi / 180)
    bufx <- bufy * cs
  }
  c(-bufx, bufx, -bufy, bufy)
}
mk_crs <- function(lon, lat) {
  pt <- cbind(lon, lat)
  localproj(pt)
}
mk_ll_extent <- function(ex, crs) {
  llex <- reproj::reproj_extent(ex, "EPSG:4326", source = crs)
  llex
}
## get the available dates
getstac <- function(llex, date) {
  qu <- sds::stacit(llex, date)
  js <- try(jsonlite::fromJSON(qu))
  
  if (inherits(js, "try-error")) return(NA_character_)
  out <- tibble::as_tibble(lapply(js$features$assets, \(.x) .x$href))
  out$datetime <- js$features$properties$datetime
  out$llex <- replicate(nrow(out), llex, simplify = FALSE)
  list(assets = out, udates = sort(unique(as.Date(out$datetime))))
}

## build the image
build_cloud <- function(assets, bf, crs) {
  
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  
  cloud <- sprintf("/vsicurl/%s", assets$cloud)
  vapour::gdal_raster_data(cloud, target_crs= crs, target_res = 10, target_ext = c(-bf, bf, -bf, bf) * 2)
}

build_image <- function(assets, ex, crs, res) {
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  
  red <- sprintf("/vsicurl/%s", assets$red)
  green <- sprintf("/vsicurl/%s", assets$green)
  blue <- sprintf("/vsicurl/%s", assets$blue)
  
  rred <- vapour::gdal_raster_data(red, target_crs= crs, target_res = res, target_ext = ex)
  ggreen <- vapour::gdal_raster_data(green, target_crs= crs, target_res = res, target_ext = ex)
  bblue <- vapour::gdal_raster_data(blue, target_crs= crs, target_res = res, target_ext = ex)
  cbind(mtrx(rred), mtrx(ggreen), mtrx(bblue))
}
mtrx <- function(x) {
  as.vector(matrix(x[[1]], attr(x, "dimension")[2], byrow = TRUE))
}
list(
  tar_target(bufy, 3000),
  tar_target(daterange, c(as.Date("2022-01-01"), Sys.Date())),
  tar_target(lon, tabl$lon), tar_target(lat, tabl$lat),
  tar_target(extent, mkextent(lon, lat, bufy), pattern = map(lon, lat)), 
  tar_target(xmin, extent[1], pattern = map(extent)),
  tar_target(xmax, extent[2], pattern = map(extent)),
  tar_target(ymin, extent[3], pattern = map(extent)),
  tar_target(ymax, extent[4], pattern = map(extent)),
  
  tar_target(crs, mk_crs(lon, lat), pattern = map(lon, lat)),
  tar_target(llex, mk_ll_extent(extent, crs), pattern = map(extent, crs)),
  tar_target(stac_json, getstac(llex, daterange), pattern = map(llex)), 
  tar_target(udates, stac_json[seq(2, length(stac_json), by = 2)]),
  tar_target(assets, stac_json[seq(1, length(stac_json), by = 2)]),
  tar_target(cloud, build_cloud(assets, 500, crs), pattern = map(assets, crs)) 
#  tar_target(image, build_image(stac_json$red[1], stac_json$green[1], stac_json$blue[1], extent[1:4], crs[1], 10))
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
