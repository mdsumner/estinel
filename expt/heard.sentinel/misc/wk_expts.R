
bb <- c(5e5,  5e5, 5e6, 5e6); src <- "+proj=laea +lat_0=-70"
dm <- c(64, 64) ## discretization
xl <- bb[c(1L, 3L)]
yl <- bb[c(2L, 4L)]
top <- cbind(xl, yl[2])
right <- cbind(xl[2], yl[2:1])[, 2:1]
bot <- cbind(xl[2:1], yl[1])
left <- cbind(xl[1], yl)[, 2:1]
xc <- seq(xl[1L], xl[2L], length.out = dm[1L] + 1L)
yc <- seq(yl[1L], yl[2L], length.out = dm[2L] + 1L)

## now we reproject and get the new extent
xy <- reproj::reproj_xy(cbind(x = xc, y = rep(yc, each = length(xc))), "EPSG:4326", source = src)
## don't ask , not right yet (see vaster::vaster_boundary)
cell <- c(seq_len(dm[1L] + 1),
          seq(dm[1L] + 1, by = dm[1] + 1, length.out = dm[2L] + 1),
          seq(prod(dm+1), by = -1, length.out = dm[1L]+1),
          seq(prod(dm+1) - dm[1L]- 1 + 1, by = -dm[1]-1, length.out = dm[2L]+1))
boundary <- xy[matrix(cell, dm[2] + 1, byrow = T), ]

bbox <- c(min(xy[,1], na.rm = TRUE),
          min(xy[,2], na.rm = TRUE),
          max(xy[,1], na.rm = TRUE),
          max(xy[,2], na.rm = TRUE))

plot(rct(bbox[1], bbox[2], bbox[3], bbox[4]))
points(xy, pch = ".")
