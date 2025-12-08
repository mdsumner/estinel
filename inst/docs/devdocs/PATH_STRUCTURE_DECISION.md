# File Path Structure Decision - Before vs After

## Problem Statement

**Current approach issues:**
1. Location names are sanitized at definition time (spaces → `_`, `é` → `e`)
2. This modifies the canonical location name
3. Underscores used inconsistently (word separators AND field separators)
4. Hard to distinguish: `Heard_Island_Atlas_Cove_2024-01-20.tif` - where does location end?

## Requirements

1. **Keep location names pristine** - spaces, special chars, proper capitalization
2. **Sanitize only for file paths** - dynamic, not baked into data
3. **Clear field separators** - distinguish location from date from suffix
4. **Filesystem safe** - no problematic characters
5. **Human readable** - easy to understand in directory listings
6. **Consistent** - same pattern everywhere

## Path Structure Options

### Option 1: SITE_ID-based (Recommended)

**Pattern:** `{collection}/{YYYY}/{MM}/{DD}/{site_id}_{date}[_{suffix}].{ext}`

**Examples:**
```
sentinel-2-c1-l2a/2024/12/05/site_abc123_2024-12-05.tif
sentinel-2-c1-l2a/2024/12/05/site_abc123_2024-12-05_scl.tif
sentinel-2-c1-l2a/2024/12/05/site_abc123_2024-12-05_q128.png
sentinel-2-c1-l2a/2024/12/05/site_def456_2024-12-05.tif
```

**Pros:**
- ✅ No sanitization needed (SITE_ID already safe)
- ✅ Handles ANY location name (Unicode, spaces, special chars)
- ✅ Clear field separation (single underscore between fields)
- ✅ Consistent hash length
- ✅ Globally unique

**Cons:**
- ❌ Not human-readable (need lookup to know location)
- ❌ Hard to browse by location in file browser

**Use when:** You prioritize robustness and don't need to manually browse files

---

### Option 2: Sanitized Location Name (Human-Readable)

**Pattern:** `{collection}/{YYYY}/{MM}/{DD}/{location-slug}_{date}[_{suffix}].{ext}`

**Examples:**
```
sentinel-2-c1-l2a/2024/12/05/hobart_2024-12-05.tif
sentinel-2-c1-l2a/2024/12/05/heard-island-atlas-cove_2024-12-05_scl.tif
sentinel-2-c1-l2a/2024/12/05/dome-c-north_2024-12-05_q128.png
sentinel-2-c1-l2a/2024/12/05/dawson-lampton-ice-tongue_2024-12-05.tif
```

**Sanitization rules:**
- Lowercase
- Remove parentheses/brackets
- Replace spaces/underscores with hyphens
- Remove accents (é → e)
- Only keep: `a-z`, `0-9`, `-`
- Single hyphens (no consecutive)

**Pros:**
- ✅ Immediately recognizable
- ✅ Easy to browse and debug
- ✅ Clear field separation (hyphens in location, underscore between fields)
- ✅ Still filesystem-safe

**Cons:**
- ❌ Requires sanitization function
- ❌ Could have collisions (e.g., "Site A" and "Site_A" → same)
- ❌ Loses original formatting info

**Use when:** You frequently browse files manually and want readability

---

### Option 3: Hybrid (Best of Both)

**Pattern:** `{collection}/{YYYY}/{MM}/{DD}/{site_id}_{location-slug}_{date}[_{suffix}].{ext}`

**Examples:**
```
sentinel-2-c1-l2a/2024/12/05/site_abc123_hobart_2024-12-05.tif
sentinel-2-c1-l2a/2024/12/05/site_abc123_heard-island_2024-12-05_scl.tif
```

**Pros:**
- ✅ Globally unique (SITE_ID)
- ✅ Human-readable (location slug)
- ✅ Guaranteed safe

**Cons:**
- ❌ Longer filenames
- ❌ Redundant information
- ❌ Still need sanitization

**Use when:** You want both robustness AND readability

---

## Recommended Approach: Option 2 (Sanitized Location)

**Why:**
1. estinel is focused on Antarctic research - human review of imagery is core workflow
2. Browsing files by location name is valuable
3. Location names are controlled (not user-generated chaos)
4. Number of locations is manageable (~50, not 50,000)
5. Clear naming makes debugging easier

**Implementation:**

```r
# Keep pristine names in data
location_original <- "Heard Island (Atlas Cove)"

# Sanitize only when building paths
location_slug <- sanitize_location(location_original)
# → "heard-island-atlas-cove"

# Build path
path <- sprintf("%s/%s/%s_%s.tif", 
                root, year_month_day, location_slug, date)
# → "/vsis3/estinel/.../heard-island-atlas-cove_2024-12-05.tif"
```

**Key principle:** 
> The location name in your data/JSON/markers is ALWAYS the pristine version.
> Sanitization happens ONLY when constructing file paths.

---

## Field Separator Rules

To make paths unambiguous:

1. **Location internal**: Use hyphens
   - `heard-island-atlas-cove`
   - `dawson-lampton-ice-tongue`

2. **Between fields**: Use underscores
   - `{location}_{date}_{suffix}.{ext}`
   - `hobart_2024-12-05_q128.png`

3. **Date internal**: Use hyphens (ISO 8601)
   - `2024-12-05`

4. **Directory structure**: Use slashes
   - `{collection}/{year}/{month}/{day}/`

**Result:** No ambiguity about where fields start/end

---

## Migration Impact

### Functions to Update

1. **`cleanup_table()`** → `cleanup_table_v2()`
   - Remove location name modification
   - Keep pristine names

2. **`define_locations_table()`**
   - Don't underscore spaces
   - Keep as written

3. **`build_image_dsn()`** → `build_image_dsn_v2()`
   - Use `build_file_path_readable()`
   - Pass location through sanitization

4. **`build_scl_dsn()`** → `build_scl_dsn_v2()`
   - Same path building approach

5. **`build_image_png()`** → `build_image_png_v2()`
   - Path derived from input, still works

### Data Compatibility

**Markers:** No change needed
- Already use SITE_ID as filename
- Already store pristine location name in JSON

**Existing files:** Two options
1. **Leave in place** - old naming still works
2. **Migrate** - rename to new structure (can write script)

**Recommendation:** Leave existing, use new structure going forward. The SITE_ID in markers will still match.

---

## Examples Comparison

### Before (Current)
```
Location in data: "Heard_Island_Atlas_Cove"
Path: /vsis3/estinel/sentinel-2-c1-l2a/2024/12/05/Heard_Island_Atlas_Cove_2024-12-05.tif
Issue: Location name is modified, underscores confusing
```

### After (Recommended)
```
Location in data: "Heard Island Atlas Cove"
Path: /vsis3/estinel/sentinel-2-c1-l2a/2024/12/05/heard-island-atlas-cove_2024-12-05.tif
Benefit: Pristine name in data, clear path structure
```

### After (Alternative - SITE_ID)
```
Location in data: "Heard Island (Atlas Cove) [Primary Colony]"
Path: /vsis3/estinel/sentinel-2-c1-l2a/2024/12/05/site_abc123_2024-12-05.tif
Benefit: No sanitization limits, but not human-readable
```

---

## Code Changes Summary

### Add to R/functions.R

```r
sanitize_location()           # NEW - sanitize for paths
build_file_path_readable()    # NEW - standardized path building
cleanup_table_v2()            # MODIFIED - keep pristine names
build_image_dsn_v2()          # MODIFIED - use new paths
build_scl_dsn_v2()            # MODIFIED - use new paths
build_image_png_v2()          # MODIFIED - use new paths
```

### Update in _targets.R

```r
# Change function calls to _v2 versions
dsn_table <- build_image_dsn_v2(group_table, rootdir = rootdir)
scl_tifs <- build_scl_dsn_v2(images_table, root = rootdir)
view_q128 <- build_image_png_v2(dsn_table, force = FALSE, type = "q128")
```

---

## Testing Checklist

- [ ] `sanitize_location()` handles spaces, accents, special chars
- [ ] Pristine names preserved in `define_locations_table()`
- [ ] Paths are filesystem-safe (no problematic chars)
- [ ] Underscores only between fields (location/date/suffix)
- [ ] Hyphens within location and date
- [ ] SITE_ID still matches (for markers)
- [ ] Existing markers still work
- [ ] JSON output has pristine names

---

## Decision: Use Sanitized Location Names (Option 2)

**Rationale:**
- Small, controlled set of locations
- Human review is core workflow
- Clear, readable paths aid debugging
- Can switch to SITE_ID later if needed (markers already use it)

**Next Steps:**
1. Implement `sanitize_location()` and path builders
2. Update `cleanup_table()` to preserve pristine names
3. Modify `build_*` functions to use new paths
4. Test with a single location
5. Verify markers still work
6. Roll out to all locations

---

**Q: What if we add hundreds of locations later?**  
A: Switch to SITE_ID-based paths (Option 1). Markers are already SITE_ID-based, so migration is easy.

**Q: What about name collisions after sanitization?**  
A: With current locations, no collisions exist. If collisions arise, fall back to SITE_ID or add numeric suffix.

**Q: Do we need to rename existing files?**  
A: No - markers track by SITE_ID. New imagery uses new paths, old imagery stays in place.
