--[[=========================================================================

    CharacterStats -- StatsWindow.lua
    The main Lotro.Window: summary line, toolbar, a ListBox of custom
    rows (group / sub-group headers, stat rows, equipment rows and their
    descriptions) with a scrollbar, and the share panel at the bottom.

    Collapsing is done by rebuilding the list with only the visible rows;
    row controls are cached in CS.rows and re-added.

=========================================================================]]

CS.StatsWindow = { };
CS.rows = { };
CS.sw = { };          -- controls of the main window (kept alive via CS)

local layingOut = false;
local listWidth = 200;

------------------------------------------------------------------------
-- SMALL HELPERS
------------------------------------------------------------------------

local function NewLabel(parent, font, colour, align)
    local label = Turbine.UI.Label();
    label:SetParent(parent);
    label:SetFont(font);
    label:SetForeColor(colour);
    label:SetTextAlignment(align or Turbine.UI.ContentAlignment.MiddleLeft);
    label:SetMouseVisible(false);
    -- single line by default (a wrapped line is clipped by the fixed row
    -- height); description rows switch multiline back on
    label:SetMultiline(false);
    -- game text (names, descriptions) may contain "<": show it literally
    if (CS.Util.Has(label, "SetMarkupEnabled")) then label:SetMarkupEnabled(false); end
    return label;
end

local function NewButton(parent, text)
    local b = Turbine.UI.Lotro.Button();
    b:SetParent(parent);
    b:SetText(text);
    return b;
end

--[[
    The scroll bar is bound to the list (SetVerticalScrollBar), and a bound
    scroll bar throws "Invalid operation while the scroll bar is bound" on
    Get/SetValue, Get/SetMinimum, Get/SetMaximum. All scrolling therefore
    goes through the ListBox itself: GetItemAt finds the visible rows,
    EnsureVisible scrolls. Everything is pcall-guarded (best effort).
]]
local function ListItemAt(y)
    local list = CS.sw.list;
    if (list == nil) then return nil; end
    local item = CS.Util.Call(list, "GetItemAt", 2, y);
    if (type(item) == "table" and item.kind ~= nil) then return item; end
    return nil;
end

local function ListIndexOf(item)
    local list = CS.sw.list;
    if (item == nil or list == nil) then return nil; end
    for i = 1, list:GetItemCount() do
        if (list:GetItem(i) == item) then return i; end
    end
    return nil;
end

local function ListEnsureVisible(index)
    local list = CS.sw.list;
    local count = (list ~= nil) and list:GetItemCount() or 0;
    if (index == nil or count < 1) then return; end
    CS.Util.Call(list, "EnsureVisible", CS.Util.Clamp(index, 1, count));
end

local function OnWheel(sender, args)
    local list = CS.sw.list;
    if (list == nil or type(args) ~= "table" or type(args.Direction) ~= "number" or args.Direction == 0) then return; end
    local steps = math.max(1, math.floor(CS.WHEEL_STEP / CS.ROW_STAT_H));
    if (args.Direction > 0) then
        local top = ListIndexOf(ListItemAt(1));
        if (top ~= nil) then ListEnsureVisible(top - steps); end
    else
        local bottom = ListIndexOf(ListItemAt(math.max(1, list:GetHeight() - 2)));
        if (bottom ~= nil) then ListEnsureVisible(bottom + steps); end
    end
end

-- Only clickable rows (headers, items) take the mouse, unless the wheel
-- fallback needs every row.
local function NewRow(kind, height, clickable)
    local row = Turbine.UI.Control();
    row.kind = kind;
    row:SetSize(listWidth, height);
    row:SetMouseVisible(clickable == true or CS.WHEEL_FALLBACK);
    if (CS.WHEEL_FALLBACK) then row.MouseWheel = OnWheel; end
    return row;
end

-- Header behaviour shared by group and sub-group rows.
local function MakeClickableHeader(row, background)
    row.background = background;
    row:SetBackColor(background);
    row.MouseEnter = function() row:SetBackColor(CS.COL_HOVER); end
    row.MouseLeave = function() row:SetBackColor(background); end
    row.MouseClick = function(sender, args)
        if (args ~= nil and args.Button ~= nil and args.Button ~= Turbine.UI.MouseButton.Left) then return; end
        CS.StatsWindow.Toggle(row.groupId);
    end
end

------------------------------------------------------------------------
-- ROW FACTORIES
------------------------------------------------------------------------

local function CreateHeaderRow(kind, groupId)
    local isGroup = (kind == "group");
    local h = isGroup and CS.ROW_GROUP_H or CS.ROW_SUB_H;
    local indent = isGroup and 4 or (CS.INDENT_SUB + 4);
    local row = NewRow(kind, h, true);
    row.groupId = groupId;
    row.text  = NewLabel(row, isGroup and CS.FONT_GROUP or CS.FONT_SUB, isGroup and CS.COL_GOLD or CS.COL_SUB);
    row.count = NewLabel(row, CS.FONT_SMALL, CS.COL_DIM, Turbine.UI.ContentAlignment.MiddleRight);
    MakeClickableHeader(row, isGroup and CS.COL_GROUP_BG or CS.COL_SUB_BG);

    row.Layout = function(w)
        row.text:SetPosition(indent, 0);
        row.text:SetSize(math.max(10, w - indent - 90), h);
        row.count:SetPosition(w - 88, 0);
        row.count:SetSize(84, h);
    end
    row.SetHeader = function(title, collapsed, countText)
        -- the row may have been re-added under the cursor without MouseLeave
        row:SetBackColor(row.background);
        CS.Util.SetText(row.text, (collapsed and "[+] " or "[-] ") .. title);
        CS.Util.SetText(row.count, countText or "");
    end
    return row;
end

--[[
    Stat row: label left, value right-aligned, both single-line. The label
    column is as wide as its text (estimated with CS.ROW_CHAR_W); the
    value gets the rest. If both don't fit, the label keeps at least
    CS.LABEL_MIN_SHARE of the width and the longer text is cut with "...".
    row.labelText / row.valueText keep the full texts.
]]
local function CreateStatRow()
    local row = NewRow("stat", CS.ROW_STAT_H);
    row.name  = NewLabel(row, CS.FONT_ROW, CS.COL_LABEL);
    row.value = NewLabel(row, CS.FONT_ROW, CS.COL_VALUE, Turbine.UI.ContentAlignment.MiddleRight);
    row.labelText = "";
    row.valueText = "";
    row.width = listWidth;

    local function Fit()
        local U = CS.Util;
        local cw = CS.ROW_CHAR_W;
        local avail = math.max(20, row.width - CS.INDENT_ROW - 4 - CS.STAT_GAP);
        local labelNeed = math.ceil(U.Utf8Len(row.labelText) * cw) + 2;
        local valueNeed = math.ceil(U.Utf8Len(row.valueText) * cw) + 2;
        local nameW = math.min(labelNeed, math.max(avail - valueNeed, math.floor(avail * CS.LABEL_MIN_SHARE)));
        nameW = math.max(10, math.min(nameW, avail - 10));
        local valueW = avail - nameW;
        if (row.nameW ~= nameW) then
            row.nameW = nameW;
            row.name:SetPosition(CS.INDENT_ROW, 0);
            row.name:SetSize(nameW, CS.ROW_STAT_H);
            row.value:SetPosition(CS.INDENT_ROW + nameW + CS.STAT_GAP, 0);
            row.value:SetSize(valueW, CS.ROW_STAT_H);
        elseif (row.valueW ~= valueW) then
            row.value:SetSize(valueW, CS.ROW_STAT_H);
        end
        row.valueW = valueW;
        CS.Util.SetText(row.name, U.FitText(row.labelText, nameW, cw));
        CS.Util.SetText(row.value, U.FitText(row.valueText, valueW, cw));
    end

    row.Layout = function(w)
        row.width = w;
        Fit();
    end
    row.SetValue = function(text, colour)
        if (row.valueText ~= text) then
            row.valueText = text;
            Fit();
        end
        if (row.lastColour ~= colour) then
            row.lastColour = colour;
            row.value:SetForeColor(colour or CS.COL_VALUE);
        end
    end
    row.SetData = function(data, alternate)
        row.labelText = data.label or "";
        row.valueText = data.value or "";
        Fit();
        row.SetValue(row.valueText, data.color);
        row:SetBackColor(alternate and CS.COL_ROW_ALT or CS.COL_TRANSPARENT);
    end
    return row;
end

--[[
    Item icons. Default: a static picture built from the ItemInfo image ids
    (SetBackground with a game asset id, mouse-invisible), so clicking it
    just toggles the row. Optional ("nativeItems"): the game's ItemControl,
    which shows the native tooltip but is fully interactive (the docs say
    the item can be used from it as from any other panel).
]]
local function ShowStaticIcon(row, images)
    if (images == nil or not images[#images]) then return false; end
    if (row.layers == nil) then
        row.layers = { };
        for i = 1, #images do
            local layer = Turbine.UI.Control();
            layer:SetParent(row);
            layer:SetPosition(20, 2);
            layer:SetSize(32, 32);
            layer:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
            layer:SetMouseVisible(false);
            row.layers[i] = layer;
        end
    end
    for i, layer in ipairs(row.layers) do
        local id = images[i];
        if (id and layer.imageId ~= id) then
            layer.imageId = id;
            if (not pcall(layer.SetBackground, layer, id)) then id = false; end
        end
        layer:SetVisible(id ~= false);
    end
    return true;
end

local function ShowNativeIcon(row, item)
    if (row.icon == nil) then
        local ok, ic = pcall(Turbine.UI.Lotro.ItemControl);
        if (not ok or ic == nil) then return false; end
        row.icon = ic;
        ic:SetParent(row);
        ic:SetPosition(20, 2);
        ic:SetSize(32, 32);
    end
    if (row.iconItem ~= item) then
        row.iconItem = item;
        pcall(row.icon.SetItem, row.icon, item);
    end
    row.icon:SetVisible(true);
    return true;
end

local function CreateItemRow()
    local row = NewRow("item", CS.ROW_ITEM_H, true);
    row.marker = NewLabel(row, CS.FONT_SUB, CS.COL_GOLD, Turbine.UI.ContentAlignment.MiddleCenter);
    row.marker:SetPosition(4, 0);
    row.marker:SetSize(16, CS.ROW_ITEM_H);

    row.placeholder = Turbine.UI.Control();
    row.placeholder:SetParent(row);
    row.placeholder:SetPosition(20, 2);
    row.placeholder:SetSize(32, 32);
    row.placeholder:SetBackColor(CS.COL_SLOT_EMPTY);
    row.placeholder:SetMouseVisible(false);

    row.slotLabel = NewLabel(row, CS.FONT_SMALL, CS.COL_DIM);
    row.slotLabel:SetPosition(CS.ITEM_TEXT_X, 2);
    row.nameLabel = NewLabel(row, CS.FONT_ROW, CS.COL_VALUE);
    row.nameLabel:SetPosition(CS.ITEM_TEXT_X, 17);

    row.Layout = function(w)
        row.slotLabel:SetSize(math.max(10, w - CS.ITEM_TEXT_X - 4), 16);
        row.nameLabel:SetSize(math.max(10, w - CS.ITEM_TEXT_X - 4), 17);
    end

    row.MouseClick = function(sender, args)
        if (args ~= nil and args.Button ~= nil and args.Button ~= Turbine.UI.MouseButton.Left) then return; end
        if (row.expandable) then CS.StatsWindow.Toggle("item." .. tostring(row.slot)); end
    end

    -- e = snapshot equipment entry
    row.SetData = function(e, expandable, expanded)
        row.slot = e.slot;
        row.expandable = expandable;
        row.marker:SetText(expandable and (expanded and "-" or "+") or "");
        row.slotLabel:SetText(e.slotLabel);

        if (e.item == nil) then
            row.nameLabel:SetText("(empty)");
            row.nameLabel:SetForeColor(CS.COL_DIM);
        else
            row.nameLabel:SetText(e.name);
            row.nameLabel:SetForeColor(CS.QUALITY_COLOR[e.quality or -1] or CS.COL_VALUE);
        end

        local mode;
        if (CS.settings.showIcons and e.item ~= nil) then
            mode = CS.settings.nativeItems and "native" or "static";
        end
        local shown = false;
        if (mode == "native") then
            shown = ShowNativeIcon(row, e.item);
        elseif (mode == "static") then
            shown = ShowStaticIcon(row, e.images);
        end
        if (row.icon ~= nil and not (shown and mode == "native")) then
            row.icon:SetVisible(false);
        end
        if (row.layers ~= nil and not (shown and mode == "static")) then
            for _, layer in ipairs(row.layers) do layer:SetVisible(false); end
        end
        row.placeholder:SetVisible(not shown);
    end
    return row;
end

local function CreateDescRow()
    local row = NewRow("desc", CS.DESC_LINE_H + 6);
    row.label = NewLabel(row, CS.FONT_DESC, CS.COL_DESC, Turbine.UI.ContentAlignment.TopLeft);
    row.label:SetMultiline(true);
    row.label:SetPosition(CS.ITEM_TEXT_X, 2);
    row.textValue = "";

    row.Layout = function(w)
        local textW = math.max(40, w - CS.ITEM_TEXT_X - 4);
        local lines = CS.Util.EstimateLines(row.textValue, textW, CS.DESC_CHAR_W);
        local h = lines * CS.DESC_LINE_H + 6;
        row:SetHeight(h);
        row.label:SetSize(textW, h - 2);
    end
    -- An item without a description (or with the client's "string table
    -- error" placeholder, removed by the model) shows only its extra line;
    -- "(no description)" is a fallback for rows without either.
    row.SetData = function(e)
        local desc = e.desc or "";
        local extra = e.extra or "";
        local text;
        if (desc ~= "") then
            text = desc;
            if (extra ~= "") then text = text .. "\n" .. extra; end
            row.label:SetForeColor(CS.COL_DESC);
        elseif (extra ~= "") then
            text = extra;
            row.label:SetForeColor(CS.COL_DESC);
        else
            text = "(no description)";
            row.label:SetForeColor(CS.COL_DIM);
        end
        row.textValue = text;
        row.label:SetText(text);
        row.Layout(listWidth);
    end
    return row;
end

-- Cached row by key; created on first use.
local function GetRow(key, factory, arg1, arg2)
    local row = CS.rows[key];
    if (row == nil) then
        row = factory(arg1, arg2);
        row.Layout(listWidth);
        CS.rows[key] = row;
    end
    return row;
end

------------------------------------------------------------------------
-- WINDOW
------------------------------------------------------------------------

function CS.StatsWindow.Build()
    local s = CS.settings;
    local win = Turbine.UI.Lotro.Window();
    CS.mainWindow = win;
    win:SetText("Character Stats");
    win:SetPosition(s.mainX, s.mainY);
    win:SetSize(s.mainW, s.mainH);
    win:SetResizable(true);
    if (CS.Util.Has(win, "SetMinimumSize")) then
        pcall(win.SetMinimumSize, win, CS.MAIN_MIN_W, CS.MAIN_MIN_H);
    end
    if (CS.Util.Has(win, "SetMaximumSize")) then
        pcall(win.SetMaximumSize, win, CS.MAIN_MAX_W, CS.Settings.DisplayHeight());
    end

    local sw = CS.sw;
    sw.summary = NewLabel(win, CS.FONT_SUMMARY, CS.COL_GOLD);
    sw.summary:SetText("");

    sw.expandAll = NewButton(win, "Expand all");
    sw.expandAll.Click = function() CS.StatsWindow.ExpandAll(); end
    sw.collapseAll = NewButton(win, "Collapse all");
    sw.collapseAll.Click = function() CS.StatsWindow.CollapseAll(); end
    sw.refresh = NewButton(win, "Refresh");
    sw.refresh.Click = function() CS.MarkDirty(true); end

    sw.list = Turbine.UI.ListBox();
    sw.list:SetParent(win);
    if (CS.Util.Has(sw.list, "SetOrientation")) then
        pcall(sw.list.SetOrientation, sw.list, Turbine.UI.Orientation.Vertical);
    end
    sw.scroll = Turbine.UI.Lotro.ScrollBar();
    sw.scroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    sw.scroll:SetParent(win);
    sw.list:SetVerticalScrollBar(sw.scroll);
    if (CS.WHEEL_FALLBACK) then sw.list.MouseWheel = OnWheel; end

    CS.SharePanel.Build(win);

    win.PositionChanged = function()
        if (not CS.unloaded) then CS.Settings.SaveSoon(); end
    end
    win.SizeChanged = function()
        CS.StatsWindow.Layout();
        if (not CS.unloaded) then CS.Settings.SaveSoon(); end
    end
    win.VisibleChanged = function()
        if (CS.unloaded) then return; end
        -- F12 hides / restores the window without changing the setting
        if (not CS.hudApplying) then
            CS.settings.mainVisible = win:IsVisible();
            CS.Settings.SaveSoon();
        end
        if (win:IsVisible()) then
            CS.MarkDirty(true);
            CS.Ticker.Wake();
        end
        CS.IconWindow.UpdateMenuText();
    end

    CS.StatsWindow.Layout();
    win:SetVisible(s.mainVisible);
end

function CS.StatsWindow.Layout()
    local win = CS.mainWindow;
    local sw = CS.sw;
    if (win == nil or layingOut) then return; end
    layingOut = true;

    local W, H = win:GetSize();
    -- manual minimum size if the client lacks SetMinimumSize
    if (W < CS.MAIN_MIN_W or H < CS.MAIN_MIN_H) then
        W = math.max(W, CS.MAIN_MIN_W);
        H = math.max(H, CS.MAIN_MIN_H);
        win:SetSize(W, H);
    end

    local pad = CS.PAD;
    local inner = W - 2 * pad;
    local top = CS.CONTENT_TOP;

    sw.summary:SetPosition(pad, top);
    sw.summary:SetSize(inner, 18);

    local by = top + 22;
    sw.expandAll:SetPosition(pad, by);
    sw.expandAll:SetSize(84, 20);
    sw.collapseAll:SetPosition(pad + 88, by);
    sw.collapseAll:SetSize(84, 20);
    sw.refresh:SetPosition(W - pad - 76, by);
    sw.refresh:SetSize(76, 20);

    local listTop = by + 26;
    local shareH = CS.SharePanel.HeightFor(H);
    local shareTop = H - CS.BOTTOM_PAD - shareH;
    local listH = math.max(20, shareTop - 6 - listTop);
    local newListW = inner - CS.SCROLL_W - 2;

    sw.list:SetPosition(pad, listTop);
    sw.list:SetSize(newListW, listH);
    sw.scroll:SetPosition(W - pad - CS.SCROLL_W, listTop);
    sw.scroll:SetSize(CS.SCROLL_W, listH);

    -- the rows are relaid by the ticker (throttled) while the user drags
    if (newListW ~= listWidth) then
        listWidth = newListW;
        CS.dirty.layout = true;
        if (CS.Ticker ~= nil) then CS.Ticker.Wake(); end
    end

    CS.SharePanel.Layout(pad, shareTop, inner, shareH);
    layingOut = false;
end

-- New width for every cached row. Description heights change, so the
-- list is rebuilt from the last snapshot (unless a refresh follows).
function CS.StatsWindow.RelayoutRows(rebuild)
    CS.dirty.layout = false;
    for _, row in pairs(CS.rows) do
        if (row:GetWidth() ~= listWidth) then
            row:SetWidth(listWidth);
            row.Layout(listWidth);
        end
    end
    if (rebuild and CS.snapshot ~= nil) then CS.StatsWindow.Rebuild(CS.snapshot); end
end

------------------------------------------------------------------------
-- LIST CONTENT
------------------------------------------------------------------------

local function SubCountText(sub)
    if (sub.items ~= nil) then return sub.filled .. "/" .. sub.total; end
    if (sub.rows ~= nil) then return tostring(#sub.rows); end
    return "";
end

local function GroupCountText(group)
    if (group.id == "equip" and not group.unavailable) then
        return group.filled .. "/" .. group.total .. " slots";
    end
    return #group.subs .. " groups";
end

function CS.StatsWindow.Rebuild(snap)
    local sw = CS.sw;
    if (snap == nil) then return; end
    local IsCollapsed = CS.Settings.IsCollapsed;
    -- remember the rows at the bottom and top of the view (the bound
    -- scroll bar can't be read, see ListItemAt)
    local bottomRow = ListItemAt(math.max(1, sw.list:GetHeight() - 2));
    local topRow = ListItemAt(1);
    sw.list:ClearItems();

    for _, group in ipairs(snap.groups) do
        local gCollapsed = IsCollapsed(group.id);
        local header = GetRow("group:" .. group.id, CreateHeaderRow, "group", group.id);
        header.SetHeader(group.title, gCollapsed, GroupCountText(group));
        sw.list:AddItem(header);

        if (not gCollapsed) then
            for _, sub in ipairs(group.subs) do
                local sCollapsed = IsCollapsed(sub.id);
                local subRow = GetRow("sub:" .. sub.id, CreateHeaderRow, "sub", sub.id);
                subRow.SetHeader(sub.title, sCollapsed, SubCountText(sub));
                sw.list:AddItem(subRow);

                if (not sCollapsed) then
                    if (sub.rows ~= nil) then
                        for i, data in ipairs(sub.rows) do
                            local row = GetRow("stat:" .. data.key, CreateStatRow);
                            row.SetData(data, (i % 2) == 0);
                            sw.list:AddItem(row);
                        end
                    end
                    if (sub.items ~= nil) then
                        for _, e in ipairs(sub.items) do
                            local itemId = "item." .. tostring(e.slot);
                            local expandable = (e.item ~= nil)
                                and ((e.desc or "") ~= "" or (e.extra or "") ~= "");
                            local expanded = expandable and not IsCollapsed(itemId);
                            local row = GetRow("item:" .. tostring(e.slot), CreateItemRow);
                            row.SetData(e, expandable, expanded);
                            sw.list:AddItem(row);
                            if (expanded) then
                                local desc = GetRow("desc:" .. tostring(e.slot), CreateDescRow);
                                desc.SetData(e);
                                sw.list:AddItem(desc);
                            end
                        end
                    end
                end
            end
        end
    end

    -- best effort: scroll the old bottom row (or top row) back into view;
    -- losing the position is acceptable
    local index = ListIndexOf(bottomRow) or ListIndexOf(topRow);
    if (index ~= nil) then ListEnsureVisible(index); end
end

-- Values only (no structure change). Collapsed rows are updated too.
function CS.StatsWindow.UpdateValues(snap)
    for _, group in ipairs(snap.groups) do
        for _, sub in ipairs(group.subs) do
            if (sub.rows ~= nil) then
                for _, data in ipairs(sub.rows) do
                    local row = CS.rows["stat:" .. data.key];
                    if (row ~= nil) then row.SetValue(data.value or "", data.color); end
                end
            end
        end
    end
end

-- Called by the ticker when dirty (and the window is visible).
function CS.StatsWindow.Refresh()
    local snap = CS.Model.Collect();
    CS.snapshot = snap;
    CS.Util.SetText(CS.sw.summary, snap.summary);
    local sig = CS.Model.Signature(snap);
    if (CS.dirty.full or sig ~= CS.lastSignature) then
        CS.lastSignature = sig;
        CS.StatsWindow.Rebuild(snap);
    else
        CS.StatsWindow.UpdateValues(snap);
    end
    CS.SharePanel.Update(snap);
    CS.dirty.full = false;
    CS.dirty.values = false;
end

------------------------------------------------------------------------
-- COLLAPSE / SHOW
------------------------------------------------------------------------

function CS.StatsWindow.Toggle(id)
    if (id == nil) then return; end
    CS.Settings.SetCollapsed(id, not CS.Settings.IsCollapsed(id));
    if (CS.snapshot ~= nil) then
        CS.StatsWindow.Rebuild(CS.snapshot);
    else
        CS.MarkDirty(true);
    end
end

local function SetAll(collapsed)
    local snap = CS.snapshot;
    CS.Settings.SetCollapsed("char", collapsed);
    CS.Settings.SetCollapsed("equip", collapsed);
    if (snap ~= nil) then
        for _, group in ipairs(snap.groups) do
            CS.Settings.SetCollapsed(group.id, collapsed);
            for _, sub in ipairs(group.subs) do
                CS.Settings.SetCollapsed(sub.id, collapsed);
                if (sub.items ~= nil) then
                    for _, e in ipairs(sub.items) do
                        CS.Settings.SetCollapsed("item." .. tostring(e.slot), collapsed);
                    end
                end
            end
        end
        CS.StatsWindow.Rebuild(snap);
    else
        CS.MarkDirty(true);
    end
end

function CS.StatsWindow.ExpandAll() SetAll(false); end
function CS.StatsWindow.CollapseAll() SetAll(true); end

--[[
    HUD (F12). CS.hudHidden mirrors the game's HUD state and changes ONLY
    on the HUD key. The settings (mainVisible / iconVisible) are what the
    user wants; F12 hides both windows and restores them from the settings.
    Commands while the HUD is hidden change the settings and show / hide
    the window directly, but never touch CS.hudHidden.
]]
function CS.SetHudHidden(hidden)
    CS.hudHidden = hidden;
    CS.hudApplying = true;
    pcall(function()
        if (hidden) then
            CS.mainWindow:SetVisible(false);
            CS.iconWindow:SetVisible(false);
        else
            CS.iconWindow:SetVisible(CS.settings.iconVisible == true);
            CS.mainWindow:SetVisible(CS.settings.mainVisible == true);
        end
    end);
    CS.hudApplying = false;
end

function CS.ShowMain(show)
    CS.settings.mainVisible = show;
    CS.Settings.SaveSoon();
    CS.mainWindow:SetVisible(show);
    if (show) then CS.mainWindow:Activate(); end
end

function CS.ToggleMain()
    CS.ShowMain(not CS.mainWindow:IsVisible());
end
