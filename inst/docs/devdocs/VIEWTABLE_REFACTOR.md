# Refactoring viewtable: Better Handling of Failed Assets

## ❌ Current Approach (Anti-pattern)

```r
# Keep everything (including NAs)
viewtableNA <- mutate(dsn_table, ...) |> tar_force(force = TRUE)

# Filter out NAs for production
viewtable <- viewtableNA |> 
  filter(!is.na(outfile), !is.na(view_q128)) |>
  tar_force(force = TRUE)
```

**Problems**:
- Two targets with unclear naming (what's "NA" mean?)
- Filtering logic duplicated in downstream code
- Hard to see what failed without inspecting viewtableNA
- tar_force on both (wasteful rebuilds)

---

## ✅ Approach 1: Single Table with Status Column (Recommended)

**Pros**: Single source of truth, easy filtering, clear status
**Cons**: None really!

```r
# === SINGLE TABLE WITH STATUS ===
viewtable <- mutate(
  dsn_table, 
  view_q128 = view_q128,
  view_histeq = view_histeq,
  view_stretch = view_stretch, 
  thumb_q128 = thumb_q128,
  thumb_histeq = thumb_histeq,
  thumb_stretch = thumb_stretch
) |>
  mutate(
    outfile = gsub("/vsis3", endpoint, outfile),
    view_q128 = gsub("/vsis3", endpoint, view_q128),
    view_histeq = gsub("/vsis3", endpoint, view_histeq),
    view_stretch = gsub("/vsis3", endpoint, view_stretch),
    scl_tif = gsub("/vsis3", endpoint, scl_tif),
    thumb_q128 = gsub("/vsis3", endpoint, thumb_q128), 
    thumb_histeq = gsub("/vsis3", endpoint, thumb_histeq), 
    thumb_stretch = gsub("/vsis3", endpoint, thumb_stretch)
  ) |>
  mutate(
    # Add status column for easy filtering
    valid = !is.na(outfile) & !is.na(view_q128),
    failure_reason = case_when(
      is.na(outfile) ~ "RGB build failed",
      is.na(view_q128) ~ "PNG generation failed",
      TRUE ~ NA_character_
    )
  ) |> 
  tar_force(force = TRUE)

# === USE FILTERED VIEWS DOWNSTREAM ===
# For web catalog (only valid)
viewtable_valid <- viewtable |> 
  filter(valid) |>
  tar_target()

# For QA report (only failures)
viewtable_failures <- viewtable |> 
  filter(!valid) |>
  tar_target()

# Write catalog JSON (only valid images)
json <- write_react_json(viewtable_valid) |> tar_force(force = TRUE)

# Optional: Write failure report
failure_report <- write_failure_report(viewtable_failures) |> 
  tar_target()
```

**Benefits**:
- Single viewtable with all data
- `valid` column makes filtering explicit
- `failure_reason` helps debugging
- Separate targets for valid/failures (clear purpose)
- No tar_force on filtered views (they depend on viewtable)

---

## ✅ Approach 2: Diagnostic Targets (Best for Investigation)

**Pros**: Explicit QA pipeline, great for debugging
**Cons**: More targets

```r
# === MAIN TABLE ===
viewtable <- mutate(dsn_table, ...) |> 
  add_validity_checks() |>
  tar_force(force = TRUE)

# === DIAGNOSTIC TARGETS ===
# Summary statistics
processing_summary <- viewtable |> 
  summarise(
    total_images = n(),
    successful = sum(valid),
    failed = sum(!valid),
    success_rate = mean(valid),
    .by = location
  ) |> 
  tar_target()

# Failed images details
failed_images <- viewtable |> 
  filter(!valid) |>
  select(location, solarday, outfile, view_q128, failure_reason) |>
  tar_target()

# Missing view types
missing_views <- viewtable |> 
  summarise(
    missing_q128 = sum(is.na(view_q128)),
    missing_histeq = sum(is.na(view_histeq)),
    missing_stretch = sum(is.na(view_stretch))
  ) |>
  tar_target()

# === WEB CATALOG (VALID ONLY) ===
json <- viewtable |> 
  filter(valid) |>
  write_react_json() |> 
  tar_force(force = TRUE)
```

**Helper function** in R/functions.R:
```r
add_validity_checks <- function(df) {
  df |>
    mutate(
      # Check each required output
      has_rgb = !is.na(outfile),
      has_view_q128 = !is.na(view_q128),
      has_view_histeq = !is.na(view_histeq),
      has_view_stretch = !is.na(view_stretch),
      has_thumb_q128 = !is.na(thumb_q128),
      has_thumb_histeq = !is.na(thumb_histeq),
      has_thumb_stretch = !is.na(thumb_stretch),
      
      # Overall validity
      valid = has_rgb & has_view_q128 & has_view_histeq & has_view_stretch,
      
      # Detailed failure reason
      failure_reason = case_when(
        !has_rgb ~ "RGB GeoTIFF build failed",
        !has_view_q128 ~ "q128 PNG generation failed",
        !has_view_histeq ~ "histeq PNG generation failed",
        !has_view_stretch ~ "stretch PNG generation failed",
        TRUE ~ NA_character_
      ),
      
      # Severity
      severity = case_when(
        !has_rgb ~ "critical",  # No base image
        !valid ~ "warning",     # Missing views
        TRUE ~ "ok"
      )
    )
}
```

---

## ✅ Approach 3: Early Failure Detection

**Pros**: Catch failures as they happen, better error tracking
**Cons**: More complex pipeline structure

```r
# === ADD VALIDATION AT EACH STEP ===

dsn_table <- build_image_dsn(group_table, rootdir = rootdir) |> 
  tar_target(pattern = map(group_table))

# Immediately identify failed RGB builds
dsn_validated <- dsn_table |>
  mutate(
    rgb_valid = !is.na(outfile),
    rgb_failure = if_else(!rgb_valid, 
                         sprintf("%s_%s", location, solarday),
                         NA_character_)
  ) |>
  tar_target()

# Track failures at RGB stage
rgb_failures <- dsn_validated |> 
  filter(!rgb_valid) |>
  select(location, solarday, SITE_ID, clear_test, rgb_failure) |>
  tar_target()

# Only process valid RGBs for PNGs
dsn_table_valid <- dsn_validated |> 
  filter(rgb_valid) |>
  tar_target()

# Generate views (only for valid RGBs)
tar_map(
  values = view_types,
  names = type,
  tar_target(view, build_image_png(dsn_table_valid, force = FALSE, type = type),
             pattern = map(dsn_table_valid)),
  tar_target(thumb, build_thumb(view, force = FALSE),
             pattern = map(view))
)

# Combine and validate
viewtable <- combine_and_validate_views(
  dsn_table_valid, 
  view_q128, view_histeq, view_stretch,
  thumb_q128, thumb_histeq, thumb_stretch
) |> tar_target()

# All failures in one place
all_failures <- bind_rows(
  rgb_failures |> mutate(stage = "RGB build"),
  viewtable |> filter(!valid) |> mutate(stage = "PNG generation")
) |> tar_target()
```

---

## ✅ Approach 4: Use targets Error Handling

**Pros**: Uses built-in targets features
**Cons**: Requires targets 1.0.0+

```r
tar_option_set(
  error = "continue",  # Don't stop pipeline on errors
  # other options...
)

# Targets will track errors automatically
# Failed targets marked with error status
# Can retrieve with tar_meta() or tar_errored()

# Later, check for errors:
errored_targets <- tar_meta() |> 
  filter(error != "") |>
  tar_target()
```

---

## 🎯 Recommended Solution: Approach 1 + 2 Combined

```r
# === SINGLE TABLE WITH VALIDATION ===
viewtable <- mutate(
  dsn_table, 
  # Add view/thumb columns
  view_q128 = view_q128,
  view_histeq = view_histeq,
  view_stretch = view_stretch, 
  thumb_q128 = thumb_q128,
  thumb_histeq = thumb_histeq,
  thumb_stretch = thumb_stretch
) |>
  mutate(
    # URL rewriting
    across(c(outfile, view_q128, view_histeq, view_stretch, scl_tif,
             thumb_q128, thumb_histeq, thumb_stretch),
           ~gsub("/vsis3", endpoint, .x))
  ) |>
  # Add validation
  mutate(
    valid = !is.na(outfile) & !is.na(view_q128),
    failure_reason = case_when(
      is.na(outfile) ~ "RGB build failed",
      is.na(view_q128) ~ "PNG generation failed",
      TRUE ~ NA_character_
    )
  ) |> 
  tar_force(force = TRUE)

# === QA/DIAGNOSTIC TARGETS ===
processing_stats <- viewtable |> 
  summarise(
    total = n(),
    valid = sum(valid),
    failed = sum(!valid),
    success_rate = scales::percent(mean(valid)),
    .by = location
  ) |> 
  tar_target()

failed_images <- viewtable |> 
  filter(!valid) |>
  tar_target()

# === PRODUCTION OUTPUTS ===
json <- viewtable |> 
  filter(valid) |>
  write_react_json() |> 
  tar_force(force = TRUE)

web <- update_react(json, rootdir) |> tar_force(force = TRUE)
```

---

## 📊 Comparison

| Approach | Clarity | Debug-ability | Lines | Recommended |
|----------|---------|---------------|-------|-------------|
| Current (NA/non-NA) | ⭐⭐ | ⭐⭐ | Medium | ❌ No |
| 1. Status Column | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Low | ✅ Yes |
| 2. Diagnostic Targets | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Medium | ✅ Yes (+ Approach 1) |
| 3. Early Detection | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | High | 🤔 Complex |
| 4. targets Error | ⭐⭐⭐ | ⭐⭐⭐ | Low | 🤔 Limited |

---

## 🚀 Quick Win: Minimal Change

Replace:
```r
viewtableNA <- mutate(dsn_table, ...) |> tar_force(force = TRUE)
viewtable <- viewtableNA |> filter(!is.na(outfile), !is.na(view_q128)) |> tar_force(force = TRUE)
```

With:
```r
viewtable <- mutate(dsn_table, ...) |>
  mutate(valid = !is.na(outfile) & !is.na(view_q128)) |>
  tar_force(force = TRUE)

# For web catalog
json <- viewtable |> filter(valid) |> write_react_json() |> tar_force(force = TRUE)

# For investigation
failed_images <- viewtable |> filter(!valid) |> tar_target()
```

**Benefits**:
- ✅ Single viewtable (no more NA/non-NA confusion)
- ✅ Explicit `valid` column (self-documenting)
- ✅ Separate `failed_images` target (easy to inspect)
- ✅ Remove duplicate tar_force
- ✅ Clearer intent

---

## 💡 Bonus: across() for URL Rewriting

Notice the URL rewriting can also be simplified:

**Before**:
```r
mutate(
  outfile = gsub("/vsis3", endpoint, outfile),
  view_q128 = gsub("/vsis3", endpoint, view_q128),
  view_histeq = gsub("/vsis3", endpoint, view_histeq),
  # ... 5 more lines
)
```

**After**:
```r
mutate(
  across(
    c(outfile, view_q128, view_histeq, view_stretch, scl_tif,
      thumb_q128, thumb_histeq, thumb_stretch),
    ~gsub("/vsis3", endpoint, .x)
  )
)
```

Or even better with helper:
```r
mutate(across(where(is.character), ~gsub("/vsis3", endpoint, .x)))
```

This rewrites ALL character columns automatically!

---

## Implementation

See next file for complete refactored pipeline with both improvements.
