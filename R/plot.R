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
pl <- function(...) {x <- dplyr::sample_n(tar_read(viewtable) |> dplyr::filter(clear_test < .6, location == "Macquarie_Island_Station"), 1); 
terra::plotRGB(stretch_q(terra::rast(x$outfile), ...), smooth = FALSE); x}

sentinel_palette <- function() {
  as.data.frame(list(value = 0:11, class = c("No Data (Missing data)", "Saturated or defective pixel", 
                                                   "Topographic casted shadows (called Dark features/Shadows for data before 2022-01-25)", 
                                                   "Cloud shadows", "Vegetation", "Not-vegetated", "Water", "Unclassified", 
                                                   "Cloud medium probability", "Cloud high probability", "Thin cirrus", 
                                                   "Snow or ice"), col = c("#000000", "#ff0000", "#2f2f2f", "#643200", 
                                                                           "#00a000", "#ffe65a", "#0000ff", "#808080", "#c0c0c0", "#ffffff", 
                                                                           "#64c8ff", "#ff96ff")))
  
}
 pl2 <- function(...) {
  x <- dplyr::sample_n(tar_read(viewtable), 1) # |> 
                         #dplyr::filter(clear_test < .6, location == "Macquarie_Island_Station"), 1); 
  op <- par(mfrow = c(1, 2))
cl <- sentinel_palette()
r <- terra::rast(x$scl_tif)
coltab(r) <- dplyr::transmute(cl, value, col)
levels(r) <- dplyr::transmute(cl, ID = value, category = class)

terra::plot(r)
terra::plot(r * 0)
terra::plotRGB(stretch_q(terra::rast(x$outfile), ...), smooth = FALSE, add = TRUE); 

par(op)
x
}


plold <- function(x) {
  if (missing(x)) x <- dplyr::sample_n(viewtable, 1); 
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
stretch_hist <- function(x, ...) {
  ## stretch as if all the pixels were in the same band (not memory safe)
  rv <- terra::stretch(terra::rast(matrix(terra::values(x))), histeq = TRUE, maxcell = terra::ncell(x))
  ## set the values to the input, then stretch to 0,255
  terra::stretch(terra::setValues(x, c(terra::values(rv))), histeq = FALSE, maxcell = terra::ncell(x))
}
stretch_q <- function(xx, n = 128L) {
  q <- quantile(terra::values(xx), seq(0, 1, length.out = n), type = 1, names = FALSE, na.rm = TRUE)
  terra::stretch(terra::setValues(xx, q[cut(terra::values(xx), unique(q), labels = F, include.lowest = T)]))
}
