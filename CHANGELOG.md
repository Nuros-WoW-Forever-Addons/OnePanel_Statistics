# Changelog — OnePanel_Statistics

All notable changes to **OnePanel_Statistics** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.1] - 2026-10-17
### Added
- **OnePanel Docking**: Registered as Tab 6 (`order = 60`, parchment note icon `INV_Misc_Note_03`) in the OnePanel Suite.
- **Hierarchical Collapsible Categories**:
  - Root categories (Character, Combat, Kills, Quests, Dungeons & Raids, Skills, PvP) and nested subcategories (Wealth, Consumables, Reputation, etc.).
  - Authentic Blizzard disabled metallic grey button banners (`UIPanelButtonTemplate`) with gold text, perfectly matching Character Stats, Skills, and Reputation headers.
  - Indented disabled grey button banners for child subcategories (Wealth, Consumables, Reputation, etc.).
- **Real-Time Search & Quick Actions**:
  - Instant text filter editbox to search across all statistics.
  - "Collapse All / Expand All" silver action button.
- **High-Contrast Statistics Rows**:
  - Stat names on the left (`GameFontHighlight`), numeric or currency values on the right, and `--` placeholders for unrecorded stats.
  - Alternating subtle row backgrounds with mouseover and selection highlights.
- **Interactive Details Drawer**:
  - Displays selected stat card with large title, breadcrumb category path, bold formatted value, and description.
- **Responsive Drawer Sync**: Full integration with `ONEPANEL_EXPAND_STATE_CHANGED` for smooth single/dual pane transitions.
