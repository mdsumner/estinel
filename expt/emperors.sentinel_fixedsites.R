library(jsonlite)
#pt <- cbind(60.883, -67.452	) ##lon,lat
#pt <- cbind(86.53, -66.08); dates <- c("2021-11-17", "2021-11-19")  ## vanhoeffen
#pt <- cbind(149.534, -66.827); dates <- c("2024-09-16", "2024-09-20") ## ninnis

tabl <- readxl::read_excel("Emperor penguin colony locations_all_2024.xlsx", skip = 2)

for (i in seq_len(nrow(tabl))) {

  pt <- cbind(tabl$long[i], tabl$lat[i])
  dates <- range(as.Date(tabl$date[i]) + c(-2, 0, 2))
ex <- rep(pt, each = 2) + c(-2.45, 2.45, -1, 1) * .03
qu <- sds::stacit(ex, dates)
json <- fromJSON(qu)
##json <- fromJSON("https://earth-search.aws.element84.com/v1/search?collections=sentinel-2-c1-l2a&bbox=60.873,-67.462,60.893,-67.442&datetime=2021-11-16T00:00:00Z/2021-11-23T23:59:59Z&limit=1000")
(udate <- unique(as.Date(json$features$properties$datetime)))
red <- sprintf("/vsicurl/%s", json$features$assets$red$href)
green <- sprintf("/vsicurl/%s", json$features$assets$green$href)
blue <- sprintf("/vsicurl/%s", json$features$assets$blue$href)

localproj <- function(x) {
  sprintf("+proj=laea +lon_0=%f +lat_0=%f", x[1], x[2])
}
prj <- localproj(pt)
pex <- reproj::reproj_extent(ex, prj, source = "EPSG:4326")


rred <- vapour::gdal_raster_data(red, target_crs= prj, target_res = 10, target_ext = pex)
ggreen <- vapour::gdal_raster_data(green, target_crs= prj, target_res = 10, target_ext = pex)
bblue <- vapour::gdal_raster_data(blue, target_crs= prj, target_res = 10, target_ext = pex)
squash <- function(x, from = c(0, 15000)) {
 # val <- scales::rescale(x, to = c(0, 1), from = from)
  val <- x
  val[val < 0] <- 0
  val[val > 1] <- 1
  val
}
dm <- attr(rred, "dimension")
col <- cbind(matrix(squash(rred[[1]]), dm[2], byrow = TRUE), matrix(squash(ggreen[[1]]), dm[2], byrow = TRUE), 
             matrix(squash(bblue[[1]]), dm[2], byrow = TRUE))
label <- sprintf("%s: %s", tabl$colony[i], format(as.Date(tabl$date[i] )))
png(sprintf("%s.png", gsub(" ", "_", label)), width = 1024, height = 1024)
ximage::ximage(array(col, c(attr(rred, "dimension")[2:1], 3L)), pex, asp = 1)
title(label)
bf <- 200
rect(-bf, -bf, bf, bf, lty = 2, border = "hotpink", col = NA)
points(cbind(c(-bf, 0, bf, 0), c(0, -bf, 0, bf)), pch = "+")
dev.off()

}
