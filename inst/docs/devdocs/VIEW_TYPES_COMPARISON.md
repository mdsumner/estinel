# Handling Multiple View Types - Three Approaches

## Approach 1: Explicit (Current)

**Pros**: Clear, easy to understand, explicit
**Cons**: Repetitive, harder to add/remove view types

```r
# === EXPLICIT TARGETS (6 targets) ===
view_q128 <- build_image_png(dsn_table, force = FALSE, type = "q128") |> 
  tar_target(pattern = map(dsn_table))
view_histeq <- build_image_png(dsn_table, force = FALSE, type = "histeq") |> 
  tar_target(pattern = map(dsn_table))
view_stretch <- build_image_png(dsn_table, force = FALSE, type = "stretch") |> 
  tar_target(pattern = map(dsn_table))

thumb_q128 <- build_thumb(view_q128, force = FALSE) |> 
  tar_target(pattern = map(view_q128)) 
thumb_histeq <- build_thumb(view_histeq, force = FALSE) |> 
  tar_target(pattern = map(view_histeq)) 
thumb_stretch <- build_thumb(view_stretch, force = FALSE) |> 
  tar_target(pattern = map(view_stretch))

# === COMBINE ===
viewtableNA <- mutate(
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
  tar_force(force = TRUE)
```

**To add a new view type**: Need to edit 4 places:
1. Add `view_newtype` target
2. Add `thumb_newtype` target
3. Add to first `mutate()`
4. Add to URL rewriting `mutate()`

---

## Approach 2: tar_map (Recommended)

**Pros**: DRY, easy to add/remove types, fewer lines
**Cons**: Slightly more complex, still manual URL rewriting

```r
# === DEFINE VIEW TYPES ONCE ===
view_types <- tibble::tibble(
  type = c("q128", "histeq", "stretch")
)

# === CREATE ALL TARGETS (6 targets from 1 spec) ===
tar_map(
  values = view_types,
  names = type,  # Creates view_q128, thumb_q128, etc.
  tar_target(
    view,
    build_image_png(dsn_table, force = FALSE, type = type),
    pattern = map(dsn_table)
  ),
  tar_target(
    thumb,
    build_thumb(view, force = FALSE),
    pattern = map(view)
  )
)

# === COMBINE (still explicit, but targets auto-created) ===
viewtableNA <- mutate(
  dsn_table, 
  view_q128 = view_q128,      # tar_map created this
  view_histeq = view_histeq,  # tar_map created this
  view_stretch = view_stretch, # tar_map created this
  thumb_q128 = thumb_q128,     # tar_map created this
  thumb_histeq = thumb_histeq, # tar_map created this
  thumb_stretch = thumb_stretch # tar_map created this
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
  tar_force(force = TRUE)
```

**To add a new view type**: Edit 1 place:
1. Add to `view_types` tibble
2. (Still need to add to mutate calls manually)

---

## Approach 3: Fully Dynamic (Most DRY)

**Pros**: Most flexible, single source of truth
**Cons**: More complex, harder to debug

```r
# === DEFINE VIEW TYPES ONCE ===
view_types <- c("q128", "histeq", "stretch")

# === CREATE TARGETS ===
tar_map(
  values = tibble::tibble(type = view_types),
  names = type,
  tar_target(
    view,
    build_image_png(dsn_table, force = FALSE, type = type),
    pattern = map(dsn_table)
  ),
  tar_target(
    thumb,
    build_thumb(view, force = FALSE),
    pattern = map(view)
  )
)

# === COMBINE WITH HELPER FUNCTION ===
viewtableNA <- dsn_table |>
  add_view_columns(
    view_types = view_types,
    views = list(q128 = view_q128, histeq = view_histeq, stretch = view_stretch),
    thumbs = list(q128 = thumb_q128, histeq = thumb_histeq, stretch = thumb_stretch)
  ) |>
  rewrite_s3_urls(endpoint = endpoint) |>
  tar_force(force = TRUE)

# Helper function in R/functions.R:
add_view_columns <- function(dsn_table, view_types, views, thumbs) {
  result <- dsn_table
  for (type in view_types) {
    result[[paste0("view_", type)]] <- views[[type]]
    result[[paste0("thumb_", type)]] <- thumbs[[type]]
  }
  result
}

rewrite_s3_urls <- function(df, endpoint) {
  char_cols <- names(df)[sapply(df, is.character)]
  for (col in char_cols) {
    df[[col]] <- gsub("/vsis3", endpoint, df[[col]])
  }
  df
}
```

**To add a new view type**: Edit 1 place:
1. Add to `view_types` vector
2. Everything else is automatic!

---

## Approach 4: Using tarchetypes::tar_combine

**Pros**: Built-in aggregation
**Cons**: Different structure for downstream use

```r
# Define view types
view_types <- tibble::tibble(type = c("q128", "histeq", "stretch"))

# Generate all view and thumb targets
tar_map(
  values = view_types,
  names = type,
  tar_target(view, build_image_png(dsn_table, force = FALSE, type = type),
             pattern = map(dsn_table)),
  tar_target(thumb, build_thumb(view, force = FALSE),
             pattern = map(view))
)

# Combine all views into single list
tar_combine(
  views_combined,
  tar_map(
    values = view_types,
    names = type,
    tar_target(view_list, 
               list(view = view, thumb = thumb, type = type))
  )
)

# Then process views_combined downstream
```

---

## Recommendation: Approach 2 (tar_map)

**Best balance of**:
- ✅ Reduced repetition (6 targets → 1 spec)
- ✅ Still clear and debuggable
- ✅ Easy to add new view types
- ✅ Doesn't require helper functions
- ⚠️ Still manual mutate (but that's OK, it's explicit)

**Code change**:

### Before (18 lines):
```r
view_q128 <- ... |> tar_target(...)
view_histeq <- ... |> tar_target(...)
view_stretch <- ... |> tar_target(...)
thumb_q128 <- ... |> tar_target(...)
thumb_histeq <- ... |> tar_target(...)
thumb_stretch <- ... |> tar_target(...)
```

### After (9 lines):
```r
view_types <- tibble::tibble(type = c("q128", "histeq", "stretch"))

tar_map(
  values = view_types,
  names = type,
  tar_target(view, build_image_png(dsn_table, force = FALSE, type = type),
             pattern = map(dsn_table)),
  tar_target(thumb, build_thumb(view, force = FALSE), pattern = map(view))
)
```

**50% fewer lines, same functionality!**

---

## When to Use Each

| Approach | Best When |
|----------|-----------|
| 1. Explicit | Learning targets, need maximum clarity |
| 2. tar_map | **Recommended for production** - clear + DRY |
| 3. Fully Dynamic | Have many (10+) view types, frequently changing |
| 4. tar_combine | Need to aggregate results into data structure |

---

## Example: Adding a New View Type

### With Approach 1 (Explicit):
```r
# 1. Add target
view_custom <- build_image_png(dsn_table, force = FALSE, type = "custom") |> 
  tar_target(pattern = map(dsn_table))

# 2. Add thumb target  
thumb_custom <- build_thumb(view_custom, force = FALSE) |> 
  tar_target(pattern = map(view_custom))

# 3. Add to mutate
mutate(dsn_table, 
       ...,
       view_custom = view_custom,
       thumb_custom = thumb_custom)

# 4. Add to URL rewriting
mutate(...,
       view_custom = gsub("/vsis3", endpoint, view_custom),
       thumb_custom = gsub("/vsis3", endpoint, thumb_custom))
```

### With Approach 2 (tar_map):
```r
# 1. Add to view_types (DONE!)
view_types <- tibble::tibble(
  type = c("q128", "histeq", "stretch", "custom")
)

# 2. Add to mutate (manual but small)
mutate(dsn_table, 
       ...,
       view_custom = view_custom,
       thumb_custom = thumb_custom)

# 3. Add to URL rewriting (manual but small)
mutate(...,
       view_custom = gsub("/vsis3", endpoint, view_custom),
       thumb_custom = gsub("/vsis3", endpoint, thumb_custom))
```

### With Approach 3 (Fully Dynamic):
```r
# 1. Add to view_types (DONE! Everything else automatic)
view_types <- c("q128", "histeq", "stretch", "custom")
```

---

## My Recommendation

Start with **Approach 2 (tar_map)** because:
1. Clear win for target generation (6 targets → 1 spec)
2. Easy to understand and debug
3. Doesn't require extra helper functions
4. Manual mutate is fine (only ~6 extra lines)
5. Good balance of DRY without over-engineering

If you later add 5+ more view types, consider **Approach 3**.

---

## Implementation

See [estinel_targets_tarmap.R](computer:///home/claude/estinel_targets_tarmap.R) for complete working example with tar_map.
