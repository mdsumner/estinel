## get a line from authority (here a contour)
##gdal raster contour --levels 1 /vsicurl/https://github.com/mdsumner/ibcso-cog/raw/refs/heads/main/IBCSO_v2_ice-surface_cog.tif l1.parquet

## create a set of tiles (all in 3031 ? or all local? or maybe MGRS?)
l <- vect("~/l.parquet")
l <- crop(l, ext(0, 4e6, -Inf, Inf))
r <- rast(align(ext(l), 3000), res = 3000)  ## note alignment to 0,0 on grain
cell <- unique(terra::cells(r, l)[,2])
r[cell] <- 1
p <- as.polygons(r, aggregate = F)
p$cell <- cell
length(cell)
##[1] 7757

## heard coastline at 3000m tiles, easy
cp <- crop(p, c(xmin = 3882000, xmax = 3921000, ymin = 1128000, ymax = 1221000))
heard <- do.call(rbind, lapply(split(cp, 1:nrow(cp)), \(.x) as.vector(ext(.x))))

library(dplyr)
tabl <- tibble::as_tibble(setNames(as.data.frame(heard), c("xmin", "xmax", "ymin", "ymax"))) |> 
  mutate(cell = cp$cell, location = sprintf("heard_%i", cell))
arrow::write_parquet(tabl, "heardcoast.parquet")  

