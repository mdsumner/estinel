nicebbox <- function(dat, min = .05, max = 1) {
  ex <- c(range(dat[,1, drop = TRUE]), range(dat[, 2, drop = TRUE]))
  dif <- diff(ex)[c(1, 3)]
  if (any(dif < min)) {
    f <- min
  }
  if (any(dif > max)) {
    f <- max
  }
  ## take the middle and give it the result
  cs <- 1/cos(mean(ex[3:4]) * pi/180)
  out <- rep(c(mean(ex[1:2]), mean(ex[3:4])), each = 2L) + c(-cs,cs, -1, 1) * f
  out
  
}

#' Plot raster at native resolution
#'
#' Determines the current device size and plots the raster centred on its own
#' middle to plot at native resolution. 
#'
#' https://www.hypertidy.org/posts/2024-12-04_plot_native/
#' @param x as SpatRaster
#' @param ... passed to plot.window
#'
#' @return the input raster, cropped corresponding to the plot made
#' @export

plot_native <- function(x, asp = 1, ..., dev_px = dev.size("px")) {
  ex <- attr(x, "gis")$bbox[c(1, 3, 2, 4)]
  dm <- attr(x, "gis")$dim[1:2]
  at <- NULL
  ## take the centre
  if (is.null(at)) {
    at <- apply(matrix(ex, 2), 2, mean)
  }
  dv <- dev_px
  scl <- diff(ex)[c(1, 3)] / dm
  halfx <- dv[1]/2 * scl[1]
  halfy <- dv[2]/2 * scl[2]
  cropex <- c(at[1] - halfx, at[1] + halfx, at[2] - halfy, at[2] + halfy)
  #x <- terra::crop(x, terra::ext(cropex), extend = TRUE)
  #add <- FALSE
  #if (terra::nlyr(x) >= 3) terra::plotRGB(x, add = add) else plot(x, ..., add = add)
  plot.new()
  plot.window(cropex[1:2], cropex[3:4], asp = asp, ...)
  ximage::ximage(x, add = TRUE)
  invisible(NULL)
}





set_gdal_envs <- function() {
  Sys.setenv("GDAL_HTTP_MAX_RETRY" = "4")
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  Sys.setenv("GDAL_HTTP_RETRY_DELAY" = "10")
  invisible(NULL)
}
## wh  ## from lonlat + radius
## duration (from the past to now)
# wh <- function(pt, r = 5000) {
#   mkextent(pt[1], pt[2], bufy = r, bufx = r)
# }
duration <- function(x = 3600 * 24 * 365.25) {
  Sys.time() + c(-x, 0)
}

stac_time <- function(x = 3600 * 24 * 365.25) {
  duration(x)
}

stac_date <- function(x = 365.25) {
  duration(x * 24 * 3600)
}
unproj <- function(x, source) {
  out <- x * NA_real_
  source <- rep(source, length.out = nrow(x))
  for (i in seq_len(nrow(x))) {
    out[i, ] <- reproj::reproj_extent(x[i, ], "EPSG:4326", source = source[i])
  }
  out
}
localproj <- function(x) {
  sprintf("+proj=laea +lon_0=%f +lat_0=%f", x[1], x[2])
}
## build the extent
mkextent <- function(lon, lat, bufy = 3000, bufx = NULL, cosine = FALSE) {
  pt <- cbind(lon, lat)
  bufy <- rep(bufy, length.out = nrow(pt))
  if (!is.null(bufx)) bufx <- rep(bufx, length.out = nrow(pt))
  if (cosine) {
    cs <- 1/cos(pt[,2L, drop = TRUE] * pi / 180)
    bufx <- bufy * cs
  } else {
    bufx <- bufy
  }
  cbind(-bufx, bufx, -bufy, bufy)
}
mkextent_crs <- function(lon, lat, bufy = 3000, bufx = 3000, crs) {
  ex <- mkextent(lon, lat, bufy, bufx)
  gdalraster::transform_bounds(ex[c(1, 3, 2, 4)], srs_to = "EPSG:4326", srs_from  = mk_crs(lon, lat))[c(1, 3, 2, 4)]
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
getstac_json <- function(x) {
  llnames <- c("lonmin", "lonmax", "latmin", "latmax")
  dtnames <- c("start", "end")
  llex <- unlist(x[llnames])
  date <- c(x[[dtnames[1]]], x[[dtnames[2]]])
  qu <- sds::stacit(llex, date, limit = 300)
  js <- try(jsonlite::fromJSON(qu))
  if (inherits(js, "try-error") || js$numberReturned < 1) return(data.frame())
 js 
}
 
# mkstac_table <- function(x) {
#   
#   ## x is a dataframe with each element for getstac
#   getstac_json(unlist(x[llnames]), c(x[[dtnames[1]]], x[[dtnames[2]]]))
# }

process_stac_table <- function(js, llex, location, crs, extent) {
  out <- tibble::as_tibble(lapply(js$features$assets, \(.x) .x$href))
  out$datetime <- as.POSIXct(strptime(js$features$properties$datetime, "%Y-%m-%dT%H:%M:%OSZ"), tz = "UTC")
  ## had to google my own notes for this ... https://github.com/mdsumner/tacky/issues/2
  out$centroid_lon <- js$features$properties$`proj:centroid`[,2]
  out$centroid_lat <- js$features$properties$`proj:centroid`[,1]
  
  out$solarday <- as.Date(round(out$datetime - (out$centroid_lon/15 * 3600), "days"))
  out$llxmin <- llex[1]
  out$llxmax <- llex[2]
  
  out$llymin <- llex[3]
  out$llymax <- llex[4]
  out$xmin <- extent[1]
  out$xmax <- extent[2]
  out$ymin <- extent[3]
  out$ymax <- extent[4]
  
  out$location <- location
  out$crs <- crs
  dplyr::arrange(out, location, datetime)
}



## build the image
build_cloud <- function(assets, res = 10, div = NULL) {
  out <- try({
  tmpdir <- tempdir()
  dir.create(tmpdir)
  tf <- tempfile(fileext = ".tif", tmpdir = tmpdir)
  set_gdal_envs()
  exnames <- c("xmin", "xmax", "ymin", "ymax")
  ## every group of rows has a single extent
  ex <- unlist(assets[1L, exnames], use.names = FALSE)
  if (!is.null(div))  {
    ## this only works for our crafted extents
    #ex <- ex/div
    dxdy <- diff(ex)[c(1, 3)]/div / 2
    middle <- c(mean(ex[1:2]), mean(ex[3:4]))
    ex <- c(middle[1] - dxdy[1], middle[1] + dxdy[1], middle[2] - dxdy[2], middle[2] + dxdy[2])
  }
  cloud <- sprintf("/vsicurl/%s", assets$scl)
  vapour::gdal_raster_dsn(cloud, target_crs= assets$crs[1], target_res = res, target_ext = ex, out_dsn = tf)
  })
  if (inherits(out, "try-error")) return(NULL)
  out
}

warp_to_dsn <- function(dsn, target_ext = NULL, target_crs = NULL, target_res = NULL, target_dim = NULL, resample = "near") {
  set_gdal_envs()
  dsn <- sprintf("/vsicurl/%s", dsn)
  args <- character()
  t_srs <- ""
  if (!is.null(target_crs)) {
    t_srs <- target_crs
  }
  if (!is.null(target_ext)) {
    
    args <- c(args, "-te", target_ext[c(1, 3, 2, 4)])
  }
  if (!is.null(target_res)) {
    target_res <- rep(target_res, length.out = 2L)
    
    args <- c(args, "-tr", target_res)
  }
  if (!is.null(target_dim)) {
    target_dim <- rep(target_dim, length.out = 2L)
    args <- c(args, "-ts", target_dim)
  }
  #t_srs <- gdalraster::srs_to_wkt(t_srs)
  chk <- gdalraster::warp(dsn, tf <- tempfile(fileext = ".tif", tmpdir = "/vsimem"), t_srs = t_srs, cl_arg = args, quiet = TRUE)
  #x <- gdalraster::read_ds(new(gdalraster::GDALRaster, tf))
  tf
}
build_image_dsn <- function(assets, res, resample = "near") {
  set_gdal_envs()
  crs <- assets$crs[1]
  
  exnames <- c("xmin", "xmax", "ymin", "ymax")
  ## every group of rows has a single extent
  ex <- unlist(assets[1L, exnames], use.names = FALSE)
  
  bands <- vector("list", 3)
  bandnames <- c("red", "green", "blue")
  ## didn't like use of gdalraster::srs_to_wkt here ??
  for (i in seq_along(bandnames)) {
    bands[[i]] <- warp_to_dsn(assets[[bandnames[i]]], target_crs = crs, target_res = res, target_ext = ex, resample = resample)
  }
  vrt <- vapour::buildvrt(unlist(bands))
  location <- assets$location[1L]
  outfile <- sprintf("/perm_storage/home/data/_targets_locationtifs/sentinel-2-c1-l2a/%s/%s_%s.tif", format(assets$solarday[1], "%Y/%m/%d"), location, format(assets$solarday[1]))
  fs::dir_create(dirname(outfile))
  gdalraster::translate(vrt, outfile, cl_arg = c("-co", "COMPRESS=DEFLATE", "-co", "TILED=NO"))
  
  ## when making this s3 we can drop the substitution
  # jsontext <- gsub("href\": \"idea-sentinel2-locations", "href\": \"https://projects.pawsey.org.au/idea-sentinel2-locations", json$dumps(stac$create_stac_item(outfile, date, collection = "idea-sentinel2-locations", with_proj = TRUE, with_raster = FALSE)$to_dict()))
  # jsonfile <- sprintf("%s-stac-item.json", outfile)
  # writeLines(jsontext, jsonfile)
  # 
  # 
  # outfile2 <- sprintf("/perm_storage/home/data/_targets_locationtifs/sentinel-2-c1-l2a/%s/%s_%s_stretch.tif", format(assets$solarday[1], "%Y/%m/%d"), location, format(assets$solarday[1]))
  # out2 <- terra::stretch(log(terra::rast(outfile)))
  # terra::writeRaster(out2, outfile2, datatype = "INT1U", gdal = c("COMPRESS=DEFLATE", "TILED=NO"), overwrite = TRUE)
  # 
  # date <- as.POSIXct(stringr::str_extract(basename(outfile2), "[0-9]{4}\\-[0-9]{2}\\-[0-9]{2}"), tz = "UTC")
  # jsontext <- gsub("href\": \"idea-sentinel2-locations", "href\": \"https://projects.pawsey.org.au/idea-sentinel2-locations", json$dumps(stac$create_stac_item(outfile2, date, collection = "idea-sentinel2-locations", with_proj = TRUE, with_raster = FALSE)$to_dict()))
  # jsonfile <- sprintf("%s-stac-item.json", outfile2)
  # writeLines(jsontext, jsonfile)
  # 

  
  outfile

}



# warp_and_read <- function(dsn, target_ext = NULL, target_crs = NULL, target_res = NULL, target_dim = NULL, resample = "near") {
#   set_gdal_envs()
#   dsn <- sprintf("/vsicurl/%s", dsn)
#   args <- character()
#   t_srs <- ""
#   if (!is.null(target_crs)) {
#     t_srs <- target_crs
#   }
#   if (!is.null(target_ext)) {
# 
#     args <- c(args, "-te", target_ext[c(1, 3, 2, 4)])
#   }
#   if (!is.null(target_res)) {
#     target_res <- rep(target_res, length.out = 2L)
#     
#     args <- c(args, "-tr", target_res)
#   }
#   if (!is.null(target_dim)) {
#     target_dim <- rep(target_dim, length.out = 2L)
#     args <- c(args, "-ts", target_dim)
#   }
#  #t_srs <- gdalraster::srs_to_wkt(t_srs)
#   chk <- gdalraster::warp(dsn, tf <- tempfile(fileext = ".tif", tmpdir = "/vsimem"), t_srs = t_srs, cl_arg = args, quiet = TRUE)
#   x <- gdalraster::read_ds(new(gdalraster::GDALRaster, tf))
#   x
# }
# build_image <- function(assets, res, resample = "near") {
#   set_gdal_envs()
#   crs <- assets$crs[1]
#   
#   exnames <- c("xmin", "xmax", "ymin", "ymax")
#   ## every group of rows has a single extent
#   ex <- unlist(assets[1L, exnames], use.names = FALSE)
#   
#   bands <- vector("list", 3)
#   bandnames <- c("red", "green", "blue")
#   ## didn't like use of gdalraster::srs_to_wkt here ??
#   for (i in seq_along(bandnames)) {
#     bands[[i]] <- warp_and_read(assets[[bandnames[i]]], target_crs = crs, target_res = res, target_ext = ex, resample = resample)
#   }
#   ## bit sneaky here to leverage plotraster "gis" idiom while also using dim, but ha sue me
#   #out <- do.call(cbind, lapply(bands, mtrx))
#   gis <- attr(bands[[1]], "gis")
#   
#   out <- unlist(bands, use.names = TRUE)
#   gis$dim <- c(gis$dim[1:2],length(bands))
#   gis$datatype <- rep(gis$datatype, length.out = length(bands))
#   attr(out, "gis") <- gis
#   out
# }
mtrx <- function(x) {
  as.vector(x)# matrix(x, attr(x, "gis")$dim[2L], byrow = TRUE))
}
read_dsn <- function(x) {
  if (is.null(x)) return(NULL)
  ds <- new(gdalraster::GDALRaster, x[[1]])
  on.exit(ds$close(), add = TRUE)
  gdalraster::read_ds(ds)
}
filter_fun <- function(.x) {
  if (is.null(.x)) return(FALSE)
  .x <- unlist(.x, use.names = F)
  if (all(is.na(.x))) return(FALSE)
  ## 0, 1, 2, 3, 
  mean(.x %in%  c(1, 3, 8, 9, 10), na.rm = TRUE) < .4
}
qm <- function(x, target_dim = c(1024, 0), target_crs = NULL, target_ext = NULL,target_res = NULL,..., scale = F, band_output_type = "raw") {
  dsn <- sprintf("/vsicurl/%s", x)
  if (scale) {
    dsn <- sprintf("vrt://%s?scale=true", dsn)
   # band_output_type <- "double"
    out <- vapour::gdal_raster_data(dsn, target_dim = target_dim, target_res = target_res, target_crs = target_crs, target_ext = target_ext)
    
  } else {
    out <- vapour::gdal_raster_nara(dsn, target_dim = target_dim, target_res = target_res, target_crs = target_crs, target_ext = target_ext, 
                                    band_output_type = band_output_type)
    
  }
  ximage::ximage(out, ...)
  invisible(out)
}