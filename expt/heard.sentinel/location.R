## get a line from authority (here a contour)
##gdal raster contour --levels 1 /vsicurl/https://github.com/mdsumner/ibcso-cog/raw/refs/heads/main/IBCSO_v2_ice-surface_cog.tif coastline.fgb
## gdal vector reproject --dst-crs "EPSG:3031" coastline.fgb coastline.parquet

## create a set of tiles (all in 3031 ? or all local? or maybe MGRS?)
library(terra)
l <- vect("coastline.parquet")
l <- crop(l, ext(0, 4e6, -Inf, Inf))
r <- rast(align(ext(l), 3000), res = 3000)  ## note alignment to 0,0 on grain
cell <- unique(terra::cells(r, l)[,2])
r[cell] <- 1
p <- as.polygons(r, aggregate = F)
p$cell <- cell
length(cell)
##[1] 7757

heard <- do.call(rbind, lapply(split(p, 1:nrow(p)), \(.x) as.vector(ext(.x))))

library(dplyr)
tabl <- tibble::as_tibble(setNames(as.data.frame(heard), c("xmin", "xmax", "ymin", "ymax"))) |>
  mutate(cell = cp$cell, location = sprintf("heard_%i", cell))
arrow::write_parquet(tabl, "heardcoast.parquet")
