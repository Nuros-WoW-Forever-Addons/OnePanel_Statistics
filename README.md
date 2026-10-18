# OnePanel_Statistics

A sleek, modern Character Statistics and records plugin for the **OnePanel Suite** in World of Warcraft, designed exclusively for the **WoW Forever Beta (v1.60.1 / Interface 16001)** runtime.

---

## 🌟 Features

- **OnePanel Docking**: Integrated as **Tab 6** (Parchment Note icon) alongside Character, Reputation, Skills, PvP, and Currency.
- **Hierarchical Collapsible Categories**: Native Blizzard Camelot grey collapsible buttons (`common-button-list-collapseExpand`) for both top-level categories and nested subcategories.
- **Instant Search & Filtering**: Fast keyboard search filter across all character statistics.
- **Interactive Details Drawer**:
  - Selected statistic card with breadcrumb path (`Category > Subcategory`).
  - Large bold numeric or formatted value readout.
  - Lore, criteria, and tracking description text.
- **Responsive Drawer Sync**: Collapses into a compact single-pane view or expands into a dual-pane detailed inspector.

---

## 💻 Commands

- `/op` — Opens the OnePanel interface.
- `/opstat` or `/opstatistics` — Diagnostic slash command to inspect statistics data.

---

## 📦 Dependencies

- **`OnePanel`**: Host canvas frame and tab manager.
- **`OnePanelUtils`**: Shared UI frame helpers, button generators, and event bus.
