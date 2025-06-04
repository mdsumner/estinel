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
getstac <- function(llex, date, location, crs) {
  qu <- sds::stacit(llex, date)
  js <- try(jsonlite::fromJSON(qu))
  
  if (inherits(js, "try-error")) return(data.frame())
  out <- tibble::as_tibble(lapply(js$features$assets, \(.x) .x$href))
  out$datetime <- as.POSIXct(strptime(js$features$properties$datetime, "%Y-%m-%dT%H:%M:%OSZ"), tz = "UTC")
  
  out$localnoon <- js$features$properties$`proj:centroid`[,1L, drop = TRUE] / 15
  out$llxmin <- llex[1]
  out$llxmax <- llex[2]
  
  out$llymin <- llex[3]
  out$llymax <- llex[4]
  out$location <- location
  out$crs <- crs
  dplyr::arrange(out, location, datetime)
}

## build the image
build_cloud <- function(assets, res, ex) {
  
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  
  cloud <- sprintf("/vsicurl/%s", assets$cloud)
  vapour::gdal_raster_data(cloud, target_crs= assets$crs[1], target_res = res, target_ext = ex)
}

warp_and_read <- function(dsn, target_ext = NULL, target_crs = NULL, target_res = NULL, target_dim = NULL) {
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  
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
 
  chk <- gdalraster::warp(dsn, tf <- tempfile(fileext = ".tif", tmpdir = "/vsimem"), t_srs = t_srs, cl_arg = args, quiet = TRUE)
  x <- gdalraster::read_ds(new(gdalraster::GDALRaster, tf))
  x
}
build_image <- function(assets, res, ex) {
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  
  crs <- assets$crs[1]
  bands <- vector("list", 3)
  bandnames <- c("red", "green", "blue")
  for (i in seq_along(bandnames)) {
    bands[[i]] <- warp_and_read(assets[[bandnames[i]]], target_crs = crs, target_res = res, target_ext = ex)
  }
  ## bit sneaky here to leverage plotraster "gis" idiom while also using dim, but ha sue me
  out <- do.call(cbind, lapply(bands, mtrx))
  gis <- attr(bands[[1]], "gis")
  gis$dim <- c(gis$dim[1:2], ncol(out))
  gis$datatype <- rep(gis$datatype, length.out = ncol(out))
  attr(out, "gis") <- gis
  out
}
mtrx <- function(x) {
  as.vector(matrix(x, attr(x, "gis")$dim[2L], byrow = TRUE))
}
filter_fun <- function(.x) {
  .x <- unlist(.x, use.names = F)
  if (all(is.na(.x))) return(TRUE)
  mean(.x %in%  c(0, 1, 2, 3, 8, 9, 10), na.rm = TRUE) > .4
}
qm <- function(x, target_dim = c(1024, 0), target_crs = NULL, target_ext = NULL,target_res = NULL,...) {
  out <- vapour::gdal_raster_nara(sprintf("/vsicurl/%s", x), target_dim = target_dim, target_res = target_res, target_crs = target_crs, target_ext = target_ext)
  ximage::ximage(out, ...)
  invisible(out)
}