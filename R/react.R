write_react_site <- function(viewtable) {
collection <- "sentinel-2-c1-l2a"
SITE_ID_template <- "site_%04i"

image_template <- 
  '{
          "id": "<<IMAGE_ID>>",
          "url":       "https://projects.pawsey.org.au/estinel/<<IMAGE_ID>>.png",
          "thumbnail": "https://projects.pawsey.org.au/estinel/thumbs/<<IMAGE_ID>>.png",
          "download": "https://projects.pawsey.org.au/estinel/<<IMAGE_ID>>.tif",
          "date": "<<DATE>>"
}'


site_template <- 
  '{
    "id": "<<SITE_ID>>",
    "name": "<<SITE_NAME>>",
    "images": [
      %s
    ]
}'
locations <- unique(viewtable$location)
sites <- character()

for (j in 1:length(locations)) {

imagetable <- dplyr::filter(viewtable, location == locations[j])
SITE_NAME <- imagetable$location[j]
#SITE_ID <- sprintf(SITE_ID_template, j)
SITE_ID <- imagetable$SITE_ID[1]
images <- character()
for (i in 1:nrow(imagetable)) {
DATE <- format(as.Date(imagetable$solarday[i]))
SDATE <- format(as.Date(imagetable$solarday[i]), "%Y/%m/%d")

IMAGE_ID <- glue::glue("{collection}/{SDATE}/{SITE_NAME}_{DATE}")



images <- paste0(c(images, glue::glue(image_template, .open = "<<", .close = ">>")), collapse = ",\n")

}

sites <- paste0(c(sites, glue::glue(sprintf(site_template, images), .open = "<<", .close = ">>")), collapse = ",\n")

}
jstext <- sprintf('{
"locations": [
 %s
]
        }', sites)
#writeLines(jstext)
writeLines(jstext, "image-catalog.json")
"image-catalog.json"
}
