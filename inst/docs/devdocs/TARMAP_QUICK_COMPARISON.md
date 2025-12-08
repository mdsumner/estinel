# View Types: Before vs After

## ❌ Before (18 lines, repetitive)

```r
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
```

**Problem**: To add a new type, copy-paste 2 more targets

---

## ✅ After (9 lines with tar_map)

```r
view_types <- tibble::tibble(type = c("q128", "histeq", "stretch"))

tar_map(
  values = view_types,
  names = type,
  tar_target(view, build_image_png(dsn_table, force = FALSE, type = type),
             pattern = map(dsn_table)),
  tar_target(thumb, build_thumb(view, force = FALSE),
             pattern = map(view))
)
```

**Creates the same 6 targets**:
- `view_q128`, `view_histeq`, `view_stretch`  
- `thumb_q128`, `thumb_histeq`, `thumb_stretch`

**Benefit**: To add a new type, just add one word to the vector!

```r
# Add "custom" stretch type:
view_types <- tibble::tibble(type = c("q128", "histeq", "stretch", "custom"))
# Done! Automatically creates view_custom and thumb_custom
```

---

## 📊 Savings

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Lines of code | 18 | 9 | **50% fewer** |
| Target specs | 6 | 1 | **6x less repetition** |
| To add new type | 6 edits | 1 edit | **6x faster** |

---

## 💡 How tar_map Works

```r
tar_map(
  values = tibble(type = c("a", "b")),  # Data frame with parameters
  names = type,                          # Column to use for naming
  
  # Template targets (repeated for each row)
  tar_target(view, build_png(type = type)),
  tar_target(thumb, build_thumb(view))
)
```

**Expands to**:
```r
view_a <- build_png(type = "a") |> tar_target()
thumb_a <- build_thumb(view_a) |> tar_target()
view_b <- build_png(type = "b") |> tar_target()
thumb_b <- build_thumb(view_b) |> tar_target()
```

---

## 🚀 Recommendation

Use **[estinel_targets_tarmap.R](computer:///home/claude/estinel_targets_tarmap.R)** - it's the same pipeline but with tar_map for view types.

Only change: Replace the 6 explicit view/thumb targets with the 9-line tar_map block!
