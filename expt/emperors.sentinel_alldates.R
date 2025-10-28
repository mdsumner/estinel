#pt <- cbind(86.53, -66.08); 


dates <- c(as.Date("2015-01-01"), Sys.Date())

bf <- 200
mksquash <- function(from = c(1000, 15000)) {
  function(x) {
  val <- scales::rescale(x, to = c(0, 1), from = from)
  val <- x
  val[val < 0] <- 0
  val[val > 1] <- 1
  val
  }
}


# squash <- function(x) {
#   val <- x
#   val[val < 0] <- 0
#   val[val > 1] <- 1
#   val
# }

Sys.setenv("GDAL_DISABLE_READDIR_ON_OPEN" = "EMPTY_DIR")


tabl <- rbind(data.frame(location = "Davis", lon = c(77 + 58/60 + 3/3600), lat = -(68 + 34/60 + 36/3600)), 
              data.frame(location = "Casey", 
                    lon = cbind(110 + 31/60 + 36/3600), lat =  -(66 + 16/60 + 57/3600)))
# tabl <- readxl::read_excel("Emperor penguin colony locations_all_2024.xlsx", skip = 2) |> 
#  dplyr::rename(location = colony, lon = long)
localproj <- function(x) {
  sprintf("+proj=laea +lon_0=%f +lat_0=%f", x[1], x[2])
}

for (j in seq_len(nrow(tabl))) {
    pt <- cbind(tabl$lon[j], tabl$lat[j])
    prj <- localproj(pt)
    
    location <- tabl$location[j]
    ex <- c(-3000, 3000, -3000, 3000)
    llex <- reproj::reproj_extent(ex, "EPSG:4326", source = prj)
    #dates <- range(as.Date(tabl$date[i]) + c(-2, 0, 2))
    qu <- sds::stacit(llex, dates)
    json <- jsonlite::fromJSON(qu)
    alldates <-as.Date(json$features$properties$datetime)
    (udate <- unique(alldates))
    udate <- sort(udate)
for (i in seq_len(length(udate))) {

  idx <- alldates == udate[i]
  red <- sprintf("/vsicurl/%s", json$features$assets$red$href[idx])
  green <- sprintf("/vsicurl/%s", json$features$assets$green$href[idx])
  blue <- sprintf("/vsicurl/%s", json$features$assets$blue$href[idx])
  cloud <- sprintf("/vsicurl/%s", json$features$assets$scl$href[idx])
  
  ccloud <- vapour::gdal_raster_data(cloud, target_crs= prj, target_res = 10, target_ext = c(-bf, bf, -bf, bf)*2)
  if (!all(is.nan(ccloud[[1]])) && mean(ccloud[[1]] %in%  c(0, 1, 2, 3, 8, 9, 10)) < .4) {
  rred <- vapour::gdal_raster_data(red, target_crs= prj, target_res = 10, target_ext = ex)
  ggreen <- vapour::gdal_raster_data(green, target_crs= prj, target_res = 10, target_ext = ex)
  bblue <- vapour::gdal_raster_data(blue, target_crs= prj, target_res = 10, target_ext = ex)
mtrx <- function(x) {
  as.vector(matrix(x[[1]], attr(x, "dimension")[2], byrow = TRUE))
}
  col0 <- cbind(mtrx(rred), mtrx(ggreen), mtrx(bblue))
  squash <- mksquash(quantile(col0, c(0.2, .75)))
  col <- squash(col0)
  #col <- scales::rescale(col0)
  dm <- attr(rred, "dimension")
  label <- sprintf("%s: %s", location, format(as.Date(udate[i])))
  #png(sprintf("%s.png", gsub(" ", "_", label)), width = 1024, height = 1024)
  ximage::ximage(array(col, c(attr(rred, "dimension")[2:1], 3L)), ex, asp = 1)
  title(label)

  rect(-bf, -bf, bf, bf, lty = 2, border = "hotpink", col = NA)
  points(cbind(c(-bf, 0, bf, 0), c(0, -bf, 0, bf)), pch = "+")
  #dev.off()
  #maxar <- vapour::gdal_raster_nara(sds::wms_googlehybrid_tms(), target_crs= prj, target_res = .5, target_ext = c(-bf, bf, -bf, bf)*2)
  #ximage::ximage(maxar)
  }
}
    
}
