--[[=========================================================================

    CharacterStats -- SharePanel.lua
    Bottom panel of the main window: channel selector, page selector,
    preview, Print button and the Quickslot that sends the current page.

    Plugins cannot send chat themselves. The Quickslot holds an Alias
    shortcut ("/say <text>") and the game executes it when the USER
    clicks the slot - exactly like a typed command.

=========================================================================]]

CS.SharePanel = { };
CS.sp = { };          -- controls of the share panel
CS.sharePages = { };

local function NewLabel(parent, font, colour, align)
    local label = Turbine.UI.Label();
    label:SetParent(parent);
    label:SetFont(font);
    label:SetForeColor(colour);
    label:SetTextAlignment(align or Turbine.UI.ContentAlignment.MiddleLeft);
    label:SetMultiline(false);     -- the preview switches it back on
    if (CS.Util.Has(label, "SetMarkupEnabled")) then label:SetMarkupEnabled(false); end
    return label;
end

local function CurrentCommand()
    return CS.Util.ChannelCommand(CS.settings.channel);
end

-- The saved page number is only clamped for display: right after login
-- fewer pages may exist for a moment.
local function CurrentPage()
    local pages = CS.sharePages;
    if (#pages == 0) then return nil; end
    local i = CS.Util.Clamp(CS.settings.page, 1, #pages);
    return pages[i], i;
end

local SetText = CS.Util.SetText;

------------------------------------------------------------------------
-- BUILD / LAYOUT
------------------------------------------------------------------------

function CS.SharePanel.Build(win)
    local sp = CS.sp;
    sp.panel = Turbine.UI.Control();
    sp.panel:SetParent(win);
    sp.panel:SetBackColor(CS.COL_PANEL_BG);

    sp.title = NewLabel(sp.panel, CS.FONT_ROW, CS.COL_SUB);
    sp.title:SetText("Share to:");
    sp.title:SetMouseVisible(false);

    -- channel selector (a Label used as a drop-down button)
    sp.channel = NewLabel(sp.panel, CS.FONT_ROW, CS.COL_VALUE);
    sp.channel:SetBackColor(CS.COL_SUB_BG);
    sp.channel:SetMouseVisible(true);
    sp.channel.MouseEnter = function() sp.channel:SetBackColor(CS.COL_HOVER); end
    sp.channel.MouseLeave = function() sp.channel:SetBackColor(CS.COL_SUB_BG); end
    sp.channel.MouseClick = function() CS.SharePanel.ShowChannelMenu(); end

    -- page selector
    sp.prev = NewLabel(sp.panel, CS.FONT_SUB, CS.COL_GOLD, Turbine.UI.ContentAlignment.MiddleCenter);
    sp.prev:SetText("<");
    sp.prev:SetMouseVisible(true);
    sp.prev.MouseClick = function() CS.SharePanel.StepPage(-1); end
    sp.page = NewLabel(sp.panel, CS.FONT_SMALL, CS.COL_VALUE, Turbine.UI.ContentAlignment.MiddleCenter);
    sp.page:SetMouseVisible(false);
    sp.next = NewLabel(sp.panel, CS.FONT_SUB, CS.COL_GOLD, Turbine.UI.ContentAlignment.MiddleCenter);
    sp.next:SetText(">");
    sp.next:SetMouseVisible(true);
    sp.next.MouseClick = function() CS.SharePanel.StepPage(1); end

    -- preview of exactly what will be sent (wraps; scrolls if it is longer
    -- than the box - scrollbar on a Label as in PimpYourText)
    sp.preview = NewLabel(sp.panel, CS.FONT_SMALL, CS.COL_VALUE, Turbine.UI.ContentAlignment.TopLeft);
    sp.preview:SetMultiline(true);
    sp.preview:SetMouseVisible(false);
    sp.preview:SetBackColor(CS.COL_PREVIEW_BG);
    sp.previewScroll = Turbine.UI.Lotro.ScrollBar();
    sp.previewScroll:SetOrientation(Turbine.UI.Orientation.Vertical);
    sp.previewScroll:SetParent(sp.panel);
    sp.preview:SetVerticalScrollBar(sp.previewScroll);

    sp.hint = NewLabel(sp.panel, CS.FONT_SMALL, CS.COL_DIM);
    sp.hint:SetMouseVisible(false);

    sp.print = Turbine.UI.Lotro.Button();
    sp.print:SetParent(sp.panel);
    sp.print:SetText("Print");
    sp.print.Click = function() CS.SharePanel.PrintAll(); end

    -- the send slot
    local qs = Turbine.UI.Lotro.Quickslot();
    sp.quickslot = qs;
    qs:SetParent(sp.panel);
    qs:SetSize(40, 40);
    qs:SetAllowDrop(false);
    if (CS.Util.Has(qs, "SetUseOnRightClick")) then pcall(qs.SetUseOnRightClick, qs, false); end
    qs.ShortcutChanged = function()
        if (CS.settingShortcut) then return; end
        -- re-apply our alias if the user dragged it away / replaced it
        local data;
        local ok, sc = pcall(qs.GetShortcut, qs);
        if (ok and sc ~= nil) then data = CS.Util.Call(sc, "GetData"); end
        if (data ~= CS.lastAlias) then CS.SharePanel.UpdateShortcut(true); end
    end
    qs.MouseEnter = function() qs:Focus(); end

    -- caption under the slot (not on top of it: the slot draws the alias
    -- icon and text itself); mouse-invisible
    sp.sendLabel = NewLabel(sp.panel, CS.FONT_ROW, CS.COL_GOLD, Turbine.UI.ContentAlignment.MiddleCenter);
    sp.sendLabel:SetText("Send");
    sp.sendLabel:SetMouseVisible(false);

    CS.SharePanel.UpdateChannelText();
end

-- Panel height for a main window of height H: taller windows get a
-- taller preview.
function CS.SharePanel.HeightFor(H)
    local extra = CS.Util.Clamp(math.floor((H - CS.MAIN_MIN_H) / 4), 0, CS.SHARE_EXTRA_MAX);
    return CS.SHARE_H + extra;
end

function CS.SharePanel.Layout(x, y, w, h)
    local sp = CS.sp;
    if (sp.panel == nil) then return; end
    h = h or CS.SHARE_H;
    sp.panel:SetPosition(x, y);
    sp.panel:SetSize(w, h);

    sp.title:SetPosition(2, 0);     sp.title:SetSize(56, 20);
    sp.channel:SetPosition(60, 0);  sp.channel:SetSize(96, 20);
    sp.prev:SetPosition(160, 0);    sp.prev:SetSize(20, 20);
    sp.page:SetPosition(182, 0);    sp.page:SetSize(math.max(20, w - 20 - 2 - 182), 20);
    sp.next:SetPosition(w - 20, 0); sp.next:SetSize(20, 20);

    local previewH = h - 50;
    sp.preview:SetPosition(2, 24);  sp.preview:SetSize(math.max(20, w - 70), previewH);
    sp.previewScroll:SetPosition(w - 66, 24);
    sp.previewScroll:SetSize(CS.SCROLL_W, previewH);
    sp.hint:SetPosition(2, h - 24); sp.hint:SetSize(math.max(20, w - 56 - 82), 20);
    sp.print:SetPosition(w - 56 - 78, h - 24);
    sp.print:SetSize(72, 20);

    -- right column (w - 56 .. w): slot, caption below it
    sp.quickslot:SetPosition(w - 48, 24);
    sp.sendLabel:SetPosition(w - 56, 24 + 40 + 2);
    sp.sendLabel:SetSize(56, 16);
end

------------------------------------------------------------------------
-- CONTENT
------------------------------------------------------------------------

function CS.SharePanel.UpdateChannelText()
    local ch = CS.Util.FindChannel(CS.settings.channel) or CS.CHANNELS[1];
    SetText(CS.sp.channel, " " .. ch.label .. "  v");
end

-- Rebuilds the pages from a snapshot and refreshes the panel.
function CS.SharePanel.Update(snap)
    local sp = CS.sp;
    if (snap ~= nil) then
        CS.sharePages = CS.ShareText.Build(snap, CS.settings.maxLen, string.len(CurrentCommand()));
    end
    local page, index = CurrentPage();
    if (page == nil) then
        SetText(sp.page, "-");
        SetText(sp.preview, "");
        SetText(sp.hint, "Nothing to share yet");
        return;
    end
    local data = CurrentCommand() .. " " .. page.text;
    SetText(sp.page, index .. "/" .. #CS.sharePages .. " " .. page.title);
    -- back to the top on new text; best effort only, a bound scroll bar
    -- may refuse SetValue ("Invalid operation while the scroll bar is bound")
    if (SetText(sp.preview, data)) then pcall(sp.previewScroll.SetValue, sp.previewScroll, 0); end
    SetText(sp.hint, string.len(data) .. "/" .. CS.settings.maxLen .. " chars");
    CS.SharePanel.UpdateChannelText();
    CS.SharePanel.UpdateShortcut(false);
end

-- Puts the current page into the Quickslot (only when the text changed).
function CS.SharePanel.UpdateShortcut(force)
    local page = CurrentPage();
    if (page == nil or CS.sp.quickslot == nil) then return; end
    local data = CurrentCommand() .. " " .. page.text;
    if (data == CS.lastAlias and not force) then return; end
    CS.settingShortcut = true;
    local ok, err = pcall(function()
        CS.sp.quickslot:SetShortcut(Turbine.UI.Lotro.Shortcut(Turbine.UI.Lotro.ShortcutType.Alias, data));
    end);
    CS.settingShortcut = false;
    if (ok) then CS.lastAlias = data; else CS.ReportError(err); end
end

function CS.SharePanel.StepPage(direction)
    local n = #CS.sharePages;
    if (n == 0) then return; end
    local i = CS.Util.Clamp(CS.settings.page, 1, n) + direction;
    if (i < 1) then i = n; elseif (i > n) then i = 1; end
    CS.settings.page = i;
    CS.Settings.SaveSoon();
    CS.SharePanel.Update(nil);
end

function CS.SharePanel.SetChannel(id)
    if (CS.Util.FindChannel(id) == nil) then return false; end
    CS.settings.channel = id;
    CS.Settings.SaveSoon();
    -- the command length changes the page budget: rebuild the pages
    CS.SharePanel.Update(CS.snapshot);
    CS.SharePanel.UpdateChannelText();
    return true;
end

function CS.SharePanel.ShowChannelMenu()
    if (CS.channelMenu == nil) then
        CS.channelMenu = Turbine.UI.ContextMenu();
        local items = CS.channelMenu:GetItems();
        for _, ch in ipairs(CS.CHANNELS) do
            local mi = Turbine.UI.MenuItem(ch.label);
            mi.channelId = ch.id;
            mi.Click = function(sender, args) CS.SharePanel.SetChannel(ch.id); end
            items:Add(mi);
        end
    end
    local items = CS.channelMenu:GetItems();
    for i = 1, items:GetCount() do
        local mi = items:Get(i);
        if (CS.Util.Has(mi, "SetChecked")) then
            pcall(mi.SetChecked, mi, mi.channelId == CS.settings.channel);
        end
    end
    CS.channelMenu:ShowMenu();
end

-- Writes all pages to the user's own chat window (nobody else sees it).
function CS.SharePanel.PrintAll()
    local snap = CS.snapshot;
    if (snap == nil) then
        local ok, result = pcall(CS.Model.Collect);
        if (not ok) then CS.ReportError(result); return; end
        snap = result;
    end
    local cmd = CurrentCommand();
    local pages = CS.ShareText.Build(snap, CS.settings.maxLen, string.len(cmd));
    Turbine.Shell.WriteLine("CharacterStats: " .. #pages .. " page(s) for " .. cmd .. ":");
    for i, page in ipairs(pages) do
        Turbine.Shell.WriteLine("<rgb=#BBBBBB>" .. i .. ". " .. cmd .. " " .. page.text .. "</rgb>");
    end
end
