#if (FALSE) {
#   #https://custom-scripts.sentinel-hub.com/custom-scripts/sentinel-2/scene-classification/
#   # 2       3       5       6       8       9      10      11 
#   # 232342   44301   83063  160075 4663921 6138614 2599653 2277939 
#   # 
#   # Value	Scene Classification	HTLM color code	Color
#   # 0	No Data (Missing data)	#000000	
#   # 1	Saturated or defective pixel	#ff0000	
#   # 2	Topographic casted shadows (called "Dark features/Shadows" for data before 2022-01-25)	#2f2f2f	
#   # 3	Cloud shadows	#643200	
#   # 4	Vegetation	#00a000	
#   # 5	Not-vegetated	#ffe65a	
#   # 6	Water	#0000ff	
#   # 7	Unclassified	#808080	
#   # 8	Cloud medium probability	#c0c0c0	
#   # 9	Cloud high probability	#ffffff	
#   # 10	Thin cirrus	#64c8ff	
#   # 11	Snow or ice	#ff96ff
#   # 
#"#000000", "#ffffff"
#tab <- cbind(1:12, scales::rescale(t(col2rgb(hcl.colors(12)))))
col <- readr::read_csv("inst/extdata/SCL_pal.csv")
tab <- cbind(col[[1]], scales::rescale(t(col2rgb(col$col))))
  xs <- NULL#320
  ys <- NULL#320
   library(targets)
   tar_load(images)
   tar_load(cloud_tifs)
 #par(mfrow = c(12, 8), mar = rep(0, 4))
  mfrow <-  n2mfrow(length(images) * 2) 
  if (mfrow[1] %% 2 == 1 ) {
    mfrow[1] <- mfrow + 1
  }
par(mfrow = c(mfrow), mar = rep(0, 4))
for (i in seq_along(images) ) {
gdalraster::plot_raster(images[[i]], xsize = xs, ysize = ys, axes = F)
gdalraster::plot_raster(new(gdalraster::GDALRaster, cloud_tifs[[i]][[1]]), col_tbl = tab, xsize = xs, ysize = ys, axes = F)
}
 
# 
# }
#  
