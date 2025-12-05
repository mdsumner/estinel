build_image_dsn <- function(assets, resample = "near", rootdir = tempdir()) {
  res <- assets$resolution[1]
  root <- sprintf("%s/%s", rootdir, assets$collection[1])
  root <- sprintf("%s/%s", root, format(assets$solarday[1L], "%Y/%m/%d"))
  set_gdal_envs()
  location <- assets$location[1L]
  outfile <- sprintf("%s/%s_%s.tif", root, location, format(assets$solarday[1]))
  
  if (!dir.exists(root)) {
    if (!is_cloud(root)) {
      dir.create(root, showWarnings = FALSE, recursive = TRUE)
    }}
  
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
                          SITE_ID = assets$SITE_ID[1],
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

  test <- put_bytes_at(vrt, outfile)
  if (inherits(test, "try-error")) {
    print("put bytes at fail")
    return(out)
  }
  out$outfile <- outfile
  out
}

build_image_png <- function(x, force = FALSE, type) {
  test <- try({
  dsn <- x[["outfile"]]
  if (length(dsn) > 1) {
    print("bad")
    print(dsn)
  }
  set_gdal_envs()
  Sys.unsetenv("AWS_NO_SIGN_REQUEST")
  if (is.na(dsn)) return(NA_character_)
  #gsub("tif$", "png", dsn)
  outpng <- gsub("\\.tif$", sprintf("_%s.png", type),  dsn)
  if (gdalraster::vsi_stat(outpng, "exists")) {
    if (!force) {
      return(outpng)  ## silently ignore
    }
  }
  if (!fs::dir_exists(dirname(outpng))) {
    if (!is_cloud(outpng))  {
      fs::dir_create(dirname(outpng))
    }
  }
  # writeLines(c(dsn, outpng), "/perm_storage/home/mdsumner/Git/estinel/afile")
  r <- terra::rast(dsn, raw = TRUE)
  if (type == "q128") {
    r <- stretch_q128(r)
  }
  if (type == "histeq") {
    r <- stretch_histeq(r)
  }
  if (type == "stretch") {
    r <- terra::stretch(r)
  }
  terra::writeRaster(r, outpng, 
                     overwrite = TRUE, datatype = "INT1U", NAflag = NA)
})
  #gdalraster::translate(dsn, outpng, cl_arg = c("-of", "PNG", "-scale", "-ot", "Byte"))
  if (inherits(test, "try-error")) return(NA_character_)
  outpng
}

build_thumb <- function(dsn, force = FALSE) {
  test <- try({
  if (is.na(dsn)) {
    print("bad dsn!!")
    return(NA_character_)
  }
  outfile <- gsub("png$", "png", gsub("estinel/", "estinel/thumbs/", dsn))
  if (gdalraster::vsi_stat(outfile, "exists")) {
    if (!force) {
      return(outfile)
    }
  }
 # r <- terra::rast(dsn)
  ## bug #1973 don't use
  ##r2 <- terra::resample(r, terra::res(r) * 10)
  #r2 <- terra::rast(r * 1)
  #terra::res(r2) <- terra::res(r) * 8
  Sys.setenv(GDAL_PAM_ENABLED = "NO")
  on.exit(Sys.setenv(GDAL_PAM_ENABLED = "YES"), add = TRUE)
  trans <- gdalraster::translate(dsn, tf <- tempfile(fileext = ".png", tmpdir = "/vsimem"), cl_arg = c("-outsize", "12.5%", "12.5%"))
  con <- new(gdalraster::VSIFile, tf, "r")
  bytes <- con$ingest(-1)
  con$close()
  gdalraster::vsi_unlink(tf)
  con1 <- new(gdalraster::VSIFile, outfile, "w")
  con1$write(bytes)
  con1$close()
  #rm(bytes); gc()
  #invisible(NULL)
  
  #Sys.setenv(GDAL_PAM_ENABLED = "NO")
  #test <- try(terra::writeRaster(terra::project(r, r2), outfile, filetype = "PNG"))
  })
  if (inherits(test, "try-error")) return(NA_character_)
  outfile
  
}
build_scl_dsn <- function(assets, div = NULL, root = tempdir()) {
  set_gdal_envs()
  res <- assets$resolution[1]
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
define_locations_table <- function() {
  dplyr::bind_rows(
    ## first row is special, we include resolution and radiusx/y these are copied throughout if NA
    ## but other rows may have this value set also
    data.frame(location = "Hobart", lon = 147.3257, lat = -42.8826, resolution = 10, radiusx = 3000, radiusy=3000), 
    data.frame(location = "Dawson_Lampton_Ice_Tongue", lon  = -26.760, lat = -76.071),
    data.frame(location = "Davis_Station", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600)), 
    data.frame(location = "Casey_Station", lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)), 
    data.frame(location = "Casey_Station_2", lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600), radiusx = 5000, radiusy = 5000), 
    data.frame(location = "Heard_Island_Atlas_Cove", lon = 73.38681, lat = -53.024348),
    data.frame(location = "Heard_Island_Atlas_Cove_2", lon = 73.38681, lat = -53.024348, radiusx = 5000, radiusy = 5000),
    data.frame(location = "Heard_Island_60m", lon = 73.50281, lat= -53.09143, resolution = 60, radiusx = 24000, radiusy=14000),
    data.frame(location = "Heard_Island_Big_Ben", lon = 73.516667, lat = -53.1), 
    data.frame(location = "Heard_Island_Spit_Bay", lon = 73.71887, lat = -53.1141),
    data.frame(location = "Heard_Island_Spit_Bay_2", lon = 73.71887, lat = -53.1141, radiusx = 5000, radiusy = 5000),
    data.frame(location = "Heard_Island_Compton_Lagoon", lon = 73.610672, lat = -53.058079),
    
    data.frame(location = "Mawson_Station", lon = 62 + 52/60 + 27/3600, lat = -(67 + 36/60 + 12/3600)),
    data.frame(location = "Macquarie_Island_Station", lon = 158.93835, lat = -54.49871),
    data.frame(location = "Macquarie_Island_South", lon = 158.8252, lat = -54.7556),
    data.frame(location = "Scullin_Monolith", lon = 66.71886, lat = -67.79353), 
    data.frame(location = "Concordia_Station", lon = 123+19/60+56/3600, lat = -(75+05/60+59/3600) ), 
    data.frame(location = "Dome_C_North", lon = 122.52059, lat = -75.34132), 
    data.frame(location = "Bechervaise _Island", lon = 62.817, lat = -67.583)
    , cleanup_table() ) |>  fill_values()
}
fill_values <- function(x) {
  for (var in c("resolution", "radiusx", "radiusy")) {
    bad <- is.na(x[[var]])
    x[[var]][bad] <- x[[var]][1]  ## better not be NA
  }
  x$SITE_ID <- sprintf("site_%s", unlist(lapply(x$location, digest::digest, "murmur32")))
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
  x$query <- href
  x
}
## get the available dates
getstac_json <- function(x, trigger) {
  js <- try(jsonlite::fromJSON(x$query))
  if (inherits(js, "try-error") || (length(js$features) < 1) || (!is.null(js$numberReturned) &&js$numberReturned < 1)) {
    return(list())
  } else {
    return(js)
  }
  x
}

is_cloud <- function(x) {
  grepl("^/vsi", x)
}
join_stac_json <- function(querytable, stac_json_list) {
  bad <- !(lengths(stac_json_list) == 8)
  querytable <- dplyr::filter(querytable, !bad)
  querytable$js <- stac_json_list[!bad]
  querytable
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
mk_spatial_window <- function(x) {
  crslaea <- mk_crs(x$lon, x$lat)
  extentlaea <- mkextent(cbind(x$lon, x$lat), x$radiusy, x$radiusx, cosine = FALSE)
  x$crs <- mk_utm_crs(x$lon, x$lat)
  extent <- 
    vaster::buffer_extent(reproj::reproj_extent(extentlaea, x$crs, source = crslaea), x$resolution)
  ll_extent <- unproj(extent, source = x$crs)
  dplyr::mutate(x, lonmin = ll_extent[1L], lonmax = ll_extent[2L], latmin = ll_extent[3L], latmax = ll_extent[4L],
                 xmin = extent[1L], xmax = extent[2L], ymin = extent[3L], ymax = extent[4L])
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
  
#  bbox <- do.call(rbind, js$features$bbox)
#  return(hrefs)
  centroid <- lapply(js$features$bbox, function(bbox) c(mean(bbox[c(1, 3)]), mean(bbox[c(2, 4)])))
  centroid_lon <- js$features$properties$`proj:centroid`[,2] %||%  unlist(lapply(centroid, "[", 1))
  centroid_lat <- js$features$properties$`proj:centroid`[,1] %||% unlist(lapply(centroid, "[", 2))
  #hrefs$centroid_lon <- centroid_lon
  #hrefs$centroid_lat <- centroid_lat
  hrefs$solarday <- as.Date(round(hrefs$datetime - (centroid_lon/15 * 3600), "days"))
  # hrefs$location <- table$location
  # hrefs$xmin <- table$xmin
  # hrefs$xmax <- table$xmax
  # hrefs$ymin <- table$ymin
  # hrefs$ymax <- table$ymax
  # hrefs$crs <- table$crs
  # hrefs$collection <- table$collection
  # hrefs$provider <- table$provider
  # 
  table$assets <- list(hrefs)
  table
  #hrefs
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
  ds <- try(new(gdalraster::GDALRaster, x[[1]]))
  if (inherits(ds, "try-error")) {
    print("oops read_dsn error")
    return(NULL)
  }
  on.exit(ds$close(), add = TRUE)
  gdalraster::read_ds(ds)
}

set_gdal_envs <- function() {
  endpoint <- "https://projects.pawsey.org.au"
  # ## key/secret for GDAL and paws-r, REGION for paws-r, endpoint, vsil, virtual for GDAl
  Sys.setenv(
    AWS_ACCESS_KEY_ID = Sys.getenv("PAWSEY_AWS_ACCESS_KEY_ID"),
    AWS_SECRET_ACCESS_KEY = Sys.getenv("PAWSEY_AWS_SECRET_ACCESS_KEY"),
    AWS_REGION = "",
    AWS_S3_ENDPOINT = endpoint,
    CPL_VSIL_USE_TEMP_FILE_FOR_RANDOM_WRITE = "YES",
    AWS_VIRTUAL_HOSTING = "NO", 
    GDAL_HTTP_MAX_RETRY = "4",
    #GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR", 
    GDAL_HTTP_RETRY_DELAY = "10"
    #,AWS_NO_SIGN_REQUEST = "YES"
  )
  
}






unproj <- function(x, source) {
  reproj::reproj_extent(x, "EPSG:4326", source = source)
}
update_react <- function(pagejson, rootdir) {
  set_gdal_envs()

  con <- new(gdalraster::VSIFile, pagejson , "r")
  bytes <- con$ingest(-1)
  con$close()
  output <- sprintf("%s/catalog/%s", rootdir, basename(pagejson))
  con1 <- new(gdalraster::VSIFile, output, "w")
  con1$write(bytes)
  con1$close()
  TRUE
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

warp_to_dsn <- function(dsn, target_ext = NULL, target_crs = NULL, target_res = NULL, target_dim = NULL, resample = "near") {
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




