
pl <- function(x) {
  if (missing(x)) x <- sample_n(viewtable, 1); 
  op <- par(mfrow = c(1, 2));
  plotRGB(rr <- rast(sprintf("/vsicurl/%s", x$outpng), raw = T)); 
  plotRGB(rr <- stretch_hist(rast(sprintf("/vsicurl/%s", x$outfile), raw = T))); 
  cl <- read.csv("inst/extdata/SCL_pal.csv")
  cl$col <- gsub("\t", "", cl$col)
  #r <- rast(gsub("/vsis3/", "/vsicurl/https://projects.pawsey.org.au/", x$scl_tif))
  #coltab(r) <- transmute(cl, value = val, col = col)
  
  #levels(r) <- rename(cl, ID = val, category = class)
  #plot(r, add = T)
  print(x$clear_test)
 # plot(density(values(rr)))
  par(op)
  x
}

cleanup_table <- function() {
  x <- readxl::read_excel("Emperor penguin colony locations_all_2024.xlsx", skip = 2) |> 
    dplyr::rename(location = colony, lon = long) |> dplyr::select(-date)
  stp <- unlist(gregexpr("[\\[\\(]", x$location)) -1
  stp[stp < 0] <- nchar(x$location[stp < 0])
  x$location <- substr(x$location, 1, stp)
  x$location <- trimws(x$location)
  x$location <- gsub("\\s+", "_", x$location, perl = TRUE)
  x$location <- gsub("é", "e", x$location)
  x
}

filter_the_table <- function(x, cfilter) {
  dplyr::filter(x, tar_group %in% which(cfilter)) |>
    dplyr::group_by(location, solarday)
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
  #out <- x * NA_real_
  #source <- rep(source, length.out = nrow(x))
  #for (i in seq_len(nrow(x))) {
  #  out[i, ] <- reproj::reproj_extent(x[i, ], "EPSG:4326", source = source[i])
  #}
  reproj::reproj_extent(x, "EPSG:4326", source = source)
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
  c(-bufx, bufx, -bufy, bufy)
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
mk_utm_crs <-function(lon, lat) {
  zone <- floor((lon + 180) / 6) + 1
  south <- lat < 0
  if (south) {
    lab <- " +south"
  } else {
    lab <- ""
  }
  gdalraster::srs_find_epsg(sprintf("+proj=utm +zone=%i%s +datum=WGS84", zone, lab))
}
make_group_table_providers <- function(x, provider, collection)   {
  stopifnot(length(provider) == length(collection))
  out <- vector("list", length(provider))
  for (i in seq_along(provider)) {
    xi <- x
    xi[["provider"]] <- provider[i]
    xi[["collection"]] <- collection[i]
    out[[i]] <- xi
  }
  do.call(rbind, out)
}

getstac_query <- function(x, limit = 300) {
  #stopifnot(length(provider) == length(collections))
  llnames <- c("lonmin", "lonmax", "latmin", "latmax")
  dtnames <- c("start", "end")
  llex <- unlist(x[llnames])
  date <- c(x[[dtnames[1]]], x[[dtnames[2]]])
 
  #href <- character(length(provider))
  #for (i in seq_along(href)) {
  href <- sds::stacit(llex, date, limit = limit, collections = x$collection[1L], provider = x$provider[1L])
  #}
  href
}
## get the available dates
getstac_json <- function(query) {
  
  js <- try(jsonlite::fromJSON(query))
  if (inherits(js, "try-error") || (length(js$features) < 1) || (!is.null(js$numberReturned) &&js$numberReturned < 1)) return(list())
 js 
}
 
# mkstac_table <- function(x) {
#   
#   ## x is a dataframe with each element for getstac
#   getstac_json(unlist(x[llnames]), c(x[[dtnames[1]]], x[[dtnames[2]]]))
# }

# process_stac_table <- function(js, llex, location, crs, extent) {
#   out <- tibble::as_tibble(lapply(js$features$assets, \(.x) .x$href))
#   out$datetime <- as.POSIXct(strptime(js$features$properties$datetime, "%Y-%m-%dT%H:%M:%OSZ"), tz = "UTC")
#   ## had to google my own notes for this ... https://github.com/mdsumner/tacky/issues/2
#   out$centroid_lon <- js$features$properties$`proj:centroid`[,2]
#   out$centroid_lat <- js$features$properties$`proj:centroid`[,1]
#   
#   out$solarday <- as.Date(round(out$datetime - (out$centroid_lon/15 * 3600), "days"))
#   out$llxmin <- llex[1]
#   out$llxmax <- llex[2]
#   
#   out$llymin <- llex[3]
#   out$llymax <- llex[4]
#   out$xmin <- extent[1]
#   out$xmax <- extent[2]
#   out$ymin <- extent[3]
#   out$ymax <- extent[4]
#   
#   out$location <- location
#   out$crs <- crs
#   outa <- try(dplyr::arrange(out, location, datetime) |> dplyr::filter(!is.na(red)))
#   if (inherits(outa, "try-error")) NULL else outa
# }

process_stac_table2 <- function(table) {
  js <- table[["js"]][[1]]
  hrefs <- tibble::as_tibble(lapply(js$features$assets, \(.x) .x$href))
  hrefs$datetime <- as.POSIXct(strptime(js$features$properties$datetime, "%Y-%m-%dT%H:%M:%OSZ"), tz = "UTC")
  ## had to google my own notes for this ... https://github.com/mdsumner/tacky/issues/2
  bbox <- do.call(rbind, js$features$bbox)
  centroid <- c(mean(bbox[, c(1, 3)]), mean(bbox[, c(2, 4)]))
  hrefs$centroid_lon <- js$features$properties$`proj:centroid`[,2] %||%  centroid[1]
  hrefs$centroid_lat <- js$features$properties$`proj:centroid`[,1] %||% centroid[2]
  
  hrefs$solarday <- as.Date(round(hrefs$datetime - (hrefs$centroid_lon/15 * 3600), "days"))
  hrefs$location <- table$location
  hrefs$xmin <- table$xmin
  hrefs$xmax <- table$xmax
  hrefs$ymin <- table$ymin
  hrefs$ymax <- table$ymax
  hrefs$crs <- table$crs
  hrefs$collection <- table$collection
  hrefs$provider <- table$provider
  hrefs
}

modify_qtable_yearly <- function(x, startdate, enddate = Sys.time(), provider, collection) {
  stopifnot(length(provider) == length(collection))

  year <- as.integer(format(as.Date(enddate), "%Y"))
  starts <- seq(as.Date(startdate), as.Date(sprintf("%i-01-01", year)), by = "1 year")
  ends <- seq(starts[2] -1, length.out = length(starts), by = "1 year")
  xx <- dplyr::bind_rows(lapply(split(x, 1:nrow(x)), function(.x) dplyr::slice(.x, rep(1, length(starts))) |> dplyr::mutate(start = starts, end = ends)))
  
  out <- vector("list", length(provider))
  for (i in seq_along(provider)) {
    xi <- xx
    xi[["provider"]] <- provider[i]
    xi[["collection"]] <- collection[i]
    out[[i]] <- xi
  }
  do.call(rbind, out)

}
stretch_hist <- function(x, ...) {
  ## stretch as if all the pixels were in the same band (not memory safe)
  rv <- terra::stretch(terra::rast(matrix(terra::values(x))), histeq = TRUE, maxcell = terra::ncell(x)*3)
  ## set the values to the input, then stretch to 0,255
  terra::stretch(terra::setValues(x, c(terra::values(rv))), histeq = FALSE, maxcell = terra::ncell(x))
}
vsicurl_for <- function(x, pc = FALSE) {
  if (pc) {
                             #pc_url_signing=yes
    out <- sprintf("/vsicurl?pc_url_signing=yes&url=%s",x)
} else {
  out <- sprintf("/vsicurl/%s", x)
}
  out
}
## build the image
build_scl_dsn <- function(assets, res = 10, div = NULL, root = tempdir()) {

  root <- sprintf("%s/%s/%s", root, assets$collection[1L], format(assets$solarday[1L], "%Y/%m/%d"))
  if (!dir.exists(root)) {
    if (!is_cloud(root)) {
      dir.create(root, showWarnings = FALSE, recursive = TRUE)
    }}
  
  location <- assets$location[1L]
  outfile <- sprintf("%s/%s_%s_scl.tif", root, location, format(assets$solarday[1]))
  
  outfile <- sprintf("%s/%s_%s.tif", root, location, format(assets$solarday[1]))
  if (gdalraster::vsi_stat(outfile, "exists")) {
    return(outfile)  ## silently ignore
  }
  set_gdal_envs()
  exnames <- c("xmin", "xmax", "ymin", "ymax")
  ## every group of rows has a single extent
  ex <- unlist(assets[1L, exnames], use.names = FALSE)
  # if (!is.null(div))  {
  #   dxdy <- diff(ex)[c(1, 3)]/div / 2
  #   middle <- c(mean(ex[1:2]), mean(ex[3:4]))
  #   ex <- c(middle[1] - dxdy[1], middle[1] + dxdy[1], middle[2] - dxdy[2], middle[2] + dxdy[2])
  # }
  scl <- assets[["scl"]] 
  if (is.na(scl)[1]) scl <- assets[["SCL"]]
 
  for (i in seq_along(scl)) scl[i] <- vsicurl_for(scl[i], pc = grepl("windows.net", scl[i]))

  out <- try(vapour::gdal_raster_dsn(scl, target_crs= assets$crs[1], target_res = res, target_ext = ex, out_dsn = outfile)[[1]], silent = TRUE)
  if (inherits(out, "try-error")) NA_character_ else out
}

warp_to_dsn <- function(dsn, target_ext = NULL, target_crs = NULL, target_res = NULL, target_dim = NULL, resample = "near") {
  set_gdal_envs()
  #dsn <- sprintf("/vsicurl/%s", dsn)
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
  chk <- try(gdalraster::warp(dsn, tf <- tempfile(fileext = ".tif"), t_srs = t_srs, cl_arg = args, quiet = TRUE), silent = TRUE)
  if (inherits(chk, "try-error")) return(NA_character_)
  #x <- gdalraster::read_ds(new(gdalraster::GDALRaster, tf))
  tf
}
put_bytes_at <- function(input, output) {
  tempv <- tempfile(fileext = ".tif", tmpdir = "/vsimem")
  test <- try( gdalraster::translate(input, tempv, 
                                     cl_arg = c( "-co", "COMPRESS=DEFLATE", "-co", "TILED=NO")), silent = T)
  
  con <- new(gdalraster::VSIFile, tempv, "r")
  bytes <- con$ingest(-1)
  con$close()
  gdalraster::vsi_unlink(tempv)
  con1 <- new(gdalraster::VSIFile, output, "w")
  con1$write(bytes)
  con1$close()
  rm(bytes); gc()
  invisible(NULL)
}
build_image_dsn <- function(assets, res, resample = "near", rootdir = tempdir()) {
  root <- sprintf("%s/%s", rootdir, assets$collection[1])
  root <- sprintf("%s/%s", root, format(assets$solarday[1L], "%Y/%m/%d"))
  
  location <- assets$location[1L]
  outfile <- sprintf("%s/%s_%s.tif", root, location, format(assets$solarday[1]))
 
  if (!dir.exists(root)) {
    if (!is_cloud(root)) {
      dir.create(root, showWarnings = FALSE, recursive = TRUE)
    }}
  
  set_gdal_envs()
  crs <- assets$crs[1]
  
  exnames <- c("xmin", "xmax", "ymin", "ymax")
  ## every group of rows has a single extent
  ex <- unlist(assets[1L, exnames], use.names = FALSE)
  
  bands <- vector("list", 3)
  bandnames <- c("red", "green", "blue")
  if (grepl("windows.net", assets[[1]][1L])) {
    bandnames <- c("B04", "B03", "B02")
    
  }
  out <-   tibble::tibble(outfile = NA_character_, location = assets$location[1], 
                          clear_test = assets$clear_test[1], 
                          solarday = assets$solarday[1],
                          scl_tif = assets$scl_tif[1], assets = list(assets))
  
  if (gdalraster::vsi_stat(outfile, "exists")) {
    out$outfile <- outfile
    return(out)  ## silently ignore
  }
  #print(out$solarday)
  #print(out$location)
  ## didn't like use of gdalraster::srs_to_wkt here ??
  for (i in seq_along(bandnames)) {

    dsns <- assets[[bandnames[i]]]
    dsns <- dsns[!is.na(dsns)]
    if (length(dsns) < 1) return(out)
    
    for (ii in seq_along(dsns)) dsns[ii] <- vsicurl_for(dsns[ii], pc = grepl("windows.net", dsns[ii]))
    tst <- try(warp_to_dsn(dsns, target_crs = crs, target_res = res, target_ext = ex, resample = resample)[[1]], silent = TRUE)
    if (inherits(tst, "try-error")) return(out)
    bands[[i]] <- tst
  }

  vrt <- try(vapour::buildvrt(unlist(bands)), silent = TRUE)
  if (inherits(vrt, "try-error")) return(out)
  
  # print(outfile)
   if (!is_cloud(root)) {
      if (!fs::dir_exists(root)) dir.create(root, showWarnings = FALSE, recursive = TRUE)
   }
   

  test <- put_bytes_at(vrt, outfile)
  if (inherits(test, "try-error")) return(out)
  out$outfile <- outfile
  out
}
is_cloud <- function(x) {
  grepl("^/vsi", x)
}
# midex <- function(x) {
#   c(mean(x[1:2]), mean(x[3:4]))
# }
# widex <- function(x) {
#   diff(x)[c(1, 3)]
# }
build_image_png <- function(dsn) {
  if (is.na(dsn)) return(NA_character_)
  outpng <- gsub("tif$", "png", dsn)
  if (gdalraster::vsi_stat(outpng, "exists")) {
    return(outpng)  ## silently ignore
  }
  if (!fs::dir_exists(dirname(outpng))) {
    if (!is_cloud(outpng))  {
      fs::dir_create(dirname(outpng))
    }
  }
 # writeLines(c(dsn, outpng), "/perm_storage/home/mdsumner/Git/estinel/afile")
  test1 <- try(r <- terra::rast(dsn, raw = TRUE), silent = TRUE)
  if (inherits(test1, "try-error")) return(NA_character_)
  test <- try(terra::writeRaster(stretch_hist(r), outpng, overwrite = TRUE, datatype = "INT1U"), silent = TRUE)
  #gdalraster::translate(dsn, outpng, cl_arg = c("-of", "PNG", "-scale", "-ot", "Byte"))
  if (inherits(test, "try-error")) return(NA_character_)
  outpng
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
  if (is.null(x) || is.na(x)) return(NULL)
  ds <- new(gdalraster::GDALRaster, x[[1]])
  on.exit(ds$close(), add = TRUE)
  gdalraster::read_ds(ds)
}
filter_fun <- function(.x) {
  if (is.null(.x)) return(NA_real_)
  .x <- unlist(.x, use.names = F)
  if (all(is.na(.x))) return(NA_real_)
  ## 0, 1, 2, 3, 
  mean(.x %in%  c(1, 3, 8, 9, 10), na.rm = TRUE) 
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


# nicebbox <- function(dat, min = .05, max = 1) {
#   ex <- c(range(dat[,1, drop = TRUE]), range(dat[, 2, drop = TRUE]))
#   dif <- diff(ex)[c(1, 3)]
#   if (any(dif < min)) {
#     f <- min
#   }
#   if (any(dif > max)) {
#     f <- max
#   }
#   ## take the middle and give it the result
#   cs <- 1/cos(mean(ex[3:4]) * pi/180)
#   out <- rep(c(mean(ex[1:2]), mean(ex[3:4])), each = 2L) + c(-cs,cs, -1, 1) * f
#   out
#   
# }
