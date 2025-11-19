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

build_scl_dsn <- function(assets, res = 10, div = NULL, root = tempdir()) {
  
  root <- sprintf("%s/%s/%s", root, assets$collection[1L], format(assets$solarday[1L], "%Y/%m/%d"))
  if (!dir.exists(root)) {
    if (!is_cloud(root)) {
      dir.create(root, showWarnings = FALSE, recursive = TRUE)
    }}
  
  location <- assets$location[1L]
  outfile <- sprintf("%s/%s_%s_scl.tif", root, location, format(assets$solarday[1]))
  
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

fill_values <- function(x) {
  for (var in c("resolution", "radiusx", "radiusy")) {
    bad <- is.na(x[[var]])
    x[[var]][bad] <- x[[var]][1]  ## better not be NA
  }
  x
}
filter_fun <- function(.x) {
  if (is.null(.x)) return(NA_real_)
  .x <- unlist(.x, use.names = F)
  if (all(is.na(.x))) return(NA_real_)
  ## 0, 1, 2, 3, 
  mean(.x %in%  c(1, 3, 8, 9, 10), na.rm = TRUE) 
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

is_cloud <- function(x) {
  grepl("^/vsi", x)
}

localproj <- function(x) {
  sprintf("+proj=laea +lon_0=%f +lat_0=%f", x[1], x[2])
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

mk_crs <- function(lon, lat) {
  pt <- cbind(lon, lat)
  localproj(pt)
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

read_dsn <- function(x) {
  if (is.null(x) || is.na(x)) return(NULL)
  ds <- new(gdalraster::GDALRaster, x[[1]])
  on.exit(ds$close(), add = TRUE)
  gdalraster::read_ds(ds)
}



  
set_gdal_envs <- function() {
  Sys.setenv("GDAL_HTTP_MAX_RETRY" = "4")
  Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")
  Sys.setenv("GDAL_HTTP_RETRY_DELAY" = "10")
  invisible(NULL)
}





unproj <- function(x, source) {
  reproj::reproj_extent(x, "EPSG:4326", source = source)
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




