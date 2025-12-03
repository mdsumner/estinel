set_gdal_s3_config <- function() {
  Sys.setenv(
    AWS_ACCESS_KEY_ID = Sys.getenv("PAWSEY_AWS_ACCESS_KEY_ID"),
    AWS_SECRET_ACCESS_KEY = Sys.getenv("PAWSEY_AWS_SECRET_ACCESS_KEY"),
    AWS_REGION = "",
    AWS_S3_ENDPOINT = "projects.pawsey.org.au",
    CPL_VSIL_USE_TEMP_FILE_FOR_RANDOM_WRITE = "YES",
    AWS_VIRTUAL_HOSTING = "FALSE",
    GDAL_HTTP_MAX_RETRY = "4",
    GDAL_HTTP_RETRY_DELAY = "10",
    "GDAL_PAM_ENABLED" = "YES"
  )
}

parse_s3_uri <- function(uri) {
  parts <- sub("^s3://", "", uri)
  bucket <- sub("/.*", "", parts)
  key <- sub("^[^/]+/", "", parts)
  list(bucket = bucket, key = key)
}

get_s3_etag <- function(vsis3_uri, endpoint = "projects.pawsey.org.au") {
  s3_uri <- sub("^/vsis3/", "s3://", vsis3_uri)
  parsed <- parse_s3_uri(s3_uri)
  
  obj_info <- aws.s3::head_object(
    object = parsed$key,
    bucket = parsed$bucket,
    base_url = endpoint,
    region = ""
  )
  
  attr(obj_info, "etag")
}
# R/s3_helpers.R
create_s3_marker <- function(vsis3_uri, marker_dir = "_s3_markers") {
  dir.create(marker_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Get ETag from S3
  etag <- get_s3_etag(vsis3_uri)
  
  # Create marker file path
  marker_name <- paste0(digest::digest(vsis3_uri), ".txt")
  marker_file <- file.path(marker_dir, marker_name)
  
  # Write BOTH the S3 path and ETag to marker file
  writeLines(c(vsis3_uri, etag), marker_file)
  
  marker_file
}

read_s3_marker <- function(marker_file) {
  lines <- readLines(marker_file)
  list(
    path = lines[1],
    etag = lines[2]
  )
}


get_s3_path <- function(marker) {
  read_s3_marker(marker)$path
}