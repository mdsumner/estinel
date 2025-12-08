# Targets Pattern/Iteration Decision Guide

## When to Use Each Pattern

### ✅ Use `pattern = map(dependency)`
**When**: You want to process each row/element independently
**Result**: N branches (one per row/element)
**Example**: 
```r
spatial_window <- mk_spatial_window(tabl) |> 
  tar_target(pattern = map(tabl))
# If tabl has 20 rows → creates 20 branches
# Each branch: one location processed independently
```

**Use cases in estinel**:
- `map(tabl)` → process each location's spatial window
- `map(querytable)` → execute each STAC query independently
- `map(images_table)` → build each image independently

---

### ✅ Use `iteration = "vector"`
**When**: Each branch returns a SINGLE atomic value
**Result**: Combined into atomic vector `c(val1, val2, val3, ...)`
**Example**:
```r
scl_clear <- filter_fun(read_dsn(scl_tifs)) |> 
  tar_target(pattern = map(scl_tifs), iteration = "vector")
# Each branch: returns one number (clear sky %)
# Combined: c(0.85, 0.92, 0.67, ...) - vector of percentages
```

**Why this matters**: 
- Can use `scl_clear[tar_group]` to match values to groups
- Memory efficient for scalar results
- Fast aggregation

**Wrong choice would be**:
```r
# DON'T DO THIS:
iteration = "list"  # Would create list(0.85, 0.92, 0.67)
                    # Harder to index, more memory
```

---

### ✅ Use `iteration = "list"`
**When**: Each branch returns a STRUCTURED object (list, data frame, etc.)
**Result**: Combined into list `list(obj1, obj2, obj3, ...)`
**Example**:
```r
stac_json_list <- getstac_json(querytable) |> 
  tar_target(pattern = map(querytable), iteration = "list")
# Each branch: returns JSON list with $features, $context, etc.
# Combined: list of JSON results, one per location
```

**Why this matters**:
- Preserves structure of complex objects
- Each element accessed as `stac_json_list[[i]]`

**Wrong choice would be**:
```r
# DON'T DO THIS:
iteration = "vector"  # Would fail - can't combine lists into vector
```

---

### ✅ Use `tar_group()` + `iteration = "group"`
**When**: You want CUSTOM grouping logic (not just one-per-row)
**Result**: N branches (one per unique group defined by `group_by()`)
**Example**:
```r
images_table <- tidyr::unnest(stac_tables_new, cols = c(assets)) |> 
  dplyr::group_by(location, solarday, provider) |> 
  tar_group() |> 
  tar_target(iteration = "group")
# Groups data by unique (location, solarday, provider) combinations
# 20 locations × 5 days × 1 provider = 100 branches
# Each branch: one location-date combination
```

**Why this matters**:
- Flexible grouping: can group by any column combination
- Each branch gets a subset of rows sharing group keys
- Can reference results by group: `scl_tifs[tar_group]`

**Use cases in estinel**:
- Group by `(location, solarday)` → process each location-date
- Regroup after adding columns → maintain parallel structure

---

### ✅ Use `tar_force(force = TRUE)`
**When**: Target should ALWAYS rebuild, ignoring caching
**Result**: Runs every time, even if inputs unchanged
**Example**:
```r
viewtable <- viewtableNA |> 
  dplyr::filter(!is.na(outfile), !is.na(view_q128)) |>
  tar_force(force = TRUE)
# Always rebuilds, even if viewtableNA unchanged
# Useful for URL rewriting that depends on external state
```

**Why this matters**:
- Final outputs that need fresh URLs
- Catalog generation that should always update
- Debugging (force rebuild to test)

**Wrong choice would be**:
```r
# Without tar_force:
tar_target()  # Would cache and skip if inputs unchanged
              # Web catalog might not update
```

---

### ❌ Use NO pattern (static target)
**When**: Process ALL branches together, or single value
**Result**: Single target (1 branch)
**Example**:
```r
markers <- read_markers(bucket, spatial_window) |> 
  tar_target()
# No pattern: reads markers for ALL locations at once
# Takes spatial_window (all 20 branches) as input
# Returns single data frame with all markers
```

**Why this matters**:
- Aggregation points: combine branches into single result
- Static configuration: single values used everywhere
- Batch operations: process multiple items together

**Use cases in estinel**:
- `markers` → read all markers at once
- `query_specs` → prepare all queries in one table
- `viewtable` → combine all results into catalog

---

## Pattern/Iteration Compatibility Matrix

| Pattern | Iteration | Use Case | Example |
|---------|-----------|----------|---------|
| `map()` | `"vector"` | Parallel scalar results | `scl_clear` (one % per image) |
| `map()` | `"list"` | Parallel structured results | `stac_json_list` (JSON per query) |
| `map()` | `"group"` | ❌ Invalid | Don't use together |
| (none) | `"group"` | Custom grouping | `images_table` (group by location+date) |
| (none) | `"vector"` | ❌ Rarely useful | Single vector target |
| (none) | `"list"` | ❌ Rarely useful | Single list target |
| (none) | (none) | Static target | `markers`, `bucket`, `endpoint` |

---

## Decision Tree

```
┌─────────────────────────────────────────────────────┐
│ Do I need to process items independently?           │
└────────────┬────────────────────────────────────────┘
             │
        YES  │  NO → Static target (no pattern)
             ↓
┌─────────────────────────────────────────────────────┐
│ Are items defined by rows in a data frame?          │
└────────────┬────────────────────────────────────────┘
             │
        YES  │  NO → Custom grouping (tar_group)
             ↓
┌─────────────────────────────────────────────────────┐
│ Use pattern = map(dependency)                       │
└─────────────────────────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────────────┐
│ What does each branch return?                       │
└────────────┬────────────────────────────────────────┘
             │
             ├─ Single value → iteration = "vector"
             │
             └─ Structured object → iteration = "list"
```

---

## Common Mistakes to Avoid

### ❌ MISTAKE 1: Missing pattern on dependent target
```r
# WRONG:
scl_tifs <- build_scl_dsn(images_table, root = rootdir) |> 
  tar_target()  # No pattern!

# If images_table has 100 branches, this tries to pass all 100
# as a single argument to build_scl_dsn() → ERROR

# RIGHT:
scl_tifs <- build_scl_dsn(images_table, root = rootdir) |> 
  tar_target(pattern = map(images_table))
# Creates 100 branches, one per images_table branch
```

---

### ❌ MISTAKE 2: Wrong iteration type
```r
# WRONG:
stac_json_list <- getstac_json(querytable) |> 
  tar_target(pattern = map(querytable), iteration = "vector")
# Each branch returns a list (JSON), can't combine into vector → ERROR

# RIGHT:
stac_json_list <- getstac_json(querytable) |> 
  tar_target(pattern = map(querytable), iteration = "list")
# Preserves list structure
```

---

### ❌ MISTAKE 3: Using tar_group() with pattern = map()
```r
# WRONG:
images_table <- ... |> 
  tar_group() |> 
  tar_target(pattern = map(stac_tables), iteration = "group")
# Can't use both map() and tar_group() - they conflict

# RIGHT:
images_table <- ... |> 
  tar_group() |> 
  tar_target(iteration = "group")
# tar_group() creates the branches, no pattern needed
```

---

### ❌ MISTAKE 4: Forgetting tar_group indices
```r
# WRONG:
group_table <- images_table |> 
  mutate(scl_tif = scl_tifs,          # Wrong!
         clear_test = scl_clear)      # Wrong!

# scl_tifs and scl_clear are vectors, but need to match groups
# This would recycle values incorrectly

# RIGHT:
group_table <- images_table |> 
  mutate(scl_tif = scl_tifs[tar_group],     # Correct index
         clear_test = scl_clear[tar_group]) # Correct index
# tar_group is the index that matches the current group
```

---

## Real Examples from Estinel

### Example 1: Location Processing (map)
```r
# 20 locations → 20 independent branches
spatial_window <- mk_spatial_window(tabl) |> 
  tar_target(pattern = map(tabl))

querytable <- getstac_query_adaptive(query_specs, provider, collection) |> 
  tar_target(pattern = map(query_specs))

# Each location processed in parallel
# No dependencies between branches
```

### Example 2: Image Processing (map + vector)
```r
# 100 image groups → 100 branches
scl_tifs <- build_scl_dsn(images_table, root = rootdir) |> 
  tar_target(pattern = map(images_table))

# Each returns a scalar → vector iteration
scl_clear <- filter_fun(read_dsn(scl_tifs)) |> 
  tar_target(pattern = map(scl_tifs), iteration = "vector")

# scl_clear is now c(0.85, 0.92, 0.67, ..., 0.78)
# Length = 100 (one per image)
```

### Example 3: Custom Grouping (tar_group)
```r
# Multiple assets per location-date, need to group
images_table <- tidyr::unnest(stac_tables_new, cols = c(assets)) |> 
  dplyr::group_by(location, solarday, provider) |> 
  tar_group() |> 
  tar_target(iteration = "group")

# Result: One branch per unique (location, solarday, provider)
# Each branch has multiple rows (assets) for that combination
```

### Example 4: Aggregation (no pattern)
```r
# Combine all branches back into single catalog
stac_json_table <- join_stac_json(querytable, stac_json_list) |> 
  tar_target()

# Takes querytable (20 branches) + stac_json_list (20 branches)
# Returns single data frame with all results combined
```

---

## Quick Reference Card

| Target Type | Pattern | Iteration | Branches | Use For |
|-------------|---------|-----------|----------|---------|
| Location loop | `map(tabl)` | - | 20 | Process each location |
| STAC queries | `map(querytable)` | `"list"` | 20 | Parallel queries |
| Cloud detect | `map(scl_tifs)` | `"vector"` | 100 | Scalar results |
| Image groups | - | `"group"` | 100 | Custom grouping |
| Aggregation | - | - | 1 | Combine results |
| Force rebuild | - | - | 1 | `tar_force(TRUE)` |

---

## Summary

**Key Principles**:
1. `pattern = map()` → One branch per row
2. `iteration = "vector"` → Scalar results
3. `iteration = "list"` → Structured results
4. `tar_group()` → Custom grouping
5. No pattern → Aggregation or static

**When in doubt**:
- Parallel processing of rows? → `map()` + appropriate iteration
- Custom groups? → `tar_group()` + `iteration = "group"`
- Combine all results? → No pattern
- Always rebuild? → `tar_force(force = TRUE)`

**Pro tip**: Run `tar_visnetwork()` to visualize your pipeline and see branching!
