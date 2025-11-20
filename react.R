collection <- "sentinel-2-c1-l2a"
SITE_ID <- "site_"
SITE_NAME <- "Auster"
IMAGE_ID <- "{collection}/2025/01/02/Auster_2025-01-02"
DATE <- "2025-01-02"

image_template <- 
'"locations": [
    {
      "id": "{SITE_ID}",
      "name": "{SITE_NAME}",
      "images": [
        {
          "id": "IMAGE_ID",
          "url":       "https://projects.pawsey.org.au/estinel/{IMAGE_ID}.png",
          "thumbnail": "https://projects.pawsey.org.au/estinel/thumbs/{IMAGE_ID}.png",
          "date": "{DATE}"
        }
      ]
    }
  ]'


names(viewtable)
