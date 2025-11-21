pq <- "https://github.com/maawoo/sentinel-2-grid-geoparquet/raw/refs/heads/main/sentinel-2-grid.parquet"
d <- arrow::read_parquet(pq)
## we'll assume they did this right, and just use a flag
d2 <- arrow::read_parquet("https://github.com/maawoo/sentinel-2-grid-geoparquet/raw/refs/heads/main/sentinel-2-grid_LAND.parquet")
d$landflag <- d$tile %in% d2$tile
## they store python code in a table for some reason ...
utm <- read.csv(header = F, colClasses = "numeric", text = gsub("\\(", "", d$utm_bounds))
d$zone <- substr(d$tile, 1, 2)
d$xmin <- utm[[1]]
d$ymin <- utm[[2]]
d$xmax <- utm[[3]]
d$ymax <- utm[[4]]

d$latband <- substr(d$tile, 3, 3)
sample(d$tile, 10)
mgrslat <- function() {
  setdiff(LETTERS[3:25], c("I", "X"))
}
vaster::plot_extent
qutemplate <-  "https://earth-search.aws.element84.com/v1/search?collections=sentinel-2-c1-l2a&%s&datetime=2025-01-01T00:00:00Z/2025-06-11T23:59:59Z&limit=1" 
tilequery <- 'query={"grid:code":{"eq":"MGRS-55GCN"}}'
qu <- sprintf(qutemplate, tilequery)
jsonlite::fromJSON(URLencode(qu))  
par(mfrow = c(2, 60), mar = c(0, .2, 0, .2))
for (zone in 1:60) {
  d0 <- d[as.numeric(d$zone) == zone & d$latband > "N" , ]
  pe(d0[d0$landflag, c("xmin", "xmax", "ymin", "ymax")], xlab = "", ylab = "")
}

for (zone in 1:60) {
  d0 <- d[as.numeric(d$zone) == zone & d$latband <= "N" , ]
  pe(d0[d0$landflag, c("xmin", "xmax", "ymin", "ymax")], xlab = "", ylab = "")
}







