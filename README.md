# emperor.sentinel

Just notes for now. Get imagery around documented colony. 

```R
gdalim <- function(..., dimension = c(512, 0), extent = NULL, crs = NULL, res = NULL) {
  if (!is.null(res)) dimension <- NULL
  args <- list(...)
  #nms <- names(args)
  
  vals <- lapply(args, \(.x) vapour::gdal_raster_data(.x, target_dim = dimension, target_ext = extent, target_crs = crs, target_res = res))
  out <- vals[[1L]]
  out[[1L]] <- colourvalues::convert_colours(scales::rescale(do.call(cbind, lapply(vals, "[[", 1L)), c(0, 255)))
  out
}

## https://data.aad.gov.au/dataset/e73bc625-383f-460a-8a91-3d9bd96bbfb7
emperor <- structure(list(Colony.name = c("Umebosi", "Casey Bay", "Amundsen Bay", 
"Kloa Point", "Fold Island", "Taylor Glacier (ASPA 101)", "Auster", 
"Flutter", "Amanda Bay (ASPA 169)", "West Ice Shelf", "Barrier Bay", 
"Karelin Bay", "Posadowsky Bay (Gauss)", "Haswell Island (ASPA 127)", 
"Shackleton Ice Shelf", "Bowman Island", "Peterson Bank", "Cape Poinsett", 
"Sabrina Coast", "Porpoise Bay", "Dibble Glacier", "Pointe Géologie (ASPA 120)", 
"Mertz Glacier", "Ninnis Bank", "Davies Bay", "Yule Bay"), Lat = c(-68.048, 
-67.311, -66.785, -66.642, -67.312, -67.454, -67.409, -67.882, 
-69.274, -66.261, -67.165, -66.4, -66.131, -66.533, -64.919, 
-65.238, -65.865, -65.816, -66.155, -66.264, -65.948, -66.675, 
-67.268, -66.78, -69.333, -70.724), Long = c(43.074, 46.975, 
50.56, 57.28, 59.322, 60.883, 63.96, 69.697, 76.827, 81.484, 
81.951, 85.359, 89.82, 93.009, 95.93, 103.197, 110.241, 113.284, 
121.062, 130.066, 134.727, 140.016, 146.003, 149.671, 158.439, 
166.537), Date = c("13-Sep-22", "13-Sep-22", "3-Sep-22", "21-Oct-22", 
"22-Nov-22", "5-Sep-22", "9-Sep-22", "9-Sep-22", "7-Sep-22", 
"11-Nov-22", "3-Sep-21", "15-Oct-22", "29-Dec-22", "30-Aug-22", 
"30-Aug-22", "7-Oct-22", "11-Sep-22", "15-Sep-22", "13-Oct-22", 
"10-Apr-22", "11-Sep-22", "19-Oct-22", "5-Sep-22", "9-Sep-22", 
"11-Sep-22", "29-Oct-22"), Image = c("Sentinel2", "Sentinel2", 
"Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", 
"Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", 
"Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", 
"Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2", 
"Sentinel2", "Sentinel2", "Sentinel2", "Sentinel2"), Comment = c("often very close to icebergs at northern end of ice tongue of a small unnamed glacier west of Umebosi Rock", 
"at western side of Casey Bay, in small embayment south of Felton Head at eastern side of Tange Peninsula", 
"on eastern end of compression zone; at times, colony splits into several groups", 
"colony tends to be right up against the coast line", "as always, south of Fold Island", 
"as usual on rock outcrop", "among grounded icebergs; several groups stretched over ~1 km ", 
" At eastern side of the Bjerkø Peninsula", "In usual location between Reel Island and the Flatness Ice Tongue. Right up against the ice tongue.", 
"At northern side of iceberg D-15A. May split into two groups that are a few kilometres apart", 
"Up to 2021, used to be located on fast ice between West Ice Shelf and iceberg D-15B. May no longer be there.", 
"central part of the West Ice Shelf; colony often near ice edge", 
"on fast ice 60-70 km north of coast", "ASPA managed by Russia; colony usually near Haswell Island but location varies between years and depends on position and number of local icebergs", 
"up agaist the northern edge of iceberg C13; a second group is just over 3 km farther west; at times, penguins move onto the iceberg", 
"at northern side of the island, very close to the island's coast", 
"on western side of fast ice north of Casey station, ~40 km off the coast. In 2022, 2 more groups within 5 km radius (mainly E) of main group", 
"at eastern side of cape, usually close to the ice edge", "on the western side of the Dalton Iceberg Tongue, around 50 km from the coast", 
"on fast ice of southwestern part of the Blodgett Iceberg Tongue; second group ~1 km from main group", 
"in southwestern section of Dibble Iceberg Tongue and just north of Dibble Glacier;  often divides into several groups, in 2022, 4 more groups within 6 km radius of main group", 
"Adélie Land, French Antarctic Territory", "on eastern side of Mertz Glacier, usually very close to the ice cliffs and near the ice edge.  Colony may split into several groups.", 
"on eastern side of Ninnis Glacier Iceberg Tongue, ~175 km north of Horn Bluff", 
"Colony location can vary slightly from year to year, but tends to occupy southern part of Davies Bay. Usually east of McLoyd Glacier and north of Arthuson Ridge.", 
"in the western part of Yule Bay, south of Missen Ridge and east of the Kirkby Glacier. Ross Dependcy, New Zealand."
)), class = "data.frame", row.names = c(NA, -26L))

emperor$date <- as.Date(strptime(emperor$Date, "%d-%b-%y"))

j <- 3

ds <- dev.size("px")[1] * 2
b <- ds/(1852 * 60)
a <- b * 1/cos(emperor$Lat[j] * pi/180)
pt <- cbind(emperor$Long[j], emperor$Lat[j])
ex <- rep(pt, each = 2) + c(-1, 1, -1, 1) * c(a, a, b, b)
bbox <- paste0(ex[c(1, 3, 2, 4)], collapse = ",")
laea <- sprintf("+proj=laea +lon_0=%f +lat_0=%f", pt[1], pt[2])
pex <- as.vector(terra::ext(terra::project(terra::rast(terra::ext(ex), crs = "OGC:CRS84"), laea)))


cnt <- 0
#cnt <- cnt + 1
date <- as.Date(emperor$date[j]) + cnt

#date <- as.Date("2021-09-13")
x <- readLines(glue::glue("https://earth-search.aws.element84.com/v1/search?limit=500&collections=sentinel-2-l2a&datetime={date-15}T00:00:00Z%2F{date+15}T00:00:00Z&bbox={bbox}"))
js <- jsonlite::fromJSON(x)
if (!is.null(js$features$assets)) {
i <- 1
x1 <- dsn::vsicurl(js$features$assets$red$href[i])
x2 <- dsn::vsicurl(js$features$assets$green$href[i])
x3 <- dsn::vsicurl(js$features$assets$blue$href[i])
x <- gdalim(red = x1, green = x2, blue = x3, crs = laea, extent = pex, res = 10)
ximage::ximage(x, asp = 1)
title(date)


}
