
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

check_table <- function(x) {
  if (any(is.na(x))) warning("locations table contains NAs")
  bad <- apply(is.na(x), 1, any)
  
  x <- x[!bad, ]
  if (nrow(x) < 1) stop("no valid location rows (are there NAs?)")
  x
}

cleanup_table <- function() {
  x <- readxl::read_excel("Emperor penguin colony locations_all_2024.xlsx", skip = 2) |> 
    dplyr::rename(location = colony, lon = long) |> dplyr::select(-date)
  x <- dplyr::filter(x, !grepl("Pointe", location))
  
  x2 <- readxl::read_excel("Emperor colonies_2022.xlsx") |> dplyr::transmute(location = Colony, lon = Long, lat = Lat)
  keep <- which(!gsub("_", " ", x$location) %in% x2$location)
  x <- rbind(x2, x[keep, ])
  stp <- unlist(gregexpr("[\\[\\(]", x$location)) -1
  stp[stp < 0] <- nchar(x$location[stp < 0])
  x$location <- substr(x$location, 1, stp)
  x$location <- trimws(x$location)
  x$location <- gsub("\\s+", "_", x$location, perl = TRUE)
  x$location <- gsub("é", "e", x$location)
  x$purpose <- as.list(rep("emperor", nrow(x)))
  x
}

define_locations_table <- function() {
  dplyr::bind_rows(
    ## first row is special, we include resolution and radiusx/y these are copied throughout if NA
    ## but other rows may have this value set also
    tibble::tibble(location = "Hobart", lon = 147.3257, lat = -42.8826, resolution = 10, radiusx = 3000, radiusy=3000), 
    tibble::tibble(location = "Davis_Station", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600), purpose = list(c("base"))), 
    tibble::tibble(location = "Casey_Station", lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600), purpose = list(c("base"))), 
    tibble::tibble(location = "Casey_Station_2", lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600), radiusx = 5000, radiusy = 5000, purpose = list(c("base"))), 
    tibble::tibble(location = "Heard_Island_Atlas_Cove", lon = 73.38681, lat = -53.024348, purpose = list(c("base", "heard"))),
    tibble::tibble(location = "Heard_Island_Atlas_Cove_2", lon = 73.38681, lat = -53.024348, radiusx = 5000, radiusy = 5000, purpose = list(c("base", "heard"))),
    tibble::tibble(location = "Heard_Island_60m", lon = 73.50281, lat= -53.09143, resolution = 60, radiusx = 24000, radiusy=14000, purpose = list(c("heard"))),
    tibble::tibble(location = "Heard_Island_Big_Ben", lon = 73.516667, lat = -53.1, purpose = list(c("heard"))), 
    tibble::tibble(location = "Heard_Island_Spit_Bay", lon = 73.71887, lat = -53.1141, purpose = list(c("heard"))),
    tibble::tibble(location = "Heard_Island_Spit_Bay_2", lon = 73.71887, lat = -53.1141, radiusx = 5000, radiusy = 5000, purpose = list(c("heard"))),
    tibble::tibble(location = "Heard_Island_Compton_Lagoon", lon = 73.610672, lat = -53.058079, purpose = list(c("heard"))),
    
    tibble::tibble(location = "Mawson_Station", lon = 62 + 52/60 + 27/3600, lat = -(67 + 36/60 + 12/3600), purpose = list(c("base"))),
    tibble::tibble(location = "Macquarie_Island_Station", lon = 158.93835, lat = -54.49871, purpose = list(c("base"))),
    tibble::tibble(location = "Macquarie_Island_South", lon = 158.8252, lat = -54.7556, purpose = list(c("macquarie"))),
    tibble::tibble(location = "Scullin_Monolith", lon = 66.71886, lat = -67.79353), 
    tibble::tibble(location = "Concordia_Station", lon = 123+19/60+56/3600, lat = -(75+05/60+59/3600) ), 
    tibble::tibble(location = "Dome_C_North", lon = 122.52059, lat = -75.34132, purpose = list(c("base"))), 
    tibble::tibble(location = "Bechervaise_Island", lon = 62.817, lat = -67.583, purpose = list(c("adelie"))),
    tibble::tibble(location = "Cape_Denison", lon = 142.6630347, lat = -67.0085726, purpose = list(c("adelie"))), 
    tibble::tibble(location = "Glen_Lusk", lon = 147.19475644052184, lat = -42.81829130353533),
    tibble::tibble(location = "Fern Tree", lon = 147.260093482072, lat = -42.922335920324294)
    , cleanup_table() ) |>  fill_values() |> check_table()
}

fill_values <- function(x) {
  for (var in c("resolution", "radiusx", "radiusy")) {
    bad <- is.na(x[[var]])
    x[[var]][bad] <- x[[var]][1]  ## better not be NA
  }
  badpurpose <- is.na(x[["purpose"]])
  if (any(is.na(badpurpose))) x[["purpose"]][bad] <- "none"
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

filter_new_solardays <- function(stac_table) {
  if (!"start_solarday" %in% names(stac_table)) {
    return(stac_table)
  }
  
  for (i in seq_len(nrow(stac_table))) {
    if (!is.na(stac_table$start_solarday[i])) {
      assets <- stac_table$assets[[i]]
      if (nrow(assets) > 0 && "solarday" %in% names(assets)) {
        assets <- assets[assets$solarday > stac_table$start_solarday[i], ]
        stac_table$assets[[i]] <- assets
      }
    }
  }
  
  stac_table[vapply(stac_table$assets, nrow, integer(1)) > 0, ]
}

getstac_json <- function(x, trigger) {
  js <- try(jsonlite::fromJSON(x$query))
  if (inherits(js, "try-error") || (length(js$features) < 1) || (!is.null(js$numberReturned) &&js$numberReturned < 1)) {
    return(list())
  } else {
    return(js)
  }
  x
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

getstac_query_adaptive <- function(query_specs, provider, collection, limit = 300) {
  llnames <- c("lonmin", "lonmax", "latmin", "latmax")
  
  query_specs$provider <- provider
  query_specs$collection <- collection
  query_specs$query <- NA_character_
  
  for (i in seq_len(nrow(query_specs))) {
    llex <- unlist(query_specs[i, llnames])
    date <- c(query_specs$start[i], query_specs$end[i])
    
    href <- sds::stacit(llex, date, limit = limit, 
                        collections = collection, 
                        provider = provider)
    query_specs$query[i] <- href
  }
  
  query_specs
}

inspect_markers <- function(bucket) {
  set_gdal_envs()
  
  marker_dir <- sprintf("/vsis3/%s/markers/", bucket)
  
  files <- gdalraster::vsi_read_dir(marker_dir, max_files = 1000)
  
  if (length(files) == 0) {
    return(data.frame(SITE_ID = character(), location = character(), 
                      last_solarday = character(), last_updated = character()))
  }
  
  markers_list <- vector("list", length(files))
  
  for (i in seq_along(files)) {
    marker_path <- file.path(marker_dir, files[i])
    tryCatch({
      con <- new(gdalraster::VSIFile, marker_path, "r")
      json_bytes <- con$ingest(-1)
      con$close()
      
      marker_data <- jsonlite::fromJSON(rawToChar(json_bytes))
      markers_list[[i]] <- as.data.frame(marker_data, stringsAsFactors = FALSE)
    }, error = function(e) {
      markers_list[[i]] <- NULL
    })
  }
  
  dplyr::bind_rows(markers_list)
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

prepare_queries <- function(spatial_window, markers, 
                            default_start = "2015-01-01", 
                            now = Sys.time()) {
  
  query_table <- dplyr::left_join(spatial_window, markers, 
                                  by = c("SITE_ID", "location"))
  
  query_table$start_solarday <- ifelse(
    is.na(query_table$last_solarday),
    as.Date(default_start),
    query_table$last_solarday + 1
  )
  
  end_solarday <- as.Date(now)
  
  query_table$offset_hours <- query_table$lon / 15
  query_table$buffer_hours <- abs(query_table$offset_hours) + 12
  
  query_table$query_start_utc <- as.POSIXct(query_table$start_solarday, tz = "UTC") - 
    (query_table$buffer_hours * 3600)
  query_table$query_end_utc <- as.POSIXct(end_solarday + 1, tz = "UTC") + 
    (query_table$buffer_hours * 3600)
  
  query_table$start <- format(query_table$query_start_utc, "%Y-%m-%dT%H:%M:%SZ")
  query_table$end <- format(query_table$query_end_utc, "%Y-%m-%dT%H:%M:%SZ")
  
  query_table
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

read_markers <- function(bucket, spatial_window) {
  set_gdal_envs()
  
  markers_list <- vector("list", nrow(spatial_window))
  
  for (i in seq_len(nrow(spatial_window))) {
    site_id <- spatial_window$SITE_ID[i]
    marker_path <- sprintf("/vsis3/%s/markers/%s.json", bucket, site_id)
    
    if (gdalraster::vsi_stat(marker_path, "exists")) {
      tryCatch({
        con <- new(gdalraster::VSIFile, marker_path, "r")
        json_bytes <- con$ingest(-1)
        con$close()
        
        marker_data <- jsonlite::fromJSON(rawToChar(json_bytes))
        markers_list[[i]] <- data.frame(
          SITE_ID = site_id,
          location = marker_data$location,
          last_solarday = as.Date(marker_data$last_solarday),
          stringsAsFactors = FALSE
        )
      }, error = function(e) {
        markers_list[[i]] <- data.frame(
          SITE_ID = site_id,
          location = spatial_window$location[i],
          last_solarday = as.Date(NA),
          stringsAsFactors = FALSE
        )
      })
    } else {
      markers_list[[i]] <- data.frame(
        SITE_ID = site_id,
        location = spatial_window$location[i],
        last_solarday = as.Date(NA),
        stringsAsFactors = FALSE
      )
    }
  }
  
  dplyr::bind_rows(markers_list)
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

stretch_histeq <- function(x, ...) {
  ## stretch as if all the pixels were in the same band (not memory safe)
  rv <- terra::stretch(terra::rast(matrix(terra::values(x))), histeq = TRUE, maxcell = terra::ncell(x))
  ## set the values to the input, then stretch to 0,255
  terra::stretch(terra::setValues(x, c(terra::values(rv))), histeq = FALSE, maxcell = terra::ncell(x))
}
stretch_q128 <- function(xx, n = 128L, type = 7L) {
  q <- quantile(terra::values(xx), seq(0, 1, length.out = n), type = type, names = FALSE, na.rm = TRUE)
  terra::stretch(terra::setValues(xx, q[cut(terra::values(xx), unique(q), labels = F, include.lowest = T)]))
}
unproj <- function(x, source) {
  reproj::reproj_extent(x, "EPSG:4326", source = source)
}

update_markers <- function(images_table) {
  marker_updates <- images_table |>
    dplyr::group_by(SITE_ID, location) |>
    dplyr::summarise(
      last_solarday = max(solarday, na.rm = TRUE),
      n_images = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::filter(!is.na(last_solarday), !is.infinite(last_solarday))
  
  marker_updates
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

write_markers <- function(bucket, updated_markers) {
  set_gdal_envs()
  
  success <- vector("logical", nrow(updated_markers))
  
  for (i in seq_len(nrow(updated_markers))) {
    marker_data <- list(
      SITE_ID = updated_markers$SITE_ID[i],
      location = updated_markers$location[i],
      last_solarday = as.character(updated_markers$last_solarday[i]),
      n_images = updated_markers$n_images[i],
      last_updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
    )
    
    json_str <- jsonlite::toJSON(marker_data, auto_unbox = TRUE, pretty = TRUE)
    json_bytes <- charToRaw(json_str)
    
    marker_path <- sprintf("/vsis3/%s/markers/%s.json", bucket, updated_markers$SITE_ID[i])
    
    tryCatch({
      con <- new(gdalraster::VSIFile, marker_path, "w")
      con$write(json_bytes)
      con$close()
      
      success[i] <- gdalraster::vsi_stat(marker_path, "exists")
    }, error = function(e) {
      warning(sprintf("Failed to write marker for %s: %s", 
                      updated_markers$location[i], e$message))
      success[i] <- FALSE
    })
  }
  
  if (sum(success) < length(success)) {
    warning(sprintf("Wrote %d/%d markers successfully", 
                    sum(success), length(success)))
  }
  
  success
}

write_react_json <- function(x) {
  set_gdal_envs()
  allfiles <- split(x, x$location) 
  locationdets <- lapply(allfiles, function(aloc) {
    imagerow <- lapply(split(aloc, 1:nrow(aloc)), function(arow) {
      list(id = digest::digest(arow), 
           date = format(arow[["solarday"]]), 
           url = list(q128 = arow$view_q128, histeq = arow$view_histeq, stretch = arow$view_stretch),
           thumbnail = list(q128 = arow$thumb_q128, histeq = arow$thumb_histeq, stretch = arow$thumb_stretch), 
           download = arow$outfile)
    })
    location_id <- aloc$SITE_ID[1L]
    location_name <- aloc$location[1L]
    out <- list(id = location_id, name = location_name, images = imagerow)
    if ("purpose" %in% names(aloc)) {
      out$purpose <- aloc$purpose[[1]]  # purpose is list column
    }
    out
  })
  outfile <- "inst/docs/image-catalog.json"
  if (!is_cloud(outfile)) {
    if (!fs::dir_exists(dirname(outfile))) fs::dir_create(dirname(outfile))
    jsonlite::write_json(list(locations = locationdets), outfile, pretty = TRUE, auto_unbox = TRUE)
  }
  outfile
}
