
library(dplyr)
library(targets)
tar_load(result)    

fi_rast <- function(x) {
  terra::rast(x$outfile[1])
}
stretch_hist <- function(x, ...) {
  ## stretch as if all the pixels were in the same band (not memory safe)
    rv <- terra::stretch(terra::rast(matrix(terra::values(x))), histeq = TRUE, maxcell = terra::ncell(x)*3)
    ## set the values to the input, then stretch to 0,255
    terra::stretch(terra::setValues(x, c(terra::values(rv))), histeq = FALSE, maxcell = terra::ncell(x))
}
fi_plot <- function(x, shist = TRUE) {
  r <- fi_rast(x)
  if (shist) r <- stretch_hist(r)
  terra::plotRGB(r, stretch = TRUE)
}
cl <- function(x) dsn::vsicurl(x)
noscale <- function(x) sprintf("vrt://%s?unscale=false", cl(x))
mkwarp <- function(x, res = 20, fex = 1) {
  ex <- unlist(x$assets[[1L]][1L, c("xmin", "xmax", "ymin", "ymax")]) * fex

  crs <- x$assets[[1]]$crs[1L]
  print(crs)
  function(x) {
    vapour::gdal_raster_dsn(noscale(x), target_ext = ex,  target_crs = crs, target_res = rep(res, length.out = 2L))[[1]]
  }
}
#warp <- mkwarp(fi)
#warp(fi$outfile[1L])

get_red <- function(x) x$assets[[1L]]$red
get_green <- function(x) x$assets[[1L]]$green
get_blue <- function(x) x$assets[[1L]]$blue
fi_rgb <- function(x, fex = 1) {
  rgb <- list(red = get_red(x), green = get_green(x), blue = get_blue(x))

  warp <- mkwarp(x[1L, ], fex = fex)
  #print(rgb)
  terra::rast(unlist(lapply(rgb, warp)), raw = TRUE)
}

fi_vrtility <- function(x) {
  library(vrtility)
 # mirai::daemons(24)
  
  bbox <- unlist(x$assets[[1]][1L, c("llxmin", "llymin", "llxmax", "llymax")])
  print(bbox)
  te <- bbox_to_projected(bbox)
  trs <- attr(te, "wkt")
  
  s2_stac <- stac_query(
    bbox = bbox,
    start_date = format(as.Date(x$solard)-1, "%Y-%m-%d"),
    end_date = format(as.Date(x$solard) + 1, "%Y-%m-%d"),
    stac_source = "https://earth-search.aws.element84.com/v1",
    collection = "sentinel-2-c1-l2a",
    #stac_source = "https://planetarycomputer.microsoft.com/api/stac/v1/",
    #collection = "hls2-s30",
    #max_cloud_cover = 100,
    #assets = c("B02", "B03", "B04", "B8A", "Fmask"), 
    assets = c("red", "green", "blue", "scl")
  )
  # number of items:
  length(s2_stac$features)
  #> [1] 10
  
  
    median_composite <- vrt_collect(s2_stac) |>
      # vrt_set_maskfun(
      #   mask_band = "Fmask",
      #   mask_values = c(0, 1, 2, 3),
      #   build_mask_pixfun = build_bitmask()
      # ) |>
      vrt_warp(t_srs = trs, te = te, tr = c(20, 20)) |>
      #vrt_stack() |>
      #vrt_set_py_pixelfun(pixfun = median_numpy()) |>
      vrt_compute(
        engine = "gdalraster"
      )
  median_composite
}


result <- filter(result, location == "Macquarie")
fi <- sample_n(result, 1L)
xm <- fi_vrtility(fi)



r <- fi_rgb(fi, fex = 1)
library(terra)
par(mfrow = c(2, 2))
plotRGB(r, stretch = TRUE)
plotRGB(stretch_hist(rast(fi$outfile)))
#plotRGB(stretch_hist(rast(fi$outfile)), stretch = F)
#plot_raster_src(xm[1], 3:1, rgb_trans = "hist")
plotRGB(stretch_hist(rast(xm)[[3:1]]))
plot_raster_src(xm, 3:1, rgb_trans = "linear")

