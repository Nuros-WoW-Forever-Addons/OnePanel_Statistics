# AI Context & Living Specification — OnePanel_Statistics

> **Living Document**: This file serves as the primary context, architectural specification, and state-handoff document for AI-assisted development across sessions. Update this file on every development cycle ("spin").

---

## 🎯 Overview & Scope

- **Addon Name**: OnePanel_Statistics
- **Current Version**: 0.0.1
- **Suite**: Part of the **OneSuite** family (OnePanel Plugin)
- **GitHub Repository**:
  - Exists: TRUE
  - URL: https://github.com/Nuros-WoW-Forever-Addons/OnePanel_Statistics
- **Branching Policy**: All development must occur on a feature branch != `main` (e.g. `dev`)
- **Live Sync Path**: `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/OnePanel_Statistics/`
- **Rollback Target**: Last working `main` branch commit
- **Release Package**: `.github/workflows/package.yml` generates `OnePanel_Statistics-latest.zip` on push to `main`
- **Dependencies**: `OnePanel`, `OnePanelUtils`
- **Target WoW Runtimes**: WoW Forever Beta (v1.60.1 / Interface 16001)
- **Primary Goal**: Deliver a modern, authentic Character Statistics tracking interface docked into OnePanel as Tab 6, featuring real-time search filtering, collapsible category and subcategory headers with standard Camelot grey button styling, high-contrast numeric values, and an interactive right-hand details drawer displaying career extremes, category breadcrumbs, and flavor descriptions.

---

## 🏗️ Architecture & Component Map

### File Structure
- `OnePanel_Statistics.toc`: Manifest, declares dependencies on `OnePanel` and `OnePanelUtils`.
- `Core.lua`: Complete plugin implementation:
  - Hierarchical category tree utilizing `GetStatisticsCategoryList()`, `GetCategoryInfo(categoryID)`, and `GetCategoryNumAchievements(categoryID)`.
  - Statistics data retrieval via `GetStatistic(categoryID, index)` and `GetAchievementInfo(statID)`.
  - Collapsible category and subcategory headers styled with Blizzard Camelot `common-button-list-collapseExpand` buttons and plus/minus icons (`common-button-list-plus` / `common-button-list-minus`).
  - High-contrast statistics rows (Name on the left, formatted value on the right, `--` placeholder for unrecorded stats).
  - Search filter editbox with instant clear and "Collapse All / Expand All" silver action buttons.
  - Interactive right-hand details drawer displaying selected statistic cards, breadcrumbs (`Category > Subcategory`), large numeric values, and descriptions.
  - Event listeners: `CRITERIA_UPDATE`, `ACHIEVEMENT_EARNED`, `PLAYER_ENTERING_WORLD`.
  - Plugin registration with OnePanel (`OnePanel:RegisterPlugin`, `order = 60`).

### Registration Payload with OnePanel
```lua
OnePanel:RegisterPlugin({
    id = "Statistics",
    title = "Statistics",
    icon = "Interface\\Icons\\INV_Misc_Note_03",
    order = 60,
    CreateView = CreateStatisticsView,
    OnShow = function(container) ... end,
    OnHide = function(container) ... end,
})
```

---

## 🔄 AI Development Cycle & Handoff Protocol

When picking up development on this addon:

1. **Orientation**: Read `CONTEXT.md` (this file) to verify current state, known issues, and active backlog items.
2. **Implementation**: Execute changes. For code refactoring or boilerplate, delegate to `qwen2.5-coder:32b` via the local `gx10_ollama` MCP server as mandated by user rules.
3. **Verification**: Verify in-game syntax with `luac -p` and test in-game using `/op` or Tab 6.
4. **Handoff Update**:
   - Move completed tasks from **Upcoming Backlog** to **Recent Completed Work**.
   - If user-facing features or commands changed, update `README.md` and append a new section in `CHANGELOG.md`.
   - Document newly discovered backlog items or edge cases in **Upcoming Backlog**.

---

## ✅ Recent Completed Work (Latest Spins)

### Spin 0.0.1 (Initial Implementation & OnePanel Integration)
- **Plugin Scaffolding**: Created manifest, documentation, workflow, and registered as Tab 6 (`order = 60`) with parchment note icon (`INV_Misc_Note_03`).
- **Hierarchical Category Tree**: Extracted root and child categories from `GetStatisticsCategoryList()` (Character, Combat, Kills, Quests, Dungeons & Raids, Skills, PvP).
- **Blizzard Camelot Grey Header Buttons**: Adopted authentic `common-button-list-collapseExpand` buttons with plus/minus icons for root categories and indented subcategories (e.g. Wealth, Consumables, Reputation).
- **Formatted Statistics Rows**: Comma-separated numbers, clean `--` formatting, alternating subtle row backgrounds, and hover highlights.
- **Side Details Drawer**: Interactive statistics card with large title, breadcrumb category path, bold value display, and description text.
- **Search & Collapse Controls**: Real-time instant search box with clear button and "Collapse All / Expand All" toggle.

---

## 📋 Living Roadmap & Upcoming Backlog (Next Spins)

### Priority 1: High Priority (Immediate Next Spin)
- [ ] **Career Highlights Card**: Quick-glance top stats (Highest Crit, Most Gold, Total Deaths) in the details drawer when no stat is selected.
- [ ] **Comparison Stat Integration**: Compare stats against target player when inspecting.

### Priority 2: Medium Priority (Enhancements)
- [ ] **Favorite Stats Pinning**: Allow players to bookmark favorite statistics to a top "Favorites" category.

---

## 🧪 Testing & Verification Guide

- **Open Panel**: Press `C` or open OnePanel and click Tab 6 (Parchment Note icon).
- **Category Check**: Confirm Character, Combat, Kills, Quests, etc. appear with grey collapsible headers.
- **Subcategory Check**: Verify nested categories like Wealth and Consumables appear indented with working expand/collapse.
- **Stat Values**: Verify numbers display correctly (e.g. Times camped: 16, Food eaten: 13, Bandages used: 5).
- **Details Drawer**: Click any stat row to verify the right-hand drawer displays breadcrumbs and large stat readout.

---

## ⚠️ Technical Constraints & Engine Gotchas

- **Parent Category IDs**: `parentCategoryID == -1` indicates a root category; non-(-1) indicates a child subcategory.
- **Formatted Strings**: `GetStatistic` may return pre-formatted strings (like money with coin icons) or numbers. Display strings as-is and format numbers with commas.
