# library(gdalraster)
# src <- "/vsis3/idea-sentinel2-locations/"
# Sys.setenv("AWS_VIRTUAL_HOSTING" = "NO")
# Sys.setenv("AWS_S3_ENDPOINT" = "https://projects.pawsey.org.au")
# 
# vsi_read_dir(src, recursive = T)

d <- arrow::read_parquet("files.parquet")

d$file <- d$url
d$source <- sprintf("/vsicurl/%s/%s", "https://projects.pawsey.org.au/idea-sentinel2-locations", d$file)
d$date <- as.Date(stringr::str_extract(d$file, "[0-9]{4}/[0-9]{2}/[0-9]{2}"))
last <- unlist(gregexpr("[0-9]{4}", basename(d$file)))
d$location <- substr(basename(d$file), 1, last-2)


library(dplyr)
distinct(d, location)
v <- d |> filter(location == "Auster", grepl("stretch.*tif$", file)) 
unlink("png0", recursive = T)
dir.create("png0")
library(terra)

v$outfile <-  sprintf("png0/files_%03i.png", 1:nrow(v))

outfun <- function(x) {
  grDevices::png(x$outfile, width = 800, height = 800)
  plotRGB(rast(x$source), asp = 1)
  dev.off()
  x$outfile
}
#options(parallelly.fork.enable = TRUE, future.rng.onMisuse = "ignore")
#library(furrr); plan(multicore, workers = 31)
library(purrr)
mirai::daemons(0)
mirai::daemons(31)
outpng <- map_chr(split(v, 1:nrow(v)), purrr::in_parallel(function(x) {
  grDevices::png(x$outfile, width = 800, height = 800)
  terra::plotRGB(terra::rast(x$source), asp = 1)
  grDevices::dev.off()
  x$outfile[1]
}))


gifski::gifski(outpng, width = 800, height = 800)
