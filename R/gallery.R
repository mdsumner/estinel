gallery <- function(dir, pattern = ".*\\.png$", pagefile = "gallery.html", overwrite = FALSE) {
  files <- fs::dir_ls(dir, pattern = pattern)
  
  ## because the html go in ./gallery/
  files <- paste0("../", files)
  div <- '<div class="gallery-item">
            <img src="%s" alt="Image 1">
        </div>'
  
  html <- '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Image Gallery</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="gallery">
%s
    </div>
</body>
</html>'
  
  if (file.exists(pagefile)) {
    if (overwrite) {
      unlink(pagefile)
    } else {
      stop(sprintf("'pagefile': '%s' exists, remove or set 'overwrite = TRUE'", pagefile))
    }
}
  writeLines(sprintf(html, paste0(sprintf(div, files), collapse = "\n")), pagefile)
  
}

