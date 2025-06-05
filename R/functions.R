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
  if (inherits(js, "try-error")) return(data.frame())
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
build_cloud <- function(assets, res = 10) {
  tmpdir <- "/perm_storage/home/data/_targets_sentineltifs"
 # dir.create(tmpdir)
  tf <- tempfile(fileext = ".tif", tmpdir = tmpdir)
  set_gdal_envs()
  exnames <- c("xmin", "xmax", "ymin", "ymax")
  ## every group of rows has a single extent
  ex <- unlist(assets[1L, exnames], use.names = FALSE)
  cloud <- sprintf("/vsicurl/%s", assets$scl)
  vapour::gdal_raster_dsn(cloud, target_crs= assets$crs[1], target_res = res, target_ext = ex, out_dsn = tf)
}

warp_and_read <- function(dsn, target_ext = NULL, target_crs = NULL, target_res = NULL, target_dim = NULL) {
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
  x <- gdalraster::read_ds(new(gdalraster::GDALRaster, tf))
  x
}
build_image <- function(assets, res) {
  set_gdal_envs()
  crs <- assets$crs[1]
  
  exnames <- c("xmin", "xmax", "ymin", "ymax")
  ## every group of rows has a single extent
  ex <- unlist(assets[1L, exnames], use.names = FALSE)
  
  bands <- vector("list", 3)
  bandnames <- c("red", "green", "blue")
  ## didn't like use of gdalraster::srs_to_wkt here ??
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
read_dsn <- function(x) {
  ds <- new(gdalraster::GDALRaster, x)
  on.exit(ds$close(), add = TRUE)
  gdalraster::read_ds(ds)
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