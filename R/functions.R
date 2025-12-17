#' Check if browser HTML needs updating
#'
#' @param local_path Character. Path to local browser HTML
#' @param remote_url Character. URL of deployed browser
#' @return Logical. TRUE if files differ, FALSE if identical
check_browser_needs_update <- function(
    local_path = "inst/docs/catalog-browser.html",
    remote_url = "https://projects.pawsey.org.au/estinel/catalog/catalog-browser.html"
) {
  
  if (!file.exists(local_path)) {
    warning("Local browser file not found: ", local_path)
    return(FALSE)
  }
  
  # Read local file
  local_content <- readLines(local_path, warn = FALSE)
  local_hash <- digest::digest(paste(local_content, collapse = "\n"), algo = "md5")
  
  # Fetch remote file
  tryCatch({
    temp_file <- tempfile(fileext = ".html")
    download.file(remote_url, temp_file, quiet = TRUE, mode = "wb")
    remote_content <- readLines(temp_file, warn = FALSE)
    remote_hash <- digest::digest(paste(remote_content, collapse = "\n"), algo = "md5")
    unlink(temp_file)
    
    # Compare
    needs_update <- local_hash != remote_hash
    
    if (needs_update) {
      message("Browser HTML has changed (local hash: ", local_hash, 
              ", remote hash: ", remote_hash, ")")
    } else {
      message("Browser HTML is up to date")
    }
    
    return(needs_update)
    
  }, error = function(e) {
    warning("Could not fetch remote browser: ", e$message)
    # If can't fetch remote, assume needs update (safe default)
    return(TRUE)
  })
}


#' #' Update browser HTML on remote server
#' #'
#' #' @param local_path Character. Path to local browser HTML
#' #' @param bucket Character. S3 bucket name
#' #' @param remote_path Character. Path within bucket
#' #' @return Logical. TRUE if upload successful
#' update_browser_html <- function(
#'     local_path = "inst/docs/catalog-browser.html",
#'     bucket = "estinel",
#'     remote_path = "catalog/catalog-browser.html"
#' ) {
#'   
#'   set_gdal_envs()
#'   
#'   if (!file.exists(local_path)) {
#'     stop("Local browser file not found: ", local_path)
#'   }
#'   
#'   # Upload to S3
#'   output_path <- sprintf("/vsis3/%s/%s", bucket, remote_path)
#'   
#'   tryCatch({
#'     # Read local file
#'     con_local <- file(local_path, "rb")
#'     bytes <- readBin(con_local, "raw", file.info(local_path)$size)
#'     close(con_local)
#'     
#'     # Write to S3
#'     con_remote <- new(gdalraster::VSIFile, output_path, "w")
#'     con_remote$write(bytes)
#'     con_remote$close()
#'     
#'     # Verify upload
#'     if (gdalraster::vsi_stat(output_path, "exists")) {
#'       message("✓ Browser HTML uploaded successfully to ", output_path)
#'       return(TRUE)
#'     } else {
#'       warning("Upload may have failed - file not found at ", output_path)
#'       return(FALSE)
#'     }
#'     
#'   }, error = function(e) {
#'     warning("Failed to upload browser HTML: ", e$message)
#'     return(FALSE)
#'   })
#' }


update_browser_html <- function(
    local_path = "inst/docs/catalog-browser.html",
    bucket = "estinel",
    remote_path = "catalog/catalog-browser.html"
) {
  
  if (!file.exists(local_path)) {
    stop("Local browser file not found: ", local_path)
  }
  
  # Use AWS CLI with correct Content-Type (simpler than GDAL for HTML)
  s3_url <- sprintf("s3://%s/%s", bucket, remote_path)
  cmd <- sprintf(
    'aws s3 --profile pawsey1197 cp "%s" "%s" --content-type "text/html"',
    local_path, s3_url
  )
  
  result <- system(cmd, ignore.stdout = FALSE)
  
  if (result == 0) {
    message("✓ Browser HTML uploaded with correct Content-Type")
    return(TRUE)
  } else {
    stop("Upload failed")
  }
}
#' Check and update browser if needed
#'
#' @param local_path Character. Path to local browser HTML
#' @param remote_url Character. URL of deployed browser
#' @param bucket Character. S3 bucket name
#' @param remote_path Character. Path within bucket
#' @return Character. Status message
check_and_update_browser <- function(
    local_path = "inst/docs/catalog-browser.html",
    remote_url = "https://projects.pawsey.org.au/estinel/catalog/catalog-browser.html",
    bucket = "estinel",
    remote_path = "catalog/catalog-browser.html"
) {
  
  # Check if update needed
  needs_update <- check_browser_needs_update(local_path, remote_url)
  
  if (!needs_update) {
    return("Browser is up to date - no upload needed")
  }
  
  # Upload
  message("Browser has changed - uploading update...")
  success <- update_browser_html(local_path, bucket, remote_path)
  
  if (success) {
    return(sprintf("Browser updated successfully at %s", Sys.time()))
  } else {
    return("Browser update FAILED - check logs")
  }
}
audit_location_coverage <- function(viewtable, expected_start = "2015-01-01") {
  coverage <- viewtable |> 
    dplyr::group_by(location) |> 
    dplyr::summarise(
      n_images = dplyr::n(),
      oldest = min(solarday),
      newest = max(solarday),
      years = paste(unique(format(solarday, "%Y")), collapse = ","),
      date_span_days = as.numeric(difftime(max(solarday), min(solarday), units = "days")),
      .groups = "drop"
    ) |> 
    dplyr::mutate(
      suspicious = oldest > as.Date("2020-01-01"),  # Should have older data
      years_count = lengths(strsplit(years, ","))
    ) |> 
    dplyr::arrange(oldest)
  
  list(
    all = coverage,
    suspicious = dplyr::filter(coverage, suspicious),
    summary = list(
      total_locations = nrow(coverage),
      suspicious_count = sum(coverage$suspicious),
      total_images = sum(coverage$n_images)
    )
  )
}

build_ndvi_dsn <- function(assets, rootdir = tempdir()) {
  build_warped_composite(assets, c("nir", "red"), "_ndvi",
                         rootdir = rootdir, return_tibble = FALSE)
}
# ==============================================================================
# REFACTORED: Consolidated Image Building Functions
# ==============================================================================
# Combines build_image_dsn and build_scl_dsn into a single flexible function
# ==============================================================================

#' Build warped composite from Sentinel-2 assets
#' 
#' Generic function to warp one or more bands to a target extent/CRS.
#' Handles both single-band (SCL) and multi-band (RGB) outputs.
#'
#' @param assets Data frame with asset URLs and metadata
#' @param band_names Character vector. Asset column names to extract
#' @param suffix Character. File suffix (e.g., "_scl" or "")
#' @param resample Character. Resampling method
#' @param rootdir Character. Root output directory
#' @param return_tibble Logical. Return tibble (TRUE) or path (FALSE)
#' @return Tibble or character path depending on return_tibble
build_warped_composite <- function(assets, 
                                   band_names = c("red", "green", "blue"),
                                   suffix = "",
                                   resample = "near", 
                                   rootdir = tempdir(),
                                   return_tibble = TRUE) {
  
  set_gdal_envs()
  
  # === COMMON SETUP ===
  res <- assets$resolution[1]
  collection <- assets$collection[1]
  date <- assets$solarday[1]
  location <- assets$location[1L]
  
  # Build output path
  root <- sprintf("%s/%s/%s", rootdir, collection, format(date, "%Y/%m/%d"))
  outfile <- sprintf("%s/%s_%s%s.tif", root, location, format(date), suffix)
  
  # Prepare tibble return (if needed)
  if (return_tibble) {
    result <- tibble::tibble(
      outfile = NA_character_, 
      location = location,
      SITE_ID = assets$SITE_ID[1],
      clear_test = assets$clear_test[1], 
      solarday = date,
      scl_tif = if("scl_tif" %in% names(assets)) assets$scl_tif[1] else NA_character_,
      assets = list(assets)
    )
  }
  
  # === CHECK IF EXISTS ===
  if (gdalraster::vsi_stat(outfile, "exists")) {
    if (return_tibble) {
      result$outfile <- outfile
      return(result)
    } else {
      return(outfile)
    }
  }
  
  # === CREATE DIRECTORY ===
  if (!dir.exists(root) && !is_cloud(root)) {
    dir.create(root, showWarnings = FALSE, recursive = TRUE)
  }
  
  # === EXTRACT TARGET EXTENT AND CRS ===
  crs <- assets$crs[1]
  ex <- unlist(assets[1L, c("xmin", "xmax", "ymin", "ymax")], use.names = FALSE)
  
  # === WARP BANDS ===
  warped_bands <- vector("list", length(band_names))
  
  for (i in seq_along(band_names)) {
    band_name <- band_names[i]
    
    # Get source URLs for this band
    band_col <- band_name
    
    # Handle PC vs Element84 naming
    if (grepl("windows.net", assets[[1]][1L])) {
      # Planetary Computer uses different band names
      band_mapping <- c(red = "B04", green = "B03", blue = "B02", scl = "SCL")
      if (band_name %in% names(band_mapping)) {
        band_col <- band_mapping[band_name]
      }
    }
    
    # Extract URLs
    dsns <- assets[[band_col]]
    if (band_col == "scl" || band_col == "SCL") {
      # SCL might be under different column name
      if (is.na(dsns)[1]) dsns <- assets[["SCL"]]
    }
    
    dsns <- dsns[!is.na(dsns)]
    
    if (length(dsns) < 1) {
      if (return_tibble) return(result) else return(NA_character_)
    }
    
    # Add vsicurl wrapper
    for (ii in seq_along(dsns)) {
      dsns[ii] <- vsicurl_for(dsns[ii], pc = grepl("windows.net", dsns[ii]))
    }
    
    # Warp this band
    warped <- try(
      warp_to_dsn(dsns, 
                  target_crs = crs, 
                  target_res = res, 
                  target_ext = ex, 
                  resample = resample)[[1]], 
      silent = TRUE
    )
    
    if (inherits(warped, "try-error")) {
      if (return_tibble) return(result) else return(NA_character_)
    }
    
    warped_bands[[i]] <- warped
  }
  
  # === BUILD OUTPUT ===
  if (length(warped_bands) == 1) {
    # Single band - use directly
    final_file <- warped_bands[[1]]
  } else {
    # Multiple bands - build VRT
    vrt <- try(vapour::buildvrt(unlist(warped_bands)), silent = TRUE)
    if (inherits(vrt, "try-error")) {
      if (return_tibble) return(result) else return(NA_character_)
    }
    final_file <- vrt
  }
  
  # === WRITE TO S3 ===
  write_result <- try(put_bytes_at(final_file, outfile), silent = TRUE)
  
  if (inherits(write_result, "try-error")) {
    if (return_tibble) return(result) else return(NA_character_)
  }
  
  # === RETURN ===
  if (return_tibble) {
    result$outfile <- outfile
    result
  } else {
    outfile
  }
}

# ==============================================================================
# WRAPPER FUNCTIONS - Keep Original API
# ==============================================================================

#' Build RGB composite (wrapper)
build_image_dsn <- function(assets, resample = "near", rootdir = tempdir()) {
  build_warped_composite(
    assets,
    band_names = c("red", "green", "blue"),
    suffix = "",
    resample = resample,
    rootdir = rootdir,
    return_tibble = TRUE
  )
}

#' Build SCL layer (wrapper)
build_scl_dsn <- function(assets, div = NULL, root = tempdir()) {
  # Note: div parameter ignored in new implementation
  # (was never actually used in original code)
  build_warped_composite(
    assets,
    band_names = "scl",
    suffix = "_scl",
    resample = "near",
    rootdir = root,
    return_tibble = FALSE
  )
}

# ==============================================================================
# BENEFITS:
# ==============================================================================
# 1. Single source of truth for warping logic
# 2. No code duplication (was ~80% identical)
# 3. Easy to add new band combinations:
#    - NDVI: build_warped_composite(assets, c("nir", "red"), "_ndvi")
#    - True color: already have it!
#    - False color: build_warped_composite(assets, c("nir", "red", "green"))
# 4. Consistent error handling across all outputs
# 5. Easier to test (one function to test, not two)
# 6. Easier to optimize (improve once, benefits all)
# 7. Maintains backward compatibility via wrappers
build_image_png <- function(x, force = FALSE, type) {
  set_gdal_envs()
  test <- try({
    dsn <- x[["outfile"]]
    if (length(dsn) > 1) {
      print("bad")
      print(dsn)
    }
    set_gdal_envs()
    
    if (is.na(dsn)) return(NA_character_)
    #gsub("tif$", "png", dsn)
    outpng <- gsub("\\.tif$", sprintf("_%s.png", type),  dsn)
    if (gdalraster::vsi_stat(outpng, "exists")) {
      if (!force) {
        return(outpng)  ## silently ignore
      }
    }
    Sys.unsetenv("AWS_NO_SIGN_REQUEST")
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
   set_gdal_envs()
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
  x$purpose <- "emperor"
  x
}

define_locations_table <- function() {
  dplyr::bind_rows(
    tibble::tibble(location = "Hobart", lon = 147.3257, lat = -42.8826, resolution = 10, radiusx = 3000, radiusy = 3000, purpose = "tasmania"), 
    tibble::tibble(location = "Kingston_HQ", lon = 147.2919, lat = -42.9866, purpose = "tasmania,base"),
    tibble::tibble(location = "Davis_Station", lon = 77.9675, lat = -68.5767, purpose = "base,antarctica"), 
    tibble::tibble(location = "Casey_Station", lon = 110.5267, lat = -66.2825, purpose = "base,antarctica"), 
    tibble::tibble(location = "Casey_Station_2", lon = 110.5267, lat = -66.2825, radiusx = 5000, radiusy = 5000, purpose = "base,casey,antarctica,island"), 
    tibble::tibble(location = "Heard_Island_Atlas_Cove", lon = 73.3868, lat = -53.0243, purpose = "base,heard,subantarctic,island"),
    tibble::tibble(location = "Heard_Island_Atlas_Cove_2", lon = 73.3868, lat = -53.0243, radiusx = 5000, radiusy = 5000, purpose = "base,heard,island"),
    tibble::tibble(location = "Heard_Island_60m", lon = 73.5028, lat = -53.0914, resolution = 60, radiusx = 24000, radiusy = 14000, purpose = "heard,subantarctic,island"),
    tibble::tibble(location = "Heard_Island_180m", lon = 73.5028, lat = -53.0914, resolution = 180, radiusx = 72000, radiusy = 72000, purpose = "heard,subantarctic,island"),
    tibble::tibble(location = "Heard_Island_360m", lon = 73.5028, lat = -53.0914, resolution = 180*2, radiusx = 96000*2, radiusy = 96000*2, purpose = "heard,subantarctic,island"),
    tibble::tibble(location = "Burnie", lon = 145.912, lat = -41.050, radiusx = 5000, radiusy = 5000, purpose = "tasmania,base"),
    tibble::tibble(location = "Heard_Island_Big_Ben", lon = 73.5167, lat = -53.1000, purpose = "heard,subantarctic,island"), 
    tibble::tibble(location = "Heard_Island_Big_Ben_2", lon = 73.5167, lat = -53.1000, radiusx = 6000, radiusy = 6000, purpose = "heard,subantarctic,island"), 
    tibble::tibble(location  = "Heard_Island_Compton_Lagoon_water", lon = 73.641231, lat = -53.035654, purpose = "heard,subantarctic,island"),
tibble::tibble(location = "Cape_Grim", lat = -40.6833327, lon = 144.6833333,purpose = "tasmania"),
tibble::tibble(location = "Bunger_Hills", lon = 100.783333, lat = -66.283333, purpose = "antarctica"),
tibble::tibble(location = "Lonnavale", lon = 146.765534, lat = -42.973019, purpose = "tasmania"),
tibble::tibble(location = "Wilkins_Aerodrome", lon = 111.52361, lat = -66.69083, purpose = "antarctica"), 
tibble::tibble(location = "Punta_Arenas_Aerodrome", lon = -70.8495728, lat = -53.0040603, purpose = "chile"), 
tibble::tibble(location = "Cambridge_Aerodrome", lon = 147.4739782, lat = -42.8299091, purpose = "tasmania"),
tibble::tibble(location = "Wilkes_Station", lon = 110.526862, lat = -66.256951, purpose = "antarctica"),
tibble::tibble(location = "McMurdo_Station", lon = 166.5280322, lat = -77.8400482, purpose = "antarctica,usa"), 
    tibble::tibble(location = "Heard_Island_Spit_Bay", lon = 73.7189, lat = -53.1141, purpose = "heard,subantarctic,island"),
    tibble::tibble(location = "Heard_Island_Spit_Bay_2", lon = 73.7189, lat = -53.1141, radiusx = 5000, radiusy = 5000, purpose = "heard,subantarctic,island"),
    tibble::tibble(location = "Heard_Island_Compton_Lagoon", lon = 73.6107, lat = -53.0581, purpose = "heard,island"),
    tibble::tibble(location = "Mawson_Station", lon = 62.8742, lat = -67.6033, purpose = "base,mawson,antarctica"),
    tibble::tibble(location = "Macquarie_Island_Station", lon = 158.9384, lat = -54.4987, purpose = "base,macquarie,subantarctic,island,tasmania"),
    tibble::tibble(location = "Macquarie_Island_South", lon = 158.8252, lat = -54.7556, purpose = "macquarie,subantarctic,island,tasmania"),
    tibble::tibble(location = "Macquarie_Island_40m", lon = 158.5766275, lat = -54.6071339, radiusx = 48000, radiusy = 48000, resolution = 40, purpose = "macquarie,subantarctic,island,tasmania"),
    tibble::tibble(location = "Bowman_Island_20m", lon = 103.117479, lat = -65.2992428, radiusx = 20000, radiusy = 20000, purpose  = "island,antarctica"),
    tibble::tibble(location = "Kiribati_1", lon = -157.43508, lat = 1.8927, purpose = "island"),
    tibble::tibble(location = "Scullin_Monolith", lon = 66.7189, lat = -67.7935, purpose = "antarctica"), 
    tibble::tibble(location = "Concordia_Station", lon = 123.3322, lat = -75.0997, purpose = "antarctica"), 
    tibble::tibble(location = "Dome_C_North", lon = 122.5206, lat = -75.3413, purpose = "base,antarctica"), 
    tibble::tibble(location = "Dome_C_M", lon = 123.617360, lat = -75.041920,  purpose = "base,antarctica"), 
    tibble::tibble(location = "Bechervaise_Island", lon = 62.8170, lat = -67.5830, radiusx = 5000, radiusy = 5000, purpose = "adelie,antarctica,island"),
    tibble::tibble(location = "Cape_Denison", lon = 142.6630, lat = -67.0086, purpose = "adelie,antarctica"), 
    tibble::tibble(location = "Glen_Lusk", lon = 147.1948, lat = -42.8183, purpose = "tasmania"),
    tibble::tibble(location = "Dolphin_Sands", lon = 148.1000, lat = -42.0890, radiusx = 5000, radiusy = 5000, purpose = "tasmania"),
    tibble::tibble(location = "Fern_Tree", lon = 147.2601, lat = -42.9223, purpose = "tasmania"), 
    tibble::tibble(location = "Maatsuyker_Island", lon = 146.2619, lat = -43.6480, purpose = "tasmania,island"), 
    tibble::tibble(location = "Pedra_Branca_Eddystone", lon = 146.9831, lat = -43.8528, purpose = "tasmania"), 
    tibble::tibble(location = "Precipitous_Bluff", lon = 146.5987, lat = -43.4704, purpose = "tasmania"), 
    tibble::tibble(location = "Mt_Anne", lon = 146.4114, lat = -42.9588, purpose = "tasmania"), 
    tibble::tibble(location = "Robbins_Island", lon = 144.8985, lat = -40.6977, radiusx = 5000, radiusy = 5000, purpose = "tasmania,island"),
    tibble::tibble(location = "Mt_Bobs", lon = 146.5694, lat = -43.2900, purpose = "tasmania"),
    tibble::tibble(location = "Tasman_Island", lon = 148.0045, lat = -43.2388, purpose = "tasmania,island,cetacean"),
    tibble::tibble(location = "Dumont_dUrville_Station", lon = 139.9978, lat = -66.6651, purpose = "antarctica"), 
    tibble::tibble(location = "Pearson_Sandhills", lon = 131.1440, lat = -31.4633, purpose = "cetacean,southaustralia"),
    tibble::tibble(location = "Head_of_the_Bight", lon = 131.158572, lat  = -31.493584, purpose = "cetacean,southaustralia"),
    tibble::tibble(location = "Rapa_Nui", lon = -109.4292, lat = -27.1984, purpose = "cetacean,island,chile"),
    tibble::tibble(location = "Maui", lon = -156.46262, lat = 20.6366, purpose = "cetacean,island,hawaii"),
tibble::tibble(location = "French Island", lon = 145.3472, lat = -38.3484, purpose = "island,victoria"),
tibble::tibble(location = "McDonald_Island", lon = 72.5773193, lat = -53.0379566, purpose = "island,mcdonald,subantarctic"),
tibble::tibble(location = "Flinders_Island_100m", lon =148.2472915 , lat = -40.2174148, resolution = 100,purpose = "flinders,island,tasmania",  radiusx=15000, radiusy=50000),
tibble::tibble(location = "King_Island_100m", lon = 144.0929451, lat = -39.8263455, resolution = 100, radiusx = 35000, radiusy = 20000, purpose = "king,island,tasmania"),
tibble::tibble(location = "Bruny_Island_100m", lon = 147.2883943, lat = -43.3273722, resolution = 100, radiusx = 35000, radiusy = 20000, purpose = "bruny,island,tasmania"),
tibble::tibble(location = "Maria_Island_100m", lon = 148.0659583, lat = -42.6488181, resolution = 100, radiusx = 35000, radiusy = 20000, purpose = "maria,island,tasmania"),

      tibble::tibble(location = "Kerguelen_Island_Esperance",lon = 70.0463278,lat = -49.476426,purpose = "kerguelen,island,subantarctic"), 
tibble::tibble(location = "Kerguelen_Island_100m",lon = 69.5,lat = -49.35,radiusx = 85000,radiusy = 85000,resolution = 100,purpose = "island,subantarctic"), 
tibble::tibble(location = "Posession_Island", lon = 51.7255261, lat = -46.404379, purpose = "crozet,island,subantarctic"),
tibble::tibble(location = "Campbell_Island", lon = 169.0854021, lat = -52.5464621, purpose = "campbell,island,subantarctic"),
tibble::tibble(location = "New_Brighton", lon = 153.57131, lat = -28.538562, purpose = "cetacean,nsw"),
      # Eyjafjörður Whale Research Site
    tibble::tibble(location = "Eyjafjordur", lon = -18.2 + 0.073,  lat =65.85, radiusx = 5000, radiusy = 5000, purpose = "cetacean,island,iceland"),
    tibble::tibble(location = "Eyjafjordur_Fjord", lon = -18.2 + 0.073,  lat =65.85, radiusx = 12000, radiusy = 12000, resolution = 20, purpose = "cetacean,island,iceland"),
    tibble::tibble(location = "San_Simeon", lon = -121.1464257, lat = 35.6114425, purpose = "pinniped,california"),
    cleanup_table()) |> fill_values() |> dplyr::distinct(location, .keep_all = TRUE) |> check_table()
}

fill_values <- function(x) {
  for (var in c("resolution", "radiusx", "radiusy")) {
    bad <- is.na(x[[var]])
    x[[var]][bad] <- x[[var]][1]  ## better not be NA
  }
  badpurp <- is.na(x$purpose)
  if (any(badpurp))  x$purpose[badpurp] <- "none"

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

# getstac_json <- function(x, trigger) {
#   js <- try(jsonlite::fromJSON(x$query))
#   if (inherits(js, "try-error") || (length(js$features) < 1) || (!is.null(js$numberReturned) &&js$numberReturned < 1)) {
#     return(list())
#   } else {
#     return(js)
#   }
#   x
# }



#' Fetch STAC JSON for a single row (used in mapped target)
#' Returns identifying info along with results for safe joining
getstac_json <- function(x, trigger) {
  js <- try(jsonlite::fromJSON(x$query))
  
  result <- list(
    location = x$location,
    SITE_ID = x$SITE_ID,
    chunk_id = x$chunk_id,
    js = if (inherits(js, "try-error") || (length(js$features) < 1) || 
             (!is.null(js$numberReturned) && js$numberReturned < 1)) {
      list(empty = TRUE)
    } else {
      js
    }
  )
  result
}


#' Join STAC results back to querytable by key
join_stac_results <- function(querytable, stac_json_list) {
  # Convert list to data frame with keys
  stac_df <- dplyr::bind_rows(lapply(stac_json_list, function(x) {
    data.frame(
      location = x$location, 
      SITE_ID = x$SITE_ID, 
      chunk_id = x$chunk_id, 
      stringsAsFactors = FALSE
    )
  }))
  stac_df$js <- lapply(stac_json_list, `[[`, "js")
  
  # Join by keys instead of position
  result <- dplyr::left_join(querytable, stac_df, 
                             by = c("location", "SITE_ID", "chunk_id"))
  
  message("Joined ", sum(!is.na(result$js)), " of ", nrow(result), " queries with results")
  result
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


# ==============================================================================
# WORKAROUND: Smart Query Chunking for Bootstrap + Markers
# ==============================================================================
# Add this to R/functions.R (after prepare_queries)
# ==============================================================================

#' Prepare queries with automatic chunking for long date ranges
#'
#' Detects bootstrap runs (> 365 days) and chunks into yearly queries
#' to avoid STAC limit=300 truncation. Incremental runs (< 365 days)
#' use single queries as before.
#'
#' @param spatial_window Data frame with location spatial windows
#' @param markers Data frame with last_solarday per location
#' @param default_start Character. Bootstrap start date
#' @param now POSIXct. Current time
#' @param chunk_threshold_days Integer. Days span to trigger chunking (default 365)
#' @return Data frame with query specifications (potentially expanded with chunks)
prepare_queries_chunked <- function(spatial_window, markers = NULL, 
                                    default_start = "2015-01-01", 
                                    now = Sys.time(),
                                    chunk_threshold_days = 365) {
  
  # Start with basic query prep
  if (!is.null(markers)) {
  query_table <- dplyr::left_join(spatial_window, markers, 
                                  by = c("SITE_ID", "location"))
  } else {
    query_table <- spatial_window
  }

  print(sprintf("about to set start_solarday for %s", paste0(spatial_window$location, collapse = ",")))
  # Fix: Use if_else to preserve Date class
  # query_table$start_solarday <- dplyr::if_else(
  #   is.na(query_table$last_solarday),
  #   as.Date(default_start),
  #   query_table$last_solarday + 1
  # )
  #print(sprintf("finished %s", spatial_window$location))
  # 
  query_table$start_solarday <- dplyr::if_else(
    is.na(query_table$last_solarday),
    as.Date(default_start),
    pmax(query_table$last_solarday + 1, as.Date("2024-01-01"))  # Floor it
  )
print(sprintf("finished %s", spatial_window$location))

  end_solarday <- as.Date(now) + 1
  
  # Calculate timezone buffers
  query_table$offset_hours <- query_table$lon / 15
  query_table$buffer_hours <- abs(query_table$offset_hours) + 12
  
  # NEW: Detect which locations need chunking
  query_table$days_span <- as.numeric(end_solarday - query_table$start_solarday)
  query_table$needs_chunking <- query_table$days_span > chunk_threshold_days
  
  # Separate into chunked and non-chunked
  no_chunk <- query_table[!query_table$needs_chunking, ]
  needs_chunk <- query_table[query_table$needs_chunking, ]
  
  # Process non-chunked (incremental runs)
  if (nrow(no_chunk) > 0) {
    no_chunk$query_start_utc <- as.POSIXct(no_chunk$start_solarday, tz = "UTC") - 
      (no_chunk$buffer_hours * 3600)
    no_chunk$query_end_utc <- as.POSIXct(end_solarday + 1, tz = "UTC") + 
      (no_chunk$buffer_hours * 3600)
    
    no_chunk$start <- format(no_chunk$query_start_utc, "%Y-%m-%dT%H:%M:%SZ")
    no_chunk$end <- format(no_chunk$query_end_utc, "%Y-%m-%dT%H:%M:%SZ")
    no_chunk$chunk_id <- 1L
  }
  
  # Process chunked (bootstrap runs)
  chunked_list <- list()
  if (nrow(needs_chunk) > 0) {
    for (i in seq_len(nrow(needs_chunk))) {
      row <- needs_chunk[i, ]
      
      # Create yearly chunks
      start_date <- row$start_solarday
      chunk_starts <- seq(start_date, end_solarday, by = "1 year")
      
      # Handle the last chunk (partial year)
      if (chunk_starts[length(chunk_starts)] < end_solarday) {
        chunk_starts <- c(chunk_starts, end_solarday)
      }
      
      # Create a row for each chunk
      for (j in seq_len(length(chunk_starts) - 1)) {
        chunk_row <- row
        chunk_start <- chunk_starts[j]
        chunk_end <- min(chunk_starts[j + 1] - 1, end_solarday)
        
        # Apply timezone buffers to chunk boundaries
        chunk_row$query_start_utc <- as.POSIXct(chunk_start, tz = "UTC") - 
          (chunk_row$buffer_hours * 3600)
        chunk_row$query_end_utc <- as.POSIXct(chunk_end + 1, tz = "UTC") + 
          (chunk_row$buffer_hours * 3600)
        
        chunk_row$start <- format(chunk_row$query_start_utc, "%Y-%m-%dT%H:%M:%SZ")
        chunk_row$end <- format(chunk_row$query_end_utc, "%Y-%m-%dT%H:%M:%SZ")
        chunk_row$chunk_id <- as.integer(j)
        
        chunked_list[[length(chunked_list) + 1]] <- chunk_row
      }
    }
    
    chunked <- dplyr::bind_rows(chunked_list)
  } else {
    chunked <- needs_chunk[0, ]  # Empty with same structure
  }
  
  # Combine and clean up
  result <- dplyr::bind_rows(no_chunk, chunked)
  result$needs_chunking <- NULL
  result$days_span <- NULL
  
  result
}

#' Join chunked STAC results back to single location rows
#'
#' After querying with chunks, this consolidates all chunks for a location
#' back into a single row with combined assets.
#'
#' @param stac_tables Data frame with STAC results (potentially chunked)
#' @return Data frame with consolidated assets per location
consolidate_chunks <- function(stac_tables) {
  
  # Identify locations that were chunked
  chunked_locations <- stac_tables |> 
    dplyr::group_by(SITE_ID, location) |> 
    dplyr::summarise(n_chunks = dplyr::n(), .groups = "drop") |> 
    dplyr::filter(n_chunks > 1)
  
  if (nrow(chunked_locations) == 0) {
    # No chunking happened, return as-is
    return(stac_tables)
  }
  
  # Separate chunked and non-chunked
  non_chunked <- stac_tables |> 
    dplyr::anti_join(chunked_locations, by = c("SITE_ID", "location"))
  
  chunked <- stac_tables |> 
    dplyr::semi_join(chunked_locations, by = c("SITE_ID", "location"))
  
  # Consolidate chunks by combining assets
  consolidated <- chunked |> 
    dplyr::group_by(SITE_ID, location) |> 
    dplyr::summarise(
      # Keep first row's metadata
      lon = dplyr::first(lon),
      lat = dplyr::first(lat),
      resolution = dplyr::first(resolution),
      radiusx = dplyr::first(radiusx),
      radiusy = dplyr::first(radiusy),
      purpose = dplyr::first(purpose),
      crs = dplyr::first(crs),
      lonmin = dplyr::first(lonmin),
      lonmax = dplyr::first(lonmax),
      latmin = dplyr::first(latmin),
      latmax = dplyr::first(latmax),
      xmin = dplyr::first(xmin),
      xmax = dplyr::first(xmax),
      ymin = dplyr::first(ymin),
      ymax = dplyr::first(ymax),
      last_solarday = dplyr::first(last_solarday),
      start_solarday = dplyr::first(start_solarday),
      offset_hours = dplyr::first(offset_hours),
      buffer_hours = dplyr::first(buffer_hours),
      query_start_utc = min(query_start_utc),  # Earliest query
      query_end_utc = max(query_end_utc),      # Latest query
      start = dplyr::first(start),
      end = dplyr::last(end),
      provider = dplyr::first(provider),
      collection = dplyr::first(collection),
      query = dplyr::first(query),  # Just keep one
      # COMBINE all assets from all chunks
      assets = list(dplyr::bind_rows(assets)),
      .groups = "drop"
    )
  
  # Recombine
  result <- dplyr::bind_rows(non_chunked, consolidated)
  
  result
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

# write_react_json <- function(x) {
#   set_gdal_envs()
#   allfiles <- split(x, x$location) 
#   locationdets <- lapply(allfiles, function(aloc) {
#     imagerow <- lapply(split(aloc, 1:nrow(aloc)), function(arow) {
#       list(id = digest::digest(arow), 
#            date = format(arow[["solarday"]]), 
#            url = list(q128 = arow$view_q128, histeq = arow$view_histeq, stretch = arow$view_stretch),
#            thumbnail = list(q128 = arow$thumb_q128, histeq = arow$thumb_histeq, stretch = arow$thumb_stretch), 
#            download = arow$outfile)
#     })
#     location_id <- aloc$SITE_ID[1L]
#     location_name <- aloc$location[1L]
#     out <- list(id = location_id, name = location_name, images = imagerow)
#     if ("purpose" %in% names(aloc)) {
#       out$purpose <- aloc$purpose[[1]]  # purpose is list column
#     }
#     out
#   })
#   outfile <- "inst/docs/image-catalog.json"
#   if (!is_cloud(outfile)) {
#     if (!fs::dir_exists(dirname(outfile))) fs::dir_create(dirname(outfile))
#     jsonlite::write_json(list(locations = locationdets), outfile, pretty = TRUE, auto_unbox = TRUE)
#   }
#   outfile
# }


## CAS system

# ==============================================================================
# S3 CAS (Content-Addressable Storage) TRACKING FUNCTIONS
# ==============================================================================
# These functions enable targets to track S3 file changes via ETags
# Add these to R/functions.R after write_react_json()
# ==============================================================================

#' Get S3 object ETag (MD5 hash) without downloading
#'
#' @param vsis3_uri Character. Path like "/vsis3/bucket/key"
#' @param endpoint Character. S3 endpoint URL
#' @return Character. ETag of the S3 object
get_s3_etag <- function(vsis3_uri, endpoint = "projects.pawsey.org.au") {
  # Convert /vsis3/bucket/key to s3://bucket/key
  s3_uri <- sub("^/vsis3/", "s3://", vsis3_uri)
  
  # Parse bucket and key
  parts <- sub("^s3://", "", s3_uri)
  bucket <- sub("/.*", "", parts)
  key <- sub("^[^/]+/", "", parts)
  
  # Get object metadata
  obj_info <- aws.s3::head_object(
    object = key,
    bucket = bucket,
    base_url = endpoint,
    region = ""
  )
  
  # Extract ETag (strip quotes if present)
  etag <- attr(obj_info, "etag")
  gsub('"', '', etag)
}

#' Create local CAS marker file for S3 object
#'
#' @param vsis3_uri Character. Path to S3 file
#' @param marker_dir Character. Directory to store marker files
#' @return Character. Path to created marker file
create_s3_marker <- function(vsis3_uri, marker_dir = "_targets/s3_markers") {
  if (is.na(vsis3_uri)) return(NA_character_)
  
  dir.create(marker_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Get ETag from S3
  etag <- tryCatch(
    get_s3_etag(vsis3_uri),
    error = function(e) {
      warning(sprintf("Failed to get ETag for %s: %s", vsis3_uri, e$message))
      return(NA_character_)
    }
  )
  
  if (is.na(etag)) return(NA_character_)
  
  # Create marker file path (hash of S3 path for uniqueness)
  marker_name <- paste0(digest::digest(vsis3_uri, algo = "md5"), ".txt")
  marker_file <- file.path(marker_dir, marker_name)
  
  # Write BOTH the S3 path and ETag to marker file
  writeLines(c(vsis3_uri, etag), marker_file)
  
  marker_file
}

#' Read marker file and extract S3 path and ETag
#'
#' @param marker_file Character. Path to marker file
#' @return List with 'path' and 'etag' elements
read_s3_marker <- function(marker_file) {
  if (is.na(marker_file) || !file.exists(marker_file)) {
    return(list(path = NA_character_, etag = NA_character_))
  }
  
  lines <- readLines(marker_file, warn = FALSE)
  list(
    path = lines[1],
    etag = lines[2]
  )
}

#' Validate that S3 file matches marker's ETag
#'
#' @param marker_file Character. Path to marker file
#' @return Logical. TRUE if ETag matches, FALSE otherwise
validate_s3_marker <- function(marker_file) {
  if (is.na(marker_file) || !file.exists(marker_file)) return(FALSE)
  
  marker_data <- read_s3_marker(marker_file)
  if (is.na(marker_data$path) || is.na(marker_data$etag)) return(FALSE)
  
  current_etag <- tryCatch(
    get_s3_etag(marker_data$path),
    error = function(e) NA_character_
  )
  
  if (is.na(current_etag)) return(FALSE)
  
  marker_data$etag == current_etag
}

# ==============================================================================
# TRACKED BUILD FUNCTIONS - WRAPPERS WITH CAS MARKERS
# ==============================================================================

#' Build image with S3 CAS tracking
#'
#' @param assets Data frame of image assets
#' @param resample Character. Resampling method
#' @param rootdir Character. Root directory for outputs
#' @param marker_dir Character. Directory for marker files
#' @return List with s3_path, marker, and metadata
build_image_dsn_tracked <- function(assets, resample = "near", 
                                    rootdir = tempdir(),
                                    marker_dir = "_targets/s3_markers") {
  set_gdal_envs()
  # Build the image (returns tibble with outfile)
  result <- build_image_dsn(assets, resample = resample, rootdir = rootdir)
  
  # Create marker for the S3 file
  marker_file <- if (!is.na(result$outfile)) {
    create_s3_marker(result$outfile, marker_dir)
  } else {
    NA_character_
  }
  
  # Return result with marker
  result$marker <- marker_file
  result
}

#' Build SCL with S3 CAS tracking
#'
#' @param assets Data frame of image assets
#' @param div Numeric. Optional division parameter
#' @param root Character. Root directory
#' @param marker_dir Character. Directory for marker files
#' @return List with s3_path and marker
build_scl_dsn_tracked <- function(assets, div = NULL, root = tempdir(),
                                  marker_dir = "_targets/s3_markers") {
  
  # Build the SCL file
  scl_path <- build_scl_dsn(assets, div = div, root = root)
  
  # Create marker for the S3 file
  marker_file <- if (!is.na(scl_path)) {
    create_s3_marker(scl_path, marker_dir)
  } else {
    NA_character_
  }
  
  # Return both path and marker
  list(
    scl_path = scl_path,
    marker = marker_file
  )
}

#' Build PNG with S3 CAS tracking
#'
#' @param x Data frame with outfile
#' @param force Logical. Force rebuild
#' @param type Character. PNG type
#' @param marker_dir Character. Directory for marker files
#' @return List with png_path and marker
build_image_png_tracked <- function(x, force = FALSE, type,
                                    marker_dir = "_targets/s3_markers") {
  
  # Build the PNG
  png_path <- build_image_png(x, force = force, type = type)
  
  # Create marker for the S3 file
  marker_file <- if (!is.na(png_path)) {
    create_s3_marker(png_path, marker_dir)
  } else {
    NA_character_
  }
  
  # Return both path and marker
  list(
    png_path = png_path,
    marker = marker_file
  )
}

#' Build thumbnail with S3 CAS tracking
#'
#' @param dsn Character. Path to source PNG
#' @param force Logical. Force rebuild
#' @param marker_dir Character. Directory for marker files
#' @return List with thumb_path and marker
build_thumb_tracked <- function(dsn, force = FALSE,
                                marker_dir = "_targets/s3_markers") {
  
  # Build the thumbnail
  thumb_path <- build_thumb(dsn, force = force)
  
  # Create marker for the S3 file
  marker_file <- if (!is.na(thumb_path)) {
    create_s3_marker(thumb_path, marker_dir)
  } else {
    NA_character_
  }
  
  # Return both path and marker
  list(
    thumb_path = thumb_path,
    marker = marker_file
  )
}

# ==============================================================================
# VALIDATION TARGET HELPERS
# ==============================================================================

#' Validate all S3 markers in a tracked table
#'
#' @param tracked_table Data frame with marker columns
#' @return Logical. TRUE if all valid, FALSE if any changed/missing
validate_all_markers <- function(tracked_table) {
  marker_cols <- grep("marker$", names(tracked_table), value = TRUE)
  
  if (length(marker_cols) == 0) return(TRUE)
  
  all_valid <- TRUE
  for (col in marker_cols) {
    markers <- tracked_table[[col]]
    valid <- vapply(markers, validate_s3_marker, logical(1))
    if (any(!valid, na.rm = TRUE)) {
      n_invalid <- sum(!valid, na.rm = TRUE)
      warning(sprintf("%s: %d/%d markers invalid or changed", 
                      col, n_invalid, length(markers)))
      all_valid <- FALSE
    }
  }
  
  all_valid
}

#' Extract S3 paths from tracked results
#'
#' @param tracked_results List or data frame with markers
#' @param path_field Character. Name of path field
#' @return Character vector of S3 paths
extract_s3_paths <- function(tracked_results, path_field = "s3_path") {
  if (is.data.frame(tracked_results)) {
    return(tracked_results[[path_field]])
  }
  
  if (is.list(tracked_results)) {
    return(vapply(tracked_results, function(x) {
      if (is.list(x) && path_field %in% names(x)) {
        x[[path_field]]
      } else {
        NA_character_
      }
    }, character(1)))
  }
  
  NA_character_
}

# ==============================================================================
# S3-Based Catalog Generation (Separate from Pipeline)
# ==============================================================================
# Add to R/functions.R
# ==============================================================================


build_catalog_from_s3 <- function(bucket = "estinel",
                                  prefix = "sentinel-2-c1-l2a",
                                  locations_table, 
                                  wait_for = NULL) {
  
  message("Listing S3 bucket: ", bucket, "/", prefix)
  
  # List all files (include "pawsey/" alias prefix!)
  files <- minioclient::mc_ls(
    paste0("pawsey/", bucket, "/", prefix),
    recursive = TRUE,
    details = TRUE
  )
  
  message("Found ", nrow(files), " total objects")
  
  # Filter to RGB TIFs only (not SCL)
  rgb_files <- files |>
    dplyr::filter(
      tools::file_ext(key) == "tif",
      !grepl("_SCL\\.tif$", key)
    )
  
  message("Found ", nrow(rgb_files), " RGB TIFFs")
  
  # Parse location and date from filenames
  catalog <- rgb_files |>
    dplyr::mutate(
      filename = basename(key),
      location_date = tools::file_path_sans_ext(filename),
      location = sub("_[0-9]{4}-[0-9]{2}-[0-9]{2}$", "", location_date),
      solarday = as.Date(sub(".*_([0-9]{4}-[0-9]{2}-[0-9]{2})$", "\\1", location_date))
    ) |>
    dplyr::filter(!is.na(solarday)) |>
    dplyr::select(location, solarday)
  
  # JOIN to get SITE_ID
  catalog <- catalog |>
    dplyr::left_join(
      locations_table |> dplyr::select(location, SITE_ID, purpose),
      by = "location"
    )
  
  # Warn about orphaned locations
  missing_id <- catalog |> dplyr::filter(is.na(SITE_ID))
  if (nrow(missing_id) > 0) {
    unknown_locs <- unique(missing_id$location)
    warning(
      "Found ", length(unknown_locs), " location(s) in S3 not in locations table:\n",
      paste("  -", unknown_locs, collapse = "\n")
    )
  }
  
  # Return only valid rows
  catalog <- catalog |> 
    dplyr::filter(!is.na(SITE_ID)) |>
    dplyr::arrange(location, solarday)
  
  message("Built catalog with ", nrow(catalog), " entries")
  message("Locations: ", length(unique(catalog$location)))
  message("Date range: ", min(catalog$solarday), " to ", max(catalog$solarday))
  
  catalog
}
#' Audit catalog against locations table
#'
#' Helper to inspect what's in S3 vs what's defined in locations
#'
#' @param catalog_table Catalog from build_catalog_from_s3()
#' @param locations_table Valid locations (from tabl)
#' @return List with audit results
audit_catalog_locations <- function(catalog_table, locations_table) {
  
  catalog_locs <- unique(catalog_table$location)
  defined_locs <- unique(locations_table$location)
  
  list(
    in_catalog_not_defined = setdiff(catalog_locs, defined_locs),
    in_defined_not_catalog = setdiff(defined_locs, catalog_locs),
    in_both = intersect(catalog_locs, defined_locs),
    summary = data.frame(
      in_catalog = length(catalog_locs),
      in_definitions = length(defined_locs),
      orphaned_in_s3 = length(setdiff(catalog_locs, defined_locs)),
      missing_imagery = length(setdiff(defined_locs, catalog_locs))
    )
  )
}


write_react_json <- function(viewtable) {
  collection <- "sentinel-2-c1-l2a"
  
  url_template <- 
    '"url": {
           "view_q128": "https://projects.pawsey.org.au/estinel/<<IMAGE_ID>>_q128.png",
           "view_hist": "https://projects.pawsey.org.au/estinel/<<IMAGE_ID>>_histeq.png",
           "view_stretch": "https://projects.pawsey.org.au/estinel/<<IMAGE_ID>>_stretch.png"
         }, 
        "thumbnail": {
           "view_q128": "https://projects.pawsey.org.au/estinel/thumbs/<<IMAGE_ID>>_q128.png",
           "view_hist": "https://projects.pawsey.org.au/estinel/thumbs/<<IMAGE_ID>>_histeq.png",
           "view_stretch": "https://projects.pawsey.org.au/estinel/thumbs/<<IMAGE_ID>>_stretch.png"
         }'
  
  image_template <- 
    '{
          "id": "<<IMAGE_ID>>",
                   <<IMAGE_URL>>,
          "download": "https://projects.pawsey.org.au/estinel/<<IMAGE_ID>>.tif",
          "date": "<<DATE>>"
}'
  
  # UPDATED: Added purpose array
  site_template <- 
    '{
    "id": "<<SITE_ID>>",
    "name": "<<SITE_NAME>>",
    "purpose": <<PURPOSE_JSON>>,
    "images": [
      %s
    ]
}'
  
  locations <- unique(viewtable$location)
  sites <- character()
  
  for (j in 1:length(locations)) {
    
    imagetable <- dplyr::filter(viewtable, location == locations[j])
    SITE_NAME <- imagetable$location[1]
    SITE_ID <- imagetable$SITE_ID[1]
    
    # ADDED: Parse CSV string to JSON array
    PURPOSE_JSON <- if ("purpose" %in% names(imagetable) && !is.na(imagetable$purpose[1])) {
      # Split CSV string: "base,heard" -> c("base", "heard")
      purpose_vec <- trimws(strsplit(imagetable$purpose[1], ",")[[1]])
      # Convert to JSON array: ["base", "heard"]
      jsonlite::toJSON(purpose_vec, auto_unbox = FALSE)
    } else {
      '["none"]'  # Default JSON array
    }
    
    images <- character()
    for (i in 1:nrow(imagetable)) {
      DATE <- format(as.Date(imagetable$solarday[i]))
      SDATE <- format(as.Date(imagetable$solarday[i]), "%Y/%m/%d")
      
      IMAGE_ID <- glue::glue("{collection}/{SDATE}/{SITE_NAME}_{DATE}")
      IMAGE_URL <- glue::glue(url_template, .open = "<<", .close = ">>")
      
      images <- paste0(c(images, glue::glue(image_template, .open = "<<", .close = ">>")), collapse = ",\n")
    }
    
    sites <- paste0(c(sites, glue::glue(sprintf(site_template, images), .open = "<<", .close = ">>")), collapse = ",\n")
  }
  
  jstext <- sprintf('{
"locations": [
 %s
]
        }', sites)
  
  outfile <- "inst/docs/image-catalog.json"
  writeLines(jstext, outfile)
  outfile
}


#' Upload catalog JSON to GitHub Release with compression
#'
#' @param json_file Character. Path to catalog JSON
#' @param repo Character. GitHub repo (owner/name)
#' @param tag Character. Release tag (default: "catalog-data")
#' @return Logical. TRUE if successful
upload_catalog_to_release <- function(json_file, 
                                      repo = "mdsumner/estinel",
                                      tag = "catalog-data") {
  
  if (!file.exists(json_file)) {
    stop("Catalog file not found: ", json_file)
  }
  
  # Compress the JSON (40MB → ~2-5MB typically)
  compressed_file <- paste0(tools::file_path_sans_ext(json_file), ".json.gz")
  
  message("Compressing catalog: ", json_file)
  con_in <- file(json_file, "r")
  con_out <- gzfile(compressed_file, "w")
  writeLines(readLines(con_in), con_out)
  close(con_in)
  close(con_out)
  
  # Get file sizes
  original_size <- file.size(json_file) / 1024^2  # MB
  compressed_size <- file.size(compressed_file) / 1024^2  # MB
  compression_ratio <- (1 - compressed_size/original_size) * 100
  
  message(sprintf("Original: %.1f MB, Compressed: %.1f MB (%.1f%% smaller)", 
                  original_size, compressed_size, compression_ratio))
  
  # Upload to GitHub Release
  message("Uploading to GitHub Release: ", tag)
  
  tryCatch({
    piggyback::pb_upload(
      file = compressed_file,
      repo = repo,
      tag = tag,
      overwrite = TRUE  # Replace existing file
    )
    
    message("✓ Upload successful!")
    message("Download URL: https://github.com/", repo, "/releases/download/", tag, "/", basename(compressed_file))
    
    # Clean up compressed file
    unlink(compressed_file)
    
    TRUE
  }, error = function(e) {
    warning("Upload failed: ", e$message)
    unlink(compressed_file)
    FALSE
  })
}


# ==============================================================================
# NON-BRANCHED VERSIONS - Process full tables
# ==============================================================================

#' Read all markers at once (non-branched version)
read_markers_all <- function(bucket, spatial_window) {
  set_gdal_envs()
  
  markers_list <- vector("list", nrow(spatial_window))
  
  for (i in seq_len(nrow(spatial_window))) {
    site_id <- spatial_window$SITE_ID[i]
    location <- spatial_window$location[i]
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
          location = location,
          last_solarday = as.Date(NA),
          stringsAsFactors = FALSE
        )
      })
    } else {
      markers_list[[i]] <- data.frame(
        SITE_ID = site_id,
        location = location,
        last_solarday = as.Date(NA),
        stringsAsFactors = FALSE
      )
    }
  }
  
  dplyr::bind_rows(markers_list)
}


#' Prepare chunked queries for ALL locations at once
#' 
#' Takes full spatial_window and markers tables, returns expanded table
#' with one row per location-chunk combination.
prepare_queries_chunked_all <- function(spatial_window, 
                                        markers = NULL, 
                                        default_start = "2015-01-01", 
                                        now = Sys.time(),
                                        chunk_threshold_days = 365) {
  
  # Join markers to spatial_window
  if (!is.null(markers) && nrow(markers) > 0) {
    query_table <- dplyr::left_join(spatial_window, markers, 
                                    by = c("SITE_ID", "location"))
  } else {
    query_table <- spatial_window
    query_table$last_solarday <- as.Date(NA)
  }
  
  # Set start date: use marker if exists, otherwise default_start
  query_table$start_solarday <- dplyr::if_else(
    is.na(query_table$last_solarday),
    as.Date(default_start),
    pmax(query_table$last_solarday + 1, as.Date("2024-01-01"))
  )
  
  end_solarday <- as.Date(now) + 1
  
  # Calculate timezone buffers
  query_table$offset_hours <- query_table$lon / 15
  query_table$buffer_hours <- abs(query_table$offset_hours) + 12
  
  # Calculate days span to determine chunking need
  query_table$days_span <- as.numeric(end_solarday - query_table$start_solarday)
  query_table$needs_chunking <- query_table$days_span > chunk_threshold_days
  
  # Process each location, expanding chunks as needed
  result_list <- vector("list", nrow(query_table))
  
  for (i in seq_len(nrow(query_table))) {
    row <- query_table[i, ]
    
    if (!row$needs_chunking) {
      # No chunking needed - single query
      row$query_start_utc <- as.POSIXct(row$start_solarday, tz = "UTC") - 
        (row$buffer_hours * 3600)
      row$query_end_utc <- as.POSIXct(end_solarday + 1, tz = "UTC") + 
        (row$buffer_hours * 3600)
      row$start <- format(row$query_start_utc, "%Y-%m-%dT%H:%M:%SZ")
      row$end <- format(row$query_end_utc, "%Y-%m-%dT%H:%M:%SZ")
      row$chunk_id <- 1L
      result_list[[i]] <- row
      
    } else {
      # Chunking needed - create yearly chunks
      start_date <- row$start_solarday
      chunk_starts <- seq(start_date, end_solarday, by = "1 year")
      
      if (chunk_starts[length(chunk_starts)] < end_solarday) {
        chunk_starts <- c(chunk_starts, end_solarday)
      }
      
      chunk_rows <- vector("list", length(chunk_starts) - 1)
      
      for (j in seq_len(length(chunk_starts) - 1)) {
        chunk_row <- row
        chunk_start <- chunk_starts[j]
        chunk_end <- min(chunk_starts[j + 1] - 1, end_solarday)
        
        chunk_row$query_start_utc <- as.POSIXct(chunk_start, tz = "UTC") - 
          (chunk_row$buffer_hours * 3600)
        chunk_row$query_end_utc <- as.POSIXct(chunk_end + 1, tz = "UTC") + 
          (chunk_row$buffer_hours * 3600)
        chunk_row$start <- format(chunk_row$query_start_utc, "%Y-%m-%dT%H:%M:%SZ")
        chunk_row$end <- format(chunk_row$query_end_utc, "%Y-%m-%dT%H:%M:%SZ")
        chunk_row$chunk_id <- as.integer(j)
        
        chunk_rows[[j]] <- chunk_row
      }
      
      result_list[[i]] <- dplyr::bind_rows(chunk_rows)
    }
  }
  
  # Combine all and clean up
  result <- dplyr::bind_rows(result_list)
  result$needs_chunking <- NULL
  result$days_span <- NULL
  
  message("Prepared ", nrow(result), " queries for ", 
          length(unique(result$location)), " locations")
  
  result
}


#' Build STAC query URLs for full table
getstac_query_adaptive_all <- function(query_specs, provider, collection, limit = 300) {
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
  
  message("Built ", nrow(query_specs), " STAC queries")
  query_specs
}

