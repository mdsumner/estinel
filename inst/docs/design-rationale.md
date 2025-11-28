# Satellite Image Browser: Design Rationale

## Project Overview

The Estinel Satellite Image Browser is a web-based tool for viewing, comparing, and classifying Sentinel-2 satellite imagery. Built as a single-page HTML application with React, it enables collaborative image quality assessment across multiple locations and time series.

**Project Context:**
- **Data Source:** Sentinel-2 imagery queried from element84.com
- **Processing:** GDAL and R targets package
- **Hosting:** Pawsey Supercomputing Research Centre
- **Development:** Built collaboratively with Claude AI
- **Repository:** https://github.com/mdsumner/estinel

---

## Core Design Principles

### 1. **Simplicity and Accessibility**
- Single HTML file deployment - no build process, no server required
- Works offline once loaded (except for image fetching)
- No dependencies beyond CDN-hosted React and Tailwind CSS
- Accessible via any modern web browser

### 2. **Progressive Enhancement**
- Start with basic browsing functionality
- Add features incrementally based on real user needs
- Each feature should stand alone and not break existing workflows

### 3. **Collaborative by Default**
- Export/import rating system for sharing classifications
- User ID tracking for accountability
- Timestamp preservation for audit trails
- URL-based import for community aggregation

---

## Major Design Decisions

## 1. View Modes

### Decision: Three Distinct Modes
- **Single View** - Full-screen individual image review
- **Slider Mode** - Overlay comparison with draggable divider
- **Side-by-Side Mode** - Dual image comparison

### Rationale:
Different tasks require different comparison methods:
- **Single view** is optimal for rating/classification workflows
- **Slider mode** excels at detecting changes between time periods (before/after)
- **Side-by-side** allows independent examination of two images

### Alternative Considered:
Single unified view with optional comparison overlay
- **Rejected because:** Different use cases benefit from purpose-built interfaces
- **Trade-off:** Slightly more complex UI, but much better task-specific experience

### Default Selection:
**Single view** chosen as default after initial development
- **Original default:** Slider mode (emphasizing comparison)
- **Changed to:** Single view (prioritizing classification workflow)
- **Reason:** As rating became the primary use case, single view with keyboard shortcuts proved most efficient

---

## 2. Navigation System

### Decision: Hybrid Keyboard/Mouse Navigation
- Arrow keys for sequential browsing
- Thumbnail grid for random access
- Auto-scroll to keep current image visible

### Rationale:
Expert users benefit enormously from keyboard shortcuts:
- Faster than mouse clicking
- Reduces cognitive load
- Enables rapid classification workflows
- "Rate and Next" mode allows one-handed operation (1-2-3 keys + arrow)

### Keyboard Shortcuts Implemented:
- `←/→` - Navigate images
- `1/2/3` - Quick rating (Good/OK/Bad)
- `G` - Toggle thumbnail panel
- `C` - Toggle crosshair
- `Space` - Play/pause slideshow
- `?` - Toggle help

### Alternative Considered:
Mouse-only interface with on-screen buttons
- **Rejected because:** Too slow for expert users processing hundreds of images
- **Compromise:** Full mouse support remains for casual users

---

## 3. Rating System

### Decision: Three-Category Classification (Good/OK/Bad)
Originally considered four categories (Good/OK/Bad/Clear), reduced to three.

### Rationale:
- **Simple enough** for quick decisions
- **Granular enough** to be useful for filtering
- **Clear semantics** - quality assessment rather than image properties
- **Fast input** - single keystroke per rating

### Alternative Considered:
Five-star rating system
- **Rejected because:** Too granular for binary quality decisions (usable vs. not usable)
- **Trade-off:** Lost nuance, gained speed

### Alternative Considered:
"Clear" as a fourth category (for cloud-free images)
- **Removed because:** Overlaps with "Good" - a good satellite image is typically cloud-free
- **Decision point:** Could be reintroduced if users need to distinguish quality from cloudiness

### Storage Design:
LocalStorage for immediate persistence + JSON export for sharing
- **Pro:** No server required, works offline
- **Pro:** User maintains full control of their data
- **Con:** Limited to single browser (mitigated by export/import)

---

## 4. Filter System

### Decision: Multi-Select Checkbox Filters
Users can view any combination of Good/OK/Bad/Unrated images simultaneously.

### Evolution:
1. **Initial design:** Single-select dropdown (show one category at a time)
2. **User request:** "Can we see unrated + good together?"
3. **Final design:** Multi-select checkboxes

### Rationale:
Multi-select enables flexible workflows:
- Review all rated images (Good + OK + Bad)
- Focus on unrated images only
- Check quality across Good + OK categories
- Custom combinations for specific review needs

### Alternative Considered:
Single-select with "All" option
- **Rejected because:** Forces users into predefined combinations
- **Trade-off:** Slightly more complex UI, much more flexible

### Filter Scope Decision:
Filters apply to **visible images** not to **sort order**
- **Rationale:** Stable, predictable behavior
- **Sort order** reflects overall data freshness (max date per location)
- **Filters** let users drill into specific quality levels within each location
- **Alternative considered:** Filter-aware sorting (e.g., "locations with most recent good images")
  - **Deferred:** Added complexity without clear user need
  - **Future:** Can be added based on expert feedback

---

## 5. Location Sorting

### Decision: Dual Sort Modes (Recent First / Alphabetical)

### Sort by Most Recent (Default):
- Shows locations with newest imagery first
- Displays latest date in dropdown
- Helps prioritize fresh data

### Sort Alphabetically:
- Traditional A-Z ordering
- Useful for systematic review

### Rationale:
Different organizational needs:
- **Recent-first** prioritizes timely review of new data
- **Alphabetical** supports methodical coverage

### UI Placement Decision:
Sort button placed **left** of location dropdown
- **Alternative considered:** Right of dropdown
- **Rejected because:** Caused jarring UI shift on toggle (dropdown width changes when showing dates)
- **Better UX:** Fixed button position, expanding dropdown to the right

### Auto-Selection on Sort:
When sort order changes, first location in new order is auto-selected
- **Rationale:** Immediate jump to "most recent" or "first alphabetical" location
- **Makes sort more actionable** - not just reordering, but navigation

---

## 6. Playback System

### Decision: Automated Slideshow with Speed Control

### Speed Options:
- Very Fast (0.1s)
- Fast (0.3s)
- Medium-Fast (0.5s)
- Medium (1s) - default
- Slow (2s)
- Very Slow (3s)

### Rationale:
Users discovered value in "holding down arrow key" to create animation
- **Formalized** this into proper playback feature
- **Added control** - consistent timing, pause/resume
- **Use cases:**
  - Quick overview of time series
  - Pattern detection across many images
  - Presentation/demo mode
  - Review of rated images as "highlight reel"

### Alternative Considered:
Fixed-speed playback only
- **Rejected because:** Different use cases need different speeds
- Very fast (0.1s) for rapid scanning
- Slow (2-3s) for detailed examination

### Scope Limitation:
Playback only available in **single view mode**
- **Rationale:** Unclear what playback means in comparison modes
- **Simplifies implementation** and user mental model

---

## 7. Import/Export System

### Decision: JSON-Based with Multiple Import Methods

### Export Format:
```json
{
  "user_id": "user_1234567890_xyz",
  "timestamp": "2024-11-29T10:30:00Z",
  "location": "Site A - Forest",
  "ratings": [
    {
      "image_id": "loc_001_img_042",
      "rating": "good",
      "timestamp": "2024-11-29T10:25:00Z"
    }
  ]
}
```

### Import Methods:
1. **File upload** - Traditional file picker
2. **URL import** - Fetch from web address

### Rationale for Dual Import:
- **File upload:** Standard, works offline, familiar to users
- **URL import:** Enables community aggregation, version control integration
  - Can host `community-ratings.json` alongside catalog
  - Users can easily import shared classifications
  - Future: Auto-load default ratings on startup

### Data Merge Strategy:
Imported ratings are **merged** with existing, not replaced
- **Rationale:** Allows incremental updates and multi-source aggregation
- **Trade-off:** No built-in conflict resolution (last write wins)
- **Future:** Could add timestamp-based conflict resolution if needed

### User ID Design:
Auto-generated, stored in localStorage
- Format: `user_[timestamp]_[random]`
- **Rationale:** Simple accountability without authentication burden
- **Alternative considered:** Manual username entry
  - **Rejected:** Extra friction, typo risk
  - **Compromise:** User ID shown in UI, can be referenced if needed

---

## 8. Statistics Display

### Decision: Dual-Level Statistics (Location + Overall)

### Display Hierarchy:
1. **Current Location** (top) - Ratings for selected location only
2. **All Locations** (bottom) - Aggregate across entire catalog

### Rationale:
Different questions need different scopes:
- "Am I done with this location?" → Location stats
- "How much work is left overall?" → Overall stats
- "Which location needs attention?" → Compare location stats

### Alternative Considered:
Single overall statistics
- **Rejected because:** Users needed to track progress per-location
- **Workflow:** Rate entire location, move to next location

### Visual Design:
Color-coded bars matching rating categories
- Green (Good), Yellow (OK), Red (Bad), Gray (Unrated)
- **Rationale:** Instant visual recognition, consistent with thumbnail dots

---

## 9. "Rate and Next" Feature

### Decision: Optional Auto-Navigation to Next Unrated Image

### Workflow:
1. User enables "Rate and Next" toggle
2. Press 1, 2, or 3 to rate current image
3. Browser automatically jumps to next unrated image
4. Repeat

### Rationale:
Rapid classification workflow optimization:
- **Eliminates** manual navigation between ratings
- **Reduces** classification time by ~50%
- **One-handed operation** - just press 1/2/3 repeatedly
- **Respects filters** - only searches within visible filtered images

### Design Choice: Toggle (Not Always-On):
- **Rationale:** Sometimes users want to rate without jumping
  - Re-rating previously classified images
  - Rating while comparing with neighbors
  - Exploratory browsing
- **Default:** Off (less surprising behavior for new users)

### Search Algorithm:
1. Search forward from current position
2. Wrap around to beginning if needed
3. Return null if no unrated images found

**Filter-aware:** Searches only within currently filtered images
- **Rationale:** User's filter choice indicates intent
- **Example:** If viewing only "Unrated" images, finds next unrated
- **Example:** If viewing "Unrated + Good", cycles through that subset

---

## 10. Thumbnail System

### Decision: Grid Display with Filter-Based Visibility

### Visual Indicators:
- **Border color:** Blue (current in single), Green (active in compare), Gray (inactive)
- **Corner dot:** Colored by rating (Green/Yellow/Red/Blue)
- **Numbering:** Original position in full sequence (not filtered position)

### Filter Behavior:
Thumbnails show only images matching active filters
- **Rationale:** Reduces clutter, focuses attention
- **Trade-off:** Can't see full context
- **Mitigation:** Count shown in header "Site Name (X shown)"

### Alternative Considered:
Show all thumbnails, dim unfiltered ones
- **Rejected because:** Visual clutter with hundreds of images
- **Use case:** If users need context, they can enable all filters

### Scroll Behavior:
Auto-scroll to keep current image visible
- **Challenge:** Indices shift when filters change
- **Solution:** Track by image ID, not index position

---

## 11. Crosshair Feature

### Decision: Optional Center Crosshair Overlay

### Purpose:
- Consistent reference point across images
- Useful for comparing exact same location
- Helps detect subtle changes

### Design:
- Red crosshair, 60×60px
- Centered on image
- Gaps in center (to see underlying pixels)
- Toggle with 'C' key

### Rationale:
Simple but effective tool for precise comparison
- **Use case:** "Is this building in the same position?"
- **Use case:** "Where exactly did the coastline change?"

### Alternative Considered:
Grid overlay or measurement tools
- **Deferred:** More complex, less clear immediate value
- **Future:** Could add if users request precise measurements

---

## 12. View Type Support

### Decision: Multi-View Type Architecture

### Implementation:
Images can have multiple view types (e.g., different color balances)
```json
{
  "url": {
    "true_color": "path/to/true_color.png",
    "false_color": "path/to/false_color.png"
  }
}
```

### Rationale:
Satellite imagery benefits from different visualizations:
- True color (what eye would see)
- False color (emphasizing vegetation)
- Other band combinations for specific analyses

### UI Treatment:
- Dropdown appears when multiple view types available
- Applies to all images in current session
- Persists across navigation

### Future Enhancement:
Currently supports simple string URLs or object with named views
- Could be extended to support per-image view type selection
- Could add view type descriptions/tooltips

---

## 13. Help System

### Decision: Comprehensive In-App Documentation

### Content Structure:
1. **Navigation** - Movement and controls
2. **View Modes** - Comparison techniques
3. **Rating System** - Classification workflow
4. **Files Available** - Data access information
5. **R Integration** - Code examples for analysts
6. **Project Attribution** - Credits and links

### Rationale:
Self-documenting application reduces support burden:
- Users can discover features
- Reduces training time
- Provides copy-paste examples (R code)
- Credits contributors and data sources

### Toggle Design:
Press `?` to show/hide
- **Rationale:** Common convention (GitHub, GMail, etc.)
- **Non-modal:** Doesn't block interaction
- **Dismissible:** Easy to hide once familiar

---

## Technical Architecture Decisions

### Single-File Application

**Decision:** Entire application in one HTML file

**Rationale:**
- **Deployment:** Copy file to any web server
- **Distribution:** Email, USB drive, git repository
- **Versioning:** Single file = single version
- **Reliability:** No broken dependencies

**Trade-offs:**
- Larger initial download (~100KB)
- Can't split-load features
- **Acceptable because:** Modern browsers, fast networks, small file size

### React Without Build Process

**Decision:** Use React via CDN with Babel standalone

**Rationale:**
- Modern component-based UI
- No build step required
- Works in any browser
- Developers can read/modify source directly

**Trade-offs:**
- Runtime JSX compilation (slight performance cost)
- Larger bundle than compiled version
- **Acceptable because:** User interaction speed dominates, not render speed

### LocalStorage for Ratings

**Decision:** Browser LocalStorage as primary data store

**Rationale:**
- Instant persistence (no server round-trip)
- Works offline
- Simple API
- No authentication needed
- Privacy-preserving (data stays on device)

**Trade-offs:**
- Limited to ~5-10MB per domain
- Doesn't sync across devices
- Can be cleared by user
- **Mitigated by:** Export/import functionality

### Catalog Format

**Decision:** JSON catalog with locations → images hierarchy

```json
{
  "locations": [
    {
      "id": "loc_001",
      "name": "Site A - Forest",
      "images": [
        {
          "id": "loc_001_img_001",
          "url": "...",
          "date": "2024-01-15",
          "thumbnail": "...",
          "download": "...",
          "stac-item": "..."
        }
      ]
    }
  ]
}
```

**Rationale:**
- Human-readable
- Easy to generate from processing pipeline
- Simple to parse in JavaScript
- Extensible (add new fields without breaking)

**Future Enhancement:**
Could add `rating` field to images once community ratings are aggregated:
```json
{
  "id": "loc_001_img_001",
  "rating": "good",
  "rating_count": 5,
  "rating_consensus": 0.8
}
```

---

## Design Patterns and Conventions

### State Management
- React hooks (useState, useEffect) for simplicity
- No Redux or external state management
- **Rationale:** Application complexity doesn't justify additional abstraction

### Error Handling
- Graceful degradation (sample data if catalog fails to load)
- User-friendly alerts for import errors
- **Design principle:** Never crash, always show something useful

### Responsive Design
- Fixed layout optimized for desktop
- Minimum viable width ~1024px
- **Rationale:** Satellite imagery review requires screen real estate
- **Trade-off:** Not mobile-optimized (acceptable for expert tool)

### Color Scheme
- Dark theme (gray-900 background)
- High contrast for readability
- Color-coded ratings (Green/Yellow/Red)
- **Rationale:** Reduces eye strain during long review sessions

---

## Future Enhancement Possibilities

Based on design decisions and user feedback potential:

### Short-term Enhancements:
1. **Auto-load community ratings** - Default URL for shared classifications
2. **Rating notes** - Optional text comments per image
3. **Bulk operations** - Rate multiple images at once
4. **Keyboard shortcuts customization** - User-defined key bindings
5. **Export filtered subset** - Export only currently visible images

### Medium-term Enhancements:
1. **Advanced filtering** - Date ranges, cloud cover, season
2. **Tagging system** - Custom labels beyond Good/OK/Bad
3. **Comparison bookmarks** - Save specific image pairs
4. **Statistics export** - CSV of rating distributions
5. **Multi-user merge** - Intelligent conflict resolution

### Long-term Possibilities:
1. **Integrated classification catalog** - Ratings baked into main catalog
2. **Machine learning integration** - Auto-suggest ratings based on patterns
3. **Change detection highlighting** - Automatic difference visualization
4. **Measurement tools** - Distance, area calculations
5. **Time-series analysis** - Trend visualization across dates

---

## Lessons Learned

### What Worked Well:

1. **Iterative development** - Start simple, add features based on real use
2. **Keyboard-first design** - Expert users benefit enormously
3. **Export/import early** - Enables collaboration from day one
4. **Single-file deployment** - Dramatically simplifies distribution
5. **User feedback integration** - Real usage reveals unexpected needs (playback, URL import)

### What We'd Do Differently:

1. **Mobile consideration** - Even if not primary target, basic support would be nice
2. **Accessibility** - Could improve keyboard navigation announcement
3. **Testing framework** - Would benefit from automated testing
4. **Performance monitoring** - Track loading times for large catalogs

### Key Design Philosophy:

**"Build the minimum viable feature, then iterate based on actual usage"**

Rather than trying to predict every need upfront, we:
- Shipped early with basic browsing
- Observed actual usage patterns
- Added features that solved real problems
- Deferred speculative features

This resulted in a tool that's genuinely useful today, while remaining extensible for tomorrow's needs.

---

## Conclusion

The Estinel Satellite Image Browser represents a pragmatic approach to collaborative scientific data review. By prioritizing simplicity, keyboard efficiency, and collaborative workflows, it enables experts to rapidly classify satellite imagery while maintaining flexibility for future enhancements.

The design deliberately avoids premature optimization, instead focusing on:
- **Immediate utility** - Works well for current needs
- **Low friction** - Easy to start using, easy to share
- **Future-ready** - Architecture supports natural evolution

As expert users provide feedback on real classification workflows, the system can grow organically to support more sophisticated needs while maintaining its core simplicity.

---

**Document Version:** 1.0  
**Date:** November 29, 2024  
**Author:** Designed collaboratively with Claude AI  
**Project:** https://github.com/mdsumner/estinel