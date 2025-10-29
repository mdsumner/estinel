
extent_tile <- function(sentinelurl) {
  tile <- gsub("^T", "", sapply(strsplit(dirname(sentinelurl), "_"), "[", 2))
  print(tile)
  pt <- mgrs::mgrs_to_latlng(tile)
  N <- substr(tile, 3, 3) >= "N"
  code <- c(7, 6)[N + 1]
  zone <- substr(tile, 1, 2)
  xy <- reproj::reproj_xy(as.matrix(pt[, c("lng", "lat")]), sprintf("EPSG:32%i%s", code, zone), source = "EPSG:4326")
  rep(xy, each = 2) + c(0, 109800, -9780, 100020)
}


# im <- "https://e84-earth-search-sentinel-data.s3.us-west-2.amazonaws.com/sentinel-2-c1-l2a/43/F/CA/2024/5/S2B_T43FCA_20240524T044328_L2A/B04.tif"
# 
# im <- sample(images_table$red, 1)
# extent_tile(im)
# new(gdalraster::GDALRaster, sprintf("/vsicurl/%s", im))$bbox()[c(1, 3, 2, 4)]
