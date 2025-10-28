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
source("R/gallery.R")

library(dplyr)
distinct(d, location)
#options(parallelly.fork.enable = TRUE, future.rng.onMisuse = "ignore")
#library(furrr); plan(multicore, workers = 31)
library(purrr)
mirai::daemons(0)
mirai::daemons(31)
unlink("gif", recursive = T)
dir.create("gif")
for (loc in  unique(d$location)) {
v <- d |> filter(location == loc, grepl("stretch.*tif$", file)) 
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
ndc2usr <- function(x) {
  grconvertX(x, "ndc", "user")
}
outpng <- map_chr(split(v, 1:nrow(v)), purrr::in_parallel(function(x) {

  grDevices::png(x$outfile, width = 800, height = 800)
  terra::plotRGB(terra::rast(x$source), asp = 1)
  rct <- grconvertX(c(.35, .35, .65, .65), "ndc", "user")
  pt <- grconvertX(c(.45, .45, .55, .55), "ndc", "user")
  text(grconvertX(.5, "ndc", "user"), grconvertY(.05, "ndc", "user"), sprintf("%s, %s", x$location[1], format(x$date[1])), col = "hotpink", cex = 1.4)
  text(grconvertX(.15, "ndc", "user"), grconvertY(.5, "ndc", "user"), sprintf("%s, %s", x$location[1], format(x$date[1])), col = "black", cex = 1.4)
  rect(rct[1], rct[2], rct[3], rct[4], lty = 2)
  points(expand.grid(pt[c(1, 3)], pt[c(2, 4)]), pch = "+", cex = 1)
  grDevices::dev.off()
  x$outfile[1]
}))
gallery("png0", pagefile = sprintf("gallery/%s.html", loc), overwrite = T)

gifski::gifski(outpng, width = 800, height = 800, gif_file = sprintf("gif/%s_%s.gif", loc, paste0(format(range(v$date)), collapse = "_")))
}