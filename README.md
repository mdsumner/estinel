
<!-- README.md is generated from README.Rmd. Please edit that file -->

# estinel

<!-- badges: start -->

<!-- badges: end -->

**Systematic Sentinel-2 imagery processing and collaborative image
classification for Antarctic research**

The goal of estinel is to process Sentinel-2 imagery in a systematic
way, targeting specific locations of interest. This is a project of the
Integrated Digital East Antarctica program at the [Australian Antarctic
Division](https://www.antarctica.gov.au/).

## Overview

estinel creates a catalog of Sentinel-2 imagery with:

- Original red, green, blue bands
- Multiple “view types” with different color balance stretches
- Complete workflow traceability using the `{targets}` package
- Interactive browser for visualization and classification
- Collaborative rating system for image quality assessment

**Data Pipeline:** - Sentinel-2 imagery queried from
[element84.com](https://element84.com) - Processed with GDAL and the R
`{targets}` package - Hosted on the [Pawsey Supercomputing Research
Centre](https://pawsey.org.au/)

## Interactive Browser

**Try it now:** [Catalog
Browser](https://projects.pawsey.org.au/estinel/catalog/catalog-browser.html)

The browser provides:

- **Multiple view modes** - Single image, slider comparison, and
  side-by-side viewing
- **Rating system** - Classify images as Good/OK/Bad with keyboard
  shortcuts (1/2/3)
- **Collaborative workflow** - Export/import ratings as JSON for team
  review
- **Smart filtering** - Multi-select filters to view specific rating
  categories
- **Playback mode** - Automated slideshow with adjustable speed (0.1s to
  3s)
- **Location sorting** - View locations by most recent imagery or
  alphabetically
- **Rate and Next** - Auto-advance to next unrated image for rapid
  classification

### Quick Start

1.  Open the
    [browser](https://projects.pawsey.org.au/estinel/catalog/catalog-browser.html)
2.  Press `?` to see keyboard shortcuts
3.  Use `1/2/3` to rate images (Good/OK/Bad)
4.  Enable “Rate and Next” for rapid classification
5.  Export your ratings and contribute them as issues to this repository

### Contributing Ratings

After rating images: 1. Click the ⭐ star button to open the rating
panel 2. Click “Export Ratings” to download your classifications as JSON
3. Share your ratings by [opening an
issue](https://github.com/mdsumner/estinel/issues) on this repository

Community ratings can be aggregated and shared via URL import for
collaborative classification efforts.

## Documentation

- **[Design Rationale](inst/docs/design-rationale.md)** - Comprehensive
  documentation of design decisions, alternatives considered, and
  rationale for the browser and classification system
- **[Browser Source](inst/docs/catalog-browser-with-ratings.html)** -
  Single-file HTML application (built with Claude AI)

### Catalog Schema

The image catalog uses a JSON format with a hierarchical structure:

``` json
{
  "locations": [
    {
      "id": "loc_001",
      "name": "Site Name - Description",
      "images": [
        {
          "id": "unique_image_id",
          "url": "path/to/image.png",
          "date": "YYYY-MM-DD",
          "thumbnail": "path/to/thumbnail.png",
          "download": "path/to/original.tif",
          "stac-item": "path/to/stac-metadata.json"
        }
      ]
    }
  ]
}
```

**Field descriptions:** - `locations[]` - Array of geographic sites
being monitored - `id` - Unique identifier for location or image -
`name` - Human-readable location name - `url` - Can be a string (single
view) or object with multiple view types (e.g.,
`{"true_color": "...", "false_color": "..."}`) - `date` - ISO 8601 date
string for the image acquisition - `thumbnail` - Low-resolution preview
image - `download` - Link to original GeoTIFF data - `stac-item` -
SpatioTemporal Asset Catalog metadata (optional)

## Project Status

This is an active research project. The R package structure provides
organization, but the primary workflow currently uses `{targets}` for
pipeline orchestration. Development continues for a better underlying
map index for the catalog.

## Installation

``` r
# Not yet on CRAN
# Install development version from GitHub:
# remotes::install_github("mdsumner/estinel")
```

## 📦 Accessing the Catalog

The satellite imagery catalog is distributed via [GitHub
Releases](https://github.com/mdsumner/estinel/releases/tag/catalog-data).

### Quick Start

``` r
# Download compressed catalog
piggyback::pb_download(
  file = "image-catalog.json.gz",
  repo = "mdsumner/estinel",
  tag = "catalog-data",
  dest = "."
)

# Read compressed JSON directly
catalog <- jsonlite::fromJSON(gzfile("image-catalog.json.gz"))

# Explore (catalog$locations is a data frame!)
nrow(catalog$locations)           # Number of locations (98)
head(catalog$locations$name)      # Location names
head(catalog$locations$purpose)   # Purpose tags (list column)
catalog$locations$name[1]         # First location name
length(catalog$locations$images[[1]])  # Images at first location
```

### Filter by Purpose

``` r
# Find all emperor penguin colonies
emperor_sites <- catalog$locations[
  sapply(catalog$locations$purpose, function(p) "emperor" %in% p),
]
nrow(emperor_sites)  # How many emperor colonies?

# Find all research bases
bases <- catalog$locations[
  sapply(catalog$locations$purpose, function(p) "base" %in% p),
]

# Multiple purposes
heard_sites <- catalog$locations[
  sapply(catalog$locations$purpose, function(p) "heard" %in% p),
]
```

### Alternative: Direct Download

``` r
# Download without piggyback
url <- "https://github.com/mdsumner/estinel/releases/download/catalog-data/image-catalog.json.gz"
temp_gz <- tempfile(fileext = ".json.gz")
download.file(url, temp_gz, mode = "wb")

# Read
catalog <- jsonlite::fromJSON(gzfile(temp_gz))

# Cleanup
unlink(temp_gz)
```

### Catalog Structure

``` r
# Data frame with columns:
str(catalog$locations, max.level = 1)

# $ id      : chr [1:98] "site_12345" ...
# $ name    : chr [1:98] "Hobart" "Davis_Station" ...
# $ purpose : List of 98 (each element is character vector)
# $ images  : List of 98 (each element is data frame of images)

# Access images for a specific location
davis_images <- catalog$locations$images[[2]]  # Davis_Station
nrow(davis_images)           # Number of images
head(davis_images$date)      # Image dates
head(davis_images$url)       # View URLs (data frame)
```

**Updated:** Every 2 hours by automated pipeline  
**Size:** ~2-5 MB compressed, ~40 MB uncompressed  
**Locations:** 98 Antarctic sites \## Code of Conduct

Please note that the estinel project is released with a [Contributor
Code of
Conduct](https://contributor-covenant.org/version/2/1/CODE_OF_CONDUCT.html).
By contributing to this project, you agree to abide by its terms.

------------------------------------------------------------------------

*This tool was built collaboratively with Claude AI as part of the
estinel project.*
