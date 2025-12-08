# File Naming Structure - Visual Comparison

## Quick Reference

### OLD (Current)
```
Location name:  Heard_Island_Atlas_Cove     ← Modified in data
File path:      Heard_Island_Atlas_Cove_2024-01-20.tif
                ^^^^^^^^^^^^^^^^^^^^^^^_^^^^^^^^^^
                    Location?          Date?
Problem:        Can't tell where location ends!
```

### NEW (Recommended)
```
Location name:  Heard Island Atlas Cove      ← Pristine in data
File path:      heard-island-atlas-cove_2024-01-20.tif
                ^^^^^^^^^^^^^^^^^^^^^^^_^^^^^^^^^^
                    Location slug      Date
Benefit:        Clear separation with single underscore
```

---

## Full Path Examples

### Example 1: Simple Location

**OLD:**
```
Data:  location = "Hobart"
Path:  /vsis3/estinel/sentinel-2-c1-l2a/2018/01/05/Hobart_2018-01-05.tif
SCL:   /vsis3/estinel/sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20_scl.tif
PNG:   /vsis3/estinel/sentinel-2-c1-l2a/2018/01/20/Hobart_2018-01-20_q128.png
```

**NEW:**
```
Data:  location = "Hobart"
Path:  /vsis3/estinel/sentinel-2-c1-l2a/2018/01/05/hobart_2018-01-05.tif
SCL:   /vsis3/estinel/sentinel-2-c1-l2a/2018/01/20/hobart_2018-01-20_scl.tif
PNG:   /vsis3/estinel/sentinel-2-c1-l2a/2018/01/20/hobart_2018-01-20_q128.png
```

**Changes:**
- ✅ Lowercase location slug
- ✅ Same clear structure

---

### Example 2: Multi-word Location

**OLD:**
```
Data:  location = "Dawson_Lampton_Ice_Tongue"  ← spaces converted to _
Path:  /vsis3/estinel/.../Dawson_Lampton_Ice_Tongue_2018-01-05.tif
                         ^^^^^^^^^^^^^^^^^^^^^^^^_^^^^^^^^^^
Problem: 4 underscores total - ambiguous!
```

**NEW:**
```
Data:  location = "Dawson Lampton Ice Tongue"  ← pristine
Path:  /vsis3/estinel/.../dawson-lampton-ice-tongue_2018-01-05.tif
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^_^^^^^^^^^^
Benefit: Hyphens in location, single _ before date
```

**Changes:**
- ✅ Pristine name in data
- ✅ Hyphens separate words within location
- ✅ Underscore separates location from date

---

### Example 3: Special Characters

**OLD:**
```
Data:  location = "Dome_C_North"              ← manual cleanup
Excel: "Dôme C (North)"                       ← original
Path:  /vsis3/estinel/.../Dome_C_North_2018-01-05.tif
Problem: Lost original name formatting
```

**NEW:**
```
Data:  location = "Dôme C North"              ← keep original
Excel: "Dôme C (North)"                       ← from Excel
Path:  /vsis3/estinel/.../dome-c-north_2018-01-05.tif
                         ^^^^^^^^^^^^^_^^^^^^^^^^
Benefit: Pristine in data, clean in filesystem
```

**Sanitization process:**
```
"Dôme C (North)"
  → Remove parens:        "Dôme C North"
  → Transliterate:        "Dome C North"  
  → Lowercase:            "dome c north"
  → Replace spaces:       "dome-c-north"
```

---

### Example 4: Complex Location with Suffix

**OLD:**
```
Data:  location = "Heard_Island_Atlas_Cove"
Path:  /vsis3/estinel/.../Heard_Island_Atlas_Cove_2024-12-05.tif
SCL:   /vsis3/estinel/.../Heard_Island_Atlas_Cove_2024-12-05_scl.tif
PNG:   /vsis3/estinel/.../Heard_Island_Atlas_Cove_2024-12-05_q128.png
Thumb: /vsis3/estinel/.../thumbs/.../Heard_Island_Atlas_Cove_2024-12-05_q128.png
                                    ^^^^^^^^^^^^^^^^^^^^^^^^_^^^^^^^^^^_^^^^
Problem: Hard to parse - 5 underscores!
```

**NEW:**
```
Data:  location = "Heard Island Atlas Cove"
Path:  /vsis3/estinel/.../heard-island-atlas-cove_2024-12-05.tif
SCL:   /vsis3/estinel/.../heard-island-atlas-cove_2024-12-05_scl.tif
PNG:   /vsis3/estinel/.../heard-island-atlas-cove_2024-12-05_q128.png
Thumb: /vsis3/estinel/.../thumbs/.../heard-island-atlas-cove_2024-12-05_q128.png
                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^_^^^^^^^^^^_^^^^
Benefit: Clear structure - hyphens in words, underscores between fields
```

**Pattern:**
```
{location-with-hyphens}_{date}_{suffix}.{ext}
```

---

## Field Separator Rules (NEW)

| Separator | Usage | Example |
|-----------|-------|---------|
| `-` (hyphen) | Within location name | `heard-island-atlas-cove` |
| `_` (underscore) | Between fields | `location_date_suffix` |
| `/` (slash) | Directory structure | `2024/12/05/` |

**Parsing a filename:**
```
heard-island-atlas-cove_2024-12-05_q128.png
^-----------------------^----------^----^---
    Location (slug)      Date      Sfx  Ext
```

Split on `_`:
1. `heard-island-atlas-cove` → location
2. `2024-12-05` → date
3. `q128.png` → suffix + extension

**vs OLD (ambiguous):**
```
Heard_Island_Atlas_Cove_2024-01-05_q128.png
^---^------^-----^----^----------^----^---
   Where does location end? 
```

---

## Directory Listings Comparison

### OLD
```bash
$ ls /vsis3/estinel/sentinel-2-c1-l2a/2024/12/05/

Casey_Station_2024-12-05.tif
Casey_Station_2024-12-05_scl.tif  
Casey_Station_2024-12-05_q128.png
Dawson_Lampton_Ice_Tongue_2024-12-05.tif
Dawson_Lampton_Ice_Tongue_2024-12-05_scl.tif
Heard_Island_Atlas_Cove_2024-12-05.tif
Heard_Island_Atlas_Cove_2024-12-05_scl.tif
```

### NEW
```bash
$ ls /vsis3/estinel/sentinel-2-c1-l2a/2024/12/05/

casey-station_2024-12-05.tif
casey-station_2024-12-05_scl.tif  
casey-station_2024-12-05_q128.png
dawson-lampton-ice-tongue_2024-12-05.tif
dawson-lampton-ice-tongue_2024-12-05_scl.tif
heard-island-atlas-cove_2024-12-05.tif
heard-island-atlas-cove_2024-12-05_scl.tif
```

**Benefits:**
- ✅ Lowercase = easier to type
- ✅ Consistent separator usage
- ✅ Groups naturally by location (sorts correctly)

---

## Marker Files (Unchanged!)

Markers already use SITE_ID, so no changes needed:

```bash
$ ls /vsis3/estinel/markers/

site_a1b2c3d4.json
site_e5f6g7h8.json
site_i9j0k1l2.json
```

**Marker content:**
```json
{
  "SITE_ID": "site_a1b2c3d4",
  "location": "Heard Island Atlas Cove",  ← pristine name
  "last_solarday": "2024-12-05",
  "last_updated": "2024-12-05T12:30:00Z",
  "n_images": 142
}
```

---

## Code Changes at a Glance

### 1. Add Sanitization Function
```r
sanitize_location <- function(location) {
  location |>
    tolower() |>
    iconv(to = "ASCII//TRANSLIT") |>
    gsub("[\\s_]+", "-", x = _) |>
    gsub("[^a-z0-9-]", "", x = _) |>
    gsub("-+", "-", x = _) |>
    gsub("^-|-$", "", x = _)
}
```

### 2. Keep Pristine Names
```r
# OLD
cleanup_table <- function() {
  x$location <- gsub("\\s+", "_", x$location)  # ❌ modifies
}

# NEW  
cleanup_table_v2 <- function() {
  # Keep pristine name, only clean up parens
  x$location <- trimws(substr(x$location, 1, paren_pos))  # ✅ pristine
}
```

### 3. Use Sanitization in Paths
```r
# OLD
outfile <- sprintf("%s/%s_%s.tif", root, location, date)
# Uses modified location name

# NEW
location_slug <- sanitize_location(location)
outfile <- sprintf("%s/%s_%s.tif", root, location_slug, date)
# Sanitizes on-the-fly, keeps data pristine
```

---

## Migration Path

### Phase 1: Add Functions ✅
- Add `sanitize_location()`
- Add `build_file_path_readable()`

### Phase 2: Update Data ✅
- Modify `cleanup_table()` to preserve pristine names
- Update `define_locations_table()` (if needed)

### Phase 3: Update Path Building ✅
- Modify `build_image_dsn()` → `_v2`
- Modify `build_scl_dsn()` → `_v2`
- Modify `build_image_png()` → `_v2`

### Phase 4: Test
- [ ] Single location test
- [ ] Verify marker compatibility
- [ ] Check existing files still accessible

### Phase 5: Deploy
- [ ] Update all functions
- [ ] Run full pipeline
- [ ] Verify new structure

---

## FAQ

**Q: Do I need to rename existing files?**  
A: No! Markers use SITE_ID which hasn't changed. Old files stay where they are.

**Q: What if I want SITE_ID-based paths instead?**  
A: Use `build_file_path()` instead of `build_file_path_readable()` - already implemented!

**Q: Can sanitization create name collisions?**  
A: With current locations, no. If it happens, we can switch to SITE_ID paths.

**Q: Will the web interface still work?**  
A: Yes - paths are in the JSON catalog, web just follows URLs.

**Q: What about spaces in web URLs?**  
A: AWS S3 URLs encode spaces correctly. But our paths use hyphens anyway!

---

## Summary

| Aspect | OLD | NEW |
|--------|-----|-----|
| Data | Modified names | Pristine names |
| Location separator | `_` | `-` |
| Field separator | `_` | `_` |
| Clarity | Ambiguous | Clear |
| Sanitization | At definition | At path building |
| Special chars | Manual cleanup | Automatic transliteration |
| Case | Mixed | Lowercase |

**Winner:** NEW approach - pristine data, dynamic sanitization, clear structure! 🎉
