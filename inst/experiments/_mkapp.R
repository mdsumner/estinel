bucket <- "geotar0"
prefix <- "_targets-geotar"
rootdir <- sprintf("/vsis3/%s/%s", bucket, prefix)
# "/perm_storage/home/data/_targets_locationtifs/sentinel-2-c1-l2a"
endpoint <- "https://projects.pawsey.org.au"


Sys.setenv(AWS_ACCESS_KEY_ID = Sys.getenv("PAWSEY_AWS_ACCESS_KEY_ID"),
           AWS_SECRET_ACCESS_KEY = Sys.getenv("PAWSEY_AWS_SECRET_ACCESS_KEY"),
           AWS_REGION = "",
           AWS_S3_ENDPOINT = gsub("^https://", "", endpoint),
           CPL_VSIL_USE_TEMP_FILE_FOR_RANDOM_WRITE = "YES",
           AWS_VIRTUAL_HOSTING = "NO")
library(targets)
library(shinyglide)
pls <- "Heard_Island_Atlas_Cove"
viewtable <- tar_read(viewtable) 
files <- viewtable[viewtable$location == pls, ]
files <- files[!is.na(files$outfile), ]
files <- arrange(files, desc(solarday))

#library(shinyglide)

tx <- paste0(sprintf('screen(
                     h2("%s %s"),
                     img(src = "%s"))', pls, format(as.Date(files$solarday)), files$outpng), collapse = ",\n")

writeLines(tx)
x <- sprintf('ui <- fixedPage(
  h3("Simple shinyglide app"),
  glide(
    %s
  )
)
server <- function(input, output, session) {
}

shinyApp(ui, server)
', tx)

writeLines(x, "app.R")

