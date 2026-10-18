--[[
    OnePanel_Statistics - Core.lua
    Character Statistics, achievements, and records plugin for OnePanel Suite.
    Designed exclusively for WoW Forever Beta (Interface 16001 / Camelot).
--]]

local addonName, addonTable = ...
local OnePanel = _G.OnePanel
local Utils = _G.OnePanelUtils

-------------------------------------------------------------------------------
-- Constants & Font Helpers
-------------------------------------------------------------------------------

local ROOT_CATEGORY_ID = -1

local function GetStandardFont()
    local fontObj = _G.GameFontHighlight or _G.SystemFont_Med1 or _G.GameFontNormal
    if fontObj and fontObj.GetFont then
        local fontPath = fontObj:GetFont()
        if fontPath and fontPath ~= "" then return fontPath end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function SafeHasAtlas(atlasName)
    if not atlasName then return false end
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlasName)
        return ok and info ~= nil
    end
    return false
end

local function FormatNumber(value)
    if not value then return "0" end
    local formatted = tostring(math.floor(value))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function CreateSilverActionButton(parent, name, text)
    local btn
    if Utils and Utils.FrameHelper and Utils.FrameHelper.CreateSilverButton then
        btn = Utils.FrameHelper:CreateSilverButton(parent, name, text)
    else
        btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
        if btn.SetText then btn:SetText(text) end
    end
    return btn
end

-------------------------------------------------------------------------------
-- Safe WoW Engine API Wrappers for Statistics
-------------------------------------------------------------------------------

local function SafeGetStatisticsCategoryList()
    if GetStatisticsCategoryList then
        local ok, list = pcall(GetStatisticsCategoryList)
        if ok and type(list) == "table" then
            return list
        elseif ok and list then
            -- Fallback if returned as packed arguments
            return { GetStatisticsCategoryList() }
        end
    end
    return {}
end

local function SafeGetCategoryInfo(categoryID)
    if not categoryID then return "Unknown", ROOT_CATEGORY_ID end
    if GetCategoryInfo then
        local ok, name, parentID = pcall(GetCategoryInfo, categoryID)
        if ok and name then
            return name, parentID or ROOT_CATEGORY_ID
        end
    end
    return "Unknown", ROOT_CATEGORY_ID
end

local function SafeGetCategoryNumAchievements(categoryID)
    if not categoryID then return 0 end
    if GetCategoryNumAchievements then
        local ok, num = pcall(GetCategoryNumAchievements, categoryID)
        if ok and type(num) == "number" then
            return num
        end
    end
    return 0
end

local function SafeGetStatistic(categoryID, statIndex)
    if not categoryID or not statIndex then return nil, true, nil end
    if GetStatistic then
        local ok, quantity, skip, statID = pcall(GetStatistic, categoryID, statIndex)
        if ok then
            return quantity, skip, statID
        end
    end
    return nil, true, nil
end

local function SafeGetAchievementInfo(statID)
    if not statID then return nil end
    if GetAchievementInfo then
        local ok, id, name, points, completed, month, day, year, description, flags, icon = pcall(GetAchievementInfo, statID)
        if ok and name then
            return {
                id = id or statID,
                name = name,
                description = description or "",
                icon = icon or "Interface\\Icons\\INV_Misc_Note_03",
            }
        end
    end
    return { id = statID, name = "Unknown Statistic", description = "", icon = "Interface\\Icons\\INV_Misc_Note_03" }
end

-------------------------------------------------------------------------------
-- Statistics Data Hierarchy Engine
-------------------------------------------------------------------------------

local function BuildStatisticsTree()
    local rawCategories = SafeGetStatisticsCategoryList()
    local rootCategories = {}
    local subcategoriesByParent = {}

    -- First pass: discover root and subcategories
    for _, catID in ipairs(rawCategories) do
        local catName, parentID = SafeGetCategoryInfo(catID)
        if parentID == ROOT_CATEGORY_ID then
            table.insert(rootCategories, {
                categoryID = catID,
                name = catName,
                isChild = false,
                subcategories = {},
                stats = {},
            })
        else
            subcategoriesByParent[parentID] = subcategoriesByParent[parentID] or {}
            table.insert(subcategoriesByParent[parentID], {
                categoryID = catID,
                name = catName,
                parentCategoryID = parentID,
                isChild = true,
                stats = {},
            })
        end
    end

    -- Second pass: link subcategories to parents and collect stats
    for _, root in ipairs(rootCategories) do
        -- Collect direct root stats
        local numStats = SafeGetCategoryNumAchievements(root.categoryID)
        for i = 1, numStats do
            local quantity, skip, statID = SafeGetStatistic(root.categoryID, i)
            if not skip and statID then
                local info = SafeGetAchievementInfo(statID)
                table.insert(root.stats, {
                    statID = statID,
                    categoryID = root.categoryID,
                    categoryName = root.name,
                    parentCategoryName = nil,
                    name = info.name,
                    description = info.description,
                    icon = info.icon,
                    quantity = quantity,
                })
            end
        end

        -- Attach subcategories
        local children = subcategoriesByParent[root.categoryID]
        if children then
            for _, child in ipairs(children) do
                local childStats = SafeGetCategoryNumAchievements(child.categoryID)
                for k = 1, childStats do
                    local quantity, skip, statID = SafeGetStatistic(child.categoryID, k)
                    if not skip and statID then
                        local info = SafeGetAchievementInfo(statID)
                        table.insert(child.stats, {
                            statID = statID,
                            categoryID = child.categoryID,
                            categoryName = child.name,
                            parentCategoryName = root.name,
                            name = info.name,
                            description = info.description,
                            icon = info.icon,
                            quantity = quantity,
                        })
                    end
                end
                table.insert(root.subcategories, child)
            end
        end
    end

    return rootCategories
end

local function FormatStatValue(quantity)
    if not quantity or quantity == "" then
        return "--"
    end

    local num = tonumber(quantity)
    if num then
        if num > 0 then
            return FormatNumber(num)
        else
            return "--"
        end
    end

    -- Return pre-formatted string (e.g. money strings with coin icons)
    return tostring(quantity)
end

-------------------------------------------------------------------------------
-- Master View Construction
-------------------------------------------------------------------------------

local function CreateStatisticsView(parentFrame)
    local container = CreateFrame("Frame", "OnePanel_StatisticsContainer", parentFrame)
    container:SetAllPoints(parentFrame)

    local searchQuery = ""
    local selectedStatID = nil
    local selectedStatData = nil

    -- Track collapsed states by categoryID (default: first root category expanded, others collapsed)
    local collapsedCategories = {}
    local initialSetupDone = false

    ---------------------------------------------------------------------------
    -- Left Area: Scrollable Statistics List & Search Filter
    ---------------------------------------------------------------------------

    local leftArea = CreateFrame("Frame", "OnePanel_StatisticsLeftArea", container)
    leftArea:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    leftArea:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    leftArea:SetWidth(338)
    container.LeftArea = leftArea

    -- Top Control Bar
    local topBar = CreateFrame("Frame", "OnePanel_StatisticsTopBar", leftArea)
    topBar:SetPoint("TOPLEFT", leftArea, "TOPLEFT", 12, -42)
    topBar:SetPoint("TOPRIGHT", leftArea, "TOPRIGHT", -12, -42)
    topBar:SetHeight(26)

    -- Search EditBox
    local searchBox = CreateFrame("EditBox", "OnePanel_StatisticsSearchBox", topBar, "InputBoxTemplate")
    searchBox:SetSize(130, 24)
    searchBox:SetPoint("LEFT", topBar, "LEFT", 2, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetFont(GetStandardFont(), 13, "")
    searchBox:SetShadowOffset(1, -1)
    searchBox:SetShadowColor(0, 0, 0, 1)

    local searchHint = searchBox:CreateFontString(nil, "OVERLAY")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    searchHint:SetFont(GetStandardFont(), 13, "")
    searchHint:SetTextColor(0.5, 0.5, 0.5, 1)
    searchHint:SetShadowOffset(1, -1)
    searchHint:SetShadowColor(0, 0, 0, 1)
    searchHint:SetText("Search statistics...")
    searchBox.Hint = searchHint

    local clearSearchBtn = CreateFrame("Button", nil, searchBox)
    clearSearchBtn:SetSize(16, 16)
    clearSearchBtn:SetPoint("RIGHT", searchBox, "RIGHT", -4, 0)
    clearSearchBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clearSearchBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    clearSearchBtn:Hide()

    clearSearchBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)

    local RefreshList = nil -- Forward declaration

    searchBox:SetScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
        searchQuery = string.lower(text or "")
        searchHint:SetShown(searchQuery == "")
        clearSearchBtn:SetShown(searchQuery ~= "")
        if RefreshList then RefreshList() end
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Collapse / Expand All Button
    local toggleAllBtn = CreateSilverActionButton(topBar, "OnePanel_StatisticsToggleAllBtn", "Collapse All")
    toggleAllBtn:SetSize(88, 24)
    toggleAllBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)

    local allCollapsed = false
    toggleAllBtn:SetScript("OnClick", function(self)
        allCollapsed = not allCollapsed
        local tree = BuildStatisticsTree()
        for _, root in ipairs(tree) do
            collapsedCategories[root.categoryID] = allCollapsed
            for _, sub in ipairs(root.subcategories) do
                collapsedCategories[sub.categoryID] = allCollapsed
            end
        end
        self:SetText(allCollapsed and "Expand All" or "Collapse All")
        if RefreshList then RefreshList() end
    end)

    -- Total Tracked Statistics Summary
    local summaryText = topBar:CreateFontString(nil, "OVERLAY")
    summaryText:SetPoint("RIGHT", topBar, "RIGHT", -2, 0)
    summaryText:SetJustifyH("RIGHT")
    summaryText:SetFont(GetStandardFont(), 13, "")
    summaryText:SetShadowOffset(1, -1)
    summaryText:SetShadowColor(0, 0, 0, 1)
    summaryText:SetTextColor(0.85, 0.85, 0.85, 1)
    topBar.SummaryText = summaryText

    -- Scroll View Container
    local scrollFrame = CreateFrame("ScrollFrame", "OnePanel_StatisticsScrollFrame", leftArea, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", leftArea, "BOTTOMRIGHT", -14, 10)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = 34
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - (delta * step))))
    end)

    local scrollBarName = scrollFrame:GetName() .. "ScrollBar"
    local scrollBar = _G[scrollBarName]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 18)
        scrollBar:SetValueStep(34)

        local upBtn = _G[scrollBarName .. "ScrollUpButton"]
        local downBtn = _G[scrollBarName .. "ScrollDownButton"]
        if upBtn then
            upBtn:SetScript("OnClick", function()
                local cur = scrollFrame:GetVerticalScroll()
                scrollFrame:SetVerticalScroll(math.max(0, cur - 34))
            end)
        end
        if downBtn then
            downBtn:SetScript("OnClick", function()
                local cur = scrollFrame:GetVerticalScroll()
                local maxScroll = scrollFrame:GetVerticalScrollRange()
                scrollFrame:SetVerticalScroll(math.min(maxScroll, cur + 34))
            end)
        end
    end

    local listContent = CreateFrame("Frame", "OnePanel_StatisticsListContent", scrollFrame)
    listContent:SetSize(288, 400)
    scrollFrame:SetScrollChild(listContent)
    listContent.rows = {}

    ---------------------------------------------------------------------------
    -- Right Area: Collapsible Side Details Panel
    ---------------------------------------------------------------------------

    local subPanel = CreateFrame("Frame", "OnePanel_StatisticsSubPanel", container)
    subPanel:SetPoint("TOPRIGHT", container, "TOPRIGHT", -6, -12)
    subPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 12)
    subPanel:SetWidth(198)
    container.SubPanel = subPanel

    -- Vertical Metal Divider separating list from details
    local vDivider = container:CreateTexture("OnePanel_StatisticsVerticalDivider", "OVERLAY", nil, 2)
    vDivider:SetTexture("Interface\\FrameGeneral\\UIFrameMetalVertical")
    vDivider:SetTexCoord(258/512, 265/512, 0, 1)
    vDivider:SetVertTile(true)
    vDivider:SetWidth(7)
    vDivider:SetPoint("TOP", leftArea, "TOPRIGHT", 1, 10)
    vDivider:SetPoint("BOTTOM", leftArea, "BOTTOMRIGHT", 1, -14)
    container.VerticalDivider = vDivider

    -- Native Right-Side Collapse / Expand Toggle Button
    local toggleBtn = CreateFrame("Button", "OnePanel_StatisticsSideToggleButton", leftArea)
    toggleBtn:SetSize(28, 28)
    toggleBtn:SetPoint("TOPRIGHT", leftArea, "TOPRIGHT", -14, -18)

    toggleBtn.Icon = toggleBtn:CreateTexture(nil, "ARTWORK")
    toggleBtn.Icon:SetAllPoints(toggleBtn)

    function toggleBtn:UpdateIcon()
        local isExp = OnePanel.isExpanded ~= false
        if isExp then
            if SafeHasAtlas("charactercreate-icon-customize-collapse-right") then
                self.Icon:SetAtlas("charactercreate-icon-customize-collapse-right")
            else
                self.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
            end
        else
            if SafeHasAtlas("charactercreate-icon-customize-collapse-left") then
                self.Icon:SetAtlas("charactercreate-icon-customize-collapse-left")
            else
                self.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            end
        end
    end
    toggleBtn:UpdateIcon()

    toggleBtn:SetScript("OnClick", function()
        if OnePanel and OnePanel.SetPanelExpanded then
            OnePanel:SetPanelExpanded(not OnePanel.isExpanded)
        end
    end)
    toggleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local isExp = OnePanel.isExpanded ~= false
        GameTooltip:SetText(isExp and "Collapse Details Panel" or "Expand Details Panel", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)

    if Utils and Utils.EventBus then
        Utils.EventBus:Register("ONEPANEL_EXPAND_STATE_CHANGED", function(isExpanded)
            if subPanel and subPanel.SetShown then
                subPanel:SetShown(isExpanded)
            end
            if vDivider and vDivider.SetShown then
                vDivider:SetShown(isExpanded)
            end
            if toggleBtn and toggleBtn.UpdateIcon then
                toggleBtn:UpdateIcon()
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Sub-Panel Details Content Components
    ---------------------------------------------------------------------------

    -- Statistic Title (16pt gold, centered)
    local detailTitle = subPanel:CreateFontString(nil, "OVERLAY")
    detailTitle:SetPoint("TOPLEFT", subPanel, "TOPLEFT", 4, -8)
    detailTitle:SetPoint("TOPRIGHT", subPanel, "TOPRIGHT", -4, -8)
    detailTitle:SetJustifyH("CENTER")
    detailTitle:SetWordWrap(true)
    detailTitle:SetFont(GetStandardFont(), 16, "")
    detailTitle:SetTextColor(1, 0.82, 0, 1)
    detailTitle:SetShadowOffset(1, -1)
    detailTitle:SetShadowColor(0, 0, 0, 1)
    subPanel.Title = detailTitle

    -- Breadcrumb Category Line (e.g. "Character > Consumables")
    local breadcrumbText = subPanel:CreateFontString(nil, "OVERLAY")
    breadcrumbText:SetPoint("TOP", detailTitle, "BOTTOM", 0, -4)
    breadcrumbText:SetJustifyH("CENTER")
    breadcrumbText:SetFont(GetStandardFont(), 11, "")
    breadcrumbText:SetTextColor(0.65, 0.65, 0.65, 1)
    breadcrumbText:SetShadowOffset(1, -1)
    breadcrumbText:SetShadowColor(0, 0, 0, 1)
    subPanel.Breadcrumb = breadcrumbText

    -- Centerpiece Value Banner (Large 22pt bold readout)
    local valueFrame = CreateFrame("Frame", nil, subPanel)
    valueFrame:SetSize(176, 44)
    valueFrame:SetPoint("TOP", breadcrumbText, "BOTTOM", 0, -10)

    local valueBg = valueFrame:CreateTexture(nil, "BACKGROUND")
    valueBg:SetAllPoints(valueFrame)
    valueBg:SetColorTexture(0.08, 0.08, 0.10, 0.85)

    local valueBorder = valueFrame:CreateTexture(nil, "BORDER")
    valueBorder:SetPoint("TOPLEFT", valueFrame, "TOPLEFT", -2, 2)
    valueBorder:SetPoint("BOTTOMRIGHT", valueFrame, "BOTTOMRIGHT", 2, -2)
    if SafeHasAtlas("ui-castingbar-frame") then
        valueBorder:SetAtlas("ui-castingbar-frame")
    else
        valueBorder:SetColorTexture(0.20, 0.18, 0.15, 0.9)
    end

    local valueText = valueFrame:CreateFontString(nil, "OVERLAY")
    valueText:SetPoint("CENTER", valueFrame, "CENTER", 0, 0)
    valueText:SetJustifyH("CENTER")
    valueText:SetFont(GetStandardFont(), 20, "")
    valueText:SetTextColor(1, 1, 1, 1)
    valueText:SetShadowOffset(1, -1)
    valueText:SetShadowColor(0, 0, 0, 1)
    valueFrame.Text = valueText
    subPanel.ValueFrame = valueFrame

    -- Scrollable Description Box
    local descScroll = CreateFrame("ScrollFrame", "OnePanel_StatisticsDescScroll", subPanel, "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT", valueFrame, "BOTTOMLEFT", 0, -12)
    descScroll:SetPoint("BOTTOMRIGHT", subPanel, "BOTTOMRIGHT", -20, 14)
    descScroll:EnableMouseWheel(true)

    local descContent = CreateFrame("Frame", nil, descScroll)
    descContent:SetSize(166, 140)
    descScroll:SetScrollChild(descContent)

    local descText = descContent:CreateFontString(nil, "OVERLAY")
    descText:SetPoint("TOPLEFT", descContent, "TOPLEFT", 2, -2)
    descText:SetPoint("TOPRIGHT", descContent, "TOPRIGHT", -2, -2)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetFont(GetStandardFont(), 12, "")
    descText:SetSpacing(3)
    descText:SetTextColor(0.85, 0.85, 0.85, 1)
    descText:SetShadowOffset(1, -1)
    descText:SetShadowColor(0, 0, 0, 1)
    subPanel.DescScroll = descScroll
    subPanel.DescText = descText

    -- Empty Details Placeholder (Shown when no statistic is selected)
    local emptyDetailText = subPanel:CreateFontString(nil, "OVERLAY")
    emptyDetailText:SetPoint("CENTER", subPanel, "CENTER", 0, 0)
    emptyDetailText:SetFont(GetStandardFont(), 13, "")
    emptyDetailText:SetShadowOffset(1, -1)
    emptyDetailText:SetShadowColor(0, 0, 0, 1)
    emptyDetailText:SetTextColor(0.5, 0.5, 0.5, 1)
    emptyDetailText:SetText("Select a statistic\nto view its details.")
    subPanel.EmptyText = emptyDetailText

    ---------------------------------------------------------------------------
    -- Sub-Panel Update Logic
    ---------------------------------------------------------------------------

    local function UpdateDetails(data)
        if not data then
            detailTitle:Hide()
            breadcrumbText:Hide()
            valueFrame:Hide()
            descScroll:Hide()
            emptyDetailText:Show()
            return
        end

        emptyDetailText:Hide()
        detailTitle:Show()
        breadcrumbText:Show()
        valueFrame:Show()
        descScroll:Show()

        detailTitle:SetText(data.name)

        if data.parentCategoryName then
            breadcrumbText:SetText(string.format("|cff888888%s > %s|r", data.parentCategoryName, data.categoryName))
        else
            breadcrumbText:SetText(string.format("|cff888888%s|r", data.categoryName))
        end

        local val = FormatStatValue(data.quantity)
        if val == "--" then
            valueText:SetText("|cff888888--|r")
        else
            valueText:SetText(string.format("|cffffffff%s|r", val))
        end

        local desc = data.description
        if not desc or desc == "" then
            desc = "No further description recorded for this statistic."
        end
        descText:SetText(desc)
        descContent:SetHeight(math.max(100, descText:GetStringHeight() + 10))
        descScroll:SetVerticalScroll(0)
    end

    ---------------------------------------------------------------------------
    -- Row Factory & List Rendering
    ---------------------------------------------------------------------------

    local function CreateRow(idx)
        local row = CreateFrame("Button", "OnePanel_StatisticsRow" .. idx, listContent)
        row:SetSize(288, 24)
        row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, 0)

        -- Subtle row background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetColorTexture(0.06, 0.06, 0.08, 0.6)
        row.Bg = bg

        -- Mouseover highlight
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.20)
        hl:SetAllPoints(row)
        row.Highlight = hl

        -- Selected highlight
        local sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        sel:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
        sel:SetBlendMode("ADD")
        sel:SetAlpha(0.35)
        sel:SetAllPoints(row)
        sel:Hide()
        row.SelectedHighlight = sel

        -- Collapsible Header Button (Matches Character Stats, Skills, and Reputation UIPanelButtonTemplate)
        local headerBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        headerBtn:SetAllPoints(row)
        headerBtn:Disable()
        headerBtn:Hide()
        if headerBtn.SetDisabledFontObject then
            headerBtn:SetDisabledFontObject("GameFontNormal")
        end
        local hFont = headerBtn:GetFontString()
        if hFont then
            hFont:SetFont(GetStandardFont(), 13, "")
            hFont:SetTextColor(1, 0.85, 0.1, 1)
            hFont:SetShadowOffset(1, -1)
            hFont:SetShadowColor(0, 0, 0, 1)
        end
        row.HeaderButton = headerBtn

        -- Subcategory Header Button (Indented UIPanelButtonTemplate for nested sections like Wealth, Consumables)
        local subHeaderBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        subHeaderBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 12, 0)
        subHeaderBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        subHeaderBtn:Disable()
        subHeaderBtn:Hide()
        if subHeaderBtn.SetDisabledFontObject then
            subHeaderBtn:SetDisabledFontObject("GameFontNormal")
        end
        local subFont = subHeaderBtn:GetFontString()
        if subFont then
            subFont:SetFont(GetStandardFont(), 12, "")
            subFont:SetTextColor(0.95, 0.85, 0.35, 1)
            subFont:SetShadowOffset(1, -1)
            subFont:SetShadowColor(0, 0, 0, 1)
        end
        row.SubHeaderButton = subHeaderBtn

        -- Statistic Value Text (Right aligned)
        local valueText = row:CreateFontString(nil, "ARTWORK")
        valueText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        valueText:SetJustifyH("RIGHT")
        valueText:SetFont(GetStandardFont(), 13, "")
        valueText:SetShadowOffset(1, -1)
        valueText:SetShadowColor(0, 0, 0, 1)
        valueText:SetTextColor(1, 1, 1, 1)
        row.ValueText = valueText

        -- Statistic Name Text (Left aligned)
        local nameText = row:CreateFontString(nil, "ARTWORK")
        nameText:SetPoint("LEFT", row, "LEFT", 12, 0)
        nameText:SetPoint("RIGHT", valueText, "LEFT", -10, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetFont(GetStandardFont(), 13, "")
        nameText:SetShadowOffset(1, -1)
        nameText:SetShadowColor(0, 0, 0, 1)
        nameText:SetTextColor(0.95, 0.95, 0.95, 1)
        row.NameText = nameText

        listContent.rows[idx] = row
        return row
    end

    RefreshList = function()
        for _, r in ipairs(listContent.rows) do r:Hide() end

        local tree = BuildStatisticsTree()

        -- Default initial collapse: keep first category expanded, others collapsed
        if not initialSetupDone then
            for idx, root in ipairs(tree) do
                if idx == 1 then
                    collapsedCategories[root.categoryID] = false
                    for _, sub in ipairs(root.subcategories) do
                        collapsedCategories[sub.categoryID] = false
                    end
                else
                    collapsedCategories[root.categoryID] = true
                end
            end
            initialSetupDone = true
        end

        local yOffset = -2
        local rowIndex = 1
        local totalStatsTracked = 0
        local selectedFound = false
        local selectedItemData = nil

        local isFiltering = (searchQuery ~= "")

        for _, root in ipairs(tree) do
            local isRootCollapsed = (collapsedCategories[root.categoryID] == true) and not isFiltering

            -- Check if root or any children match search filter
            local rootMatches = false
            local matchingDirectStats = {}
            local matchingSubcategories = {}

            if isFiltering then
                for _, st in ipairs(root.stats) do
                    if string.find(string.lower(st.name or ""), searchQuery, 1, true) then
                        table.insert(matchingDirectStats, st)
                        rootMatches = true
                    end
                end
                for _, sub in ipairs(root.subcategories) do
                    local subMatches = {}
                    for _, st in ipairs(sub.stats) do
                        if string.find(string.lower(st.name or ""), searchQuery, 1, true) then
                            table.insert(subMatches, st)
                            rootMatches = true
                        end
                    end
                    if #subMatches > 0 then
                        table.insert(matchingSubcategories, { sub = sub, stats = subMatches })
                    end
                end
            else
                matchingDirectStats = root.stats
                for _, sub in ipairs(root.subcategories) do
                    table.insert(matchingSubcategories, { sub = sub, stats = sub.stats })
                end
            end

            local shouldShowRoot = not isFiltering or rootMatches

            if shouldShowRoot then
                -- Render Root Category Header (Authentic UIPanelButtonTemplate disabled grey button)
                local row = listContent.rows[rowIndex] or CreateRow(rowIndex)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, yOffset)
                row:SetPoint("RIGHT", listContent, "RIGHT", -4, 0)
                row:SetHeight(26)

                row.Bg:Hide()
                row.NameText:Hide()
                row.ValueText:Hide()
                row.SelectedHighlight:Hide()
                row.SubHeaderButton:Hide()

                local headerBtn = row.HeaderButton
                headerBtn:Show()
                headerBtn:ClearAllPoints()
                headerBtn:SetAllPoints(row)
                headerBtn:SetHeight(26)
                headerBtn:SetText(root.name)
                headerBtn:Disable()
                headerBtn:EnableMouse(true)
                local hFont = headerBtn:GetFontString()
                if hFont then
                    hFont:SetFont(GetStandardFont(), 13, "")
                    hFont:SetTextColor(1, 0.85, 0.1, 1)
                    hFont:SetShadowOffset(1, -1)
                    hFont:SetShadowColor(0, 0, 0, 1)
                end

                local catID = root.categoryID
                headerBtn:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" then
                        collapsedCategories[catID] = not collapsedCategories[catID]
                        RefreshList()
                    end
                end)
                row:SetScript("OnClick", function()
                    collapsedCategories[catID] = not collapsedCategories[catID]
                    RefreshList()
                end)

                row:Show()
                rowIndex = rowIndex + 1
                yOffset = yOffset - 30

                -- If root is expanded, render direct stats and subcategories
                if not isRootCollapsed then
                    -- Render direct stats
                    for _, st in ipairs(matchingDirectStats) do
                        totalStatsTracked = totalStatsTracked + 1
                        local statRow = listContent.rows[rowIndex] or CreateRow(rowIndex)
                        statRow:ClearAllPoints()
                        statRow:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, yOffset)
                        statRow:SetPoint("RIGHT", listContent, "RIGHT", -4, 0)
                        statRow:SetHeight(22)

                        statRow.HeaderButton:Hide()
                        statRow.SubHeaderButton:Hide()
                        statRow.Bg:Show()
                        statRow.NameText:Show()
                        statRow.ValueText:Show()

                        statRow.NameText:ClearAllPoints()
                        statRow.NameText:SetPoint("LEFT", statRow, "LEFT", 14, 0)
                        statRow.NameText:SetPoint("RIGHT", statRow.ValueText, "LEFT", -8, 0)
                        statRow.NameText:SetText(st.name)

                        local val = FormatStatValue(st.quantity)
                        if val == "--" then
                            statRow.ValueText:SetText("|cff777777--|r")
                        else
                            statRow.ValueText:SetText(val)
                        end

                        local isSelected = (selectedStatID and selectedStatID == st.statID)
                        if isSelected then
                            statRow.SelectedHighlight:Show()
                            selectedFound = true
                            selectedItemData = st
                        else
                            statRow.SelectedHighlight:Hide()
                        end

                        statRow:SetScript("OnClick", function()
                            selectedStatID = st.statID
                            selectedStatData = st
                            UpdateDetails(st)
                            RefreshList()
                        end)

                        statRow:Show()
                        rowIndex = rowIndex + 1
                        yOffset = yOffset - 23
                    end

                    -- Render Subcategories
                    for _, subItem in ipairs(matchingSubcategories) do
                        local sub = subItem.sub
                        local subStats = subItem.stats
                        local isSubCollapsed = (collapsedCategories[sub.categoryID] == true) and not isFiltering

                        -- Subcategory Header (Indented UIPanelButtonTemplate disabled grey button)
                        local subRow = listContent.rows[rowIndex] or CreateRow(rowIndex)
                        subRow:ClearAllPoints()
                        subRow:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, yOffset)
                        subRow:SetPoint("RIGHT", listContent, "RIGHT", -4, 0)
                        subRow:SetHeight(24)

                        subRow.Bg:Hide()
                        subRow.HeaderButton:Hide()
                        subRow.NameText:Hide()
                        subRow.ValueText:Hide()
                        subRow.SelectedHighlight:Hide()

                        local subHeaderBtn = subRow.SubHeaderButton
                        subHeaderBtn:Show()
                        subHeaderBtn:ClearAllPoints()
                        subHeaderBtn:SetPoint("TOPLEFT", subRow, "TOPLEFT", 12, 0)
                        subHeaderBtn:SetPoint("BOTTOMRIGHT", subRow, "BOTTOMRIGHT", 0, 0)
                        subHeaderBtn:SetHeight(24)
                        subHeaderBtn:SetText(sub.name)
                        subHeaderBtn:Disable()
                        subHeaderBtn:EnableMouse(true)
                        local subFont = subHeaderBtn:GetFontString()
                        if subFont then
                            subFont:SetFont(GetStandardFont(), 12, "")
                            subFont:SetTextColor(0.95, 0.85, 0.35, 1)
                            subFont:SetShadowOffset(1, -1)
                            subFont:SetShadowColor(0, 0, 0, 1)
                        end

                        local subCatID = sub.categoryID
                        subHeaderBtn:SetScript("OnMouseUp", function(self, button)
                            if button == "LeftButton" then
                                collapsedCategories[subCatID] = not collapsedCategories[subCatID]
                                RefreshList()
                            end
                        end)
                        subRow:SetScript("OnClick", function()
                            collapsedCategories[subCatID] = not collapsedCategories[subCatID]
                            RefreshList()
                        end)

                        subRow:Show()
                        rowIndex = rowIndex + 1
                        yOffset = yOffset - 28

                        -- If subcategory expanded, render its stats
                        if not isSubCollapsed then
                            for _, st in ipairs(subStats) do
                                totalStatsTracked = totalStatsTracked + 1
                                local statRow = listContent.rows[rowIndex] or CreateRow(rowIndex)
                                statRow:ClearAllPoints()
                                statRow:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, yOffset)
                                statRow:SetPoint("RIGHT", listContent, "RIGHT", -4, 0)
                                statRow:SetHeight(22)

                                statRow.HeaderButton:Hide()
                                statRow.SubHeaderButton:Hide()
                                statRow.Bg:Show()
                                statRow.NameText:Show()
                                statRow.ValueText:Show()

                                statRow.NameText:ClearAllPoints()
                                statRow.NameText:SetPoint("LEFT", statRow, "LEFT", 26, 0)
                                statRow.NameText:SetPoint("RIGHT", statRow.ValueText, "LEFT", -8, 0)
                                statRow.NameText:SetText(st.name)

                                local val = FormatStatValue(st.quantity)
                                if val == "--" then
                                    statRow.ValueText:SetText("|cff777777--|r")
                                else
                                    statRow.ValueText:SetText(val)
                                end

                                local isSelected = (selectedStatID and selectedStatID == st.statID)
                                if isSelected then
                                    statRow.SelectedHighlight:Show()
                                    selectedFound = true
                                    selectedItemData = st
                                else
                                    statRow.SelectedHighlight:Hide()
                                end

                                statRow:SetScript("OnClick", function()
                                    selectedStatID = st.statID
                                    selectedStatData = st
                                    UpdateDetails(st)
                                    RefreshList()
                                end)

                                statRow:Show()
                                rowIndex = rowIndex + 1
                                yOffset = yOffset - 23
                            end
                        end
                    end
                end
            end
        end

        listContent:SetHeight(math.max(400, math.abs(yOffset) + 20))
        topBar.SummaryText:SetText(string.format("|cff888888Tracked:|r |cffffcc00%d|r", totalStatsTracked))

        if selectedFound and selectedItemData then
            UpdateDetails(selectedItemData)
        else
            if not selectedStatID then
                UpdateDetails(nil)
            end
        end
    end

    container.Refresh = RefreshList

    ---------------------------------------------------------------------------
    -- Event Listener
    ---------------------------------------------------------------------------

    local eventFrame = CreateFrame("Frame", nil, container)
    eventFrame:RegisterEvent("CRITERIA_UPDATE")
    eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(self, event)
        if container:IsVisible() and RefreshList then
            RefreshList()
        end
    end)

    return container
end

-------------------------------------------------------------------------------
-- OnePanel Plugin Registration
-------------------------------------------------------------------------------

local function RegisterStatisticsPlugin()
    if not OnePanel then return end

    OnePanel:RegisterPlugin({
        id = "Statistics",
        title = "Statistics",
        order = 60, -- Tab 6 in OnePanel Suite
        icon = "Interface\\Icons\\INV_Misc_Note_03",
        CreateView = CreateStatisticsView,
        OnShow = function(container)
            if OnePanel and OnePanel.SetTitleText then
                OnePanel:SetTitleText("Statistics")
            end
            if OnePanel and OnePanel.SetHeaderPortrait then
                OnePanel:SetHeaderPortrait(nil, nil, true)
            end
            if container and container.Refresh then
                container:Refresh()
            end
        end,
        OnHide = function(container)
            GameTooltip_Hide()
        end
    })
end

-------------------------------------------------------------------------------
-- Initialization Listener & Slash Command
-------------------------------------------------------------------------------

local loadFrame = CreateFrame("Frame", "OnePanel_Statistics_LoadFrame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        RegisterStatisticsPlugin()
    end
end)

SLASH_OPSTAT1 = "/opstat"
SLASH_OPSTAT2 = "/opstatistics"
SlashCmdList["OPSTAT"] = function()
    local categories = SafeGetStatisticsCategoryList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OnePanel_Statistics]|r Discovered categories: " .. tostring(#categories))
    if OnePanel and OnePanel.frame then
        OnePanel.frame:Show()
        if OnePanel.SelectPlugin then
            OnePanel:SelectPlugin("Statistics")
        end
    end
end
