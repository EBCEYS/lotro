--[[=========================================================================

    CharacterStats -- IconWindow.lua
    Small frameless screen icon: left click toggles the main window,
    left drag moves it, right click opens a context menu. It also listens
    for the HUD toggle (F12) and hides / restores both windows.

=========================================================================]]

CS.IconWindow = { };

local drag;           -- { x, y, moved } while the left button is down
local menuItems = { };

local function Border(parent, x, y, w, h)
    local c = Turbine.UI.Control();
    c:SetParent(parent);
    c:SetPosition(x, y);
    c:SetSize(w, h);
    c:SetBackColor(CS.COL_GOLD);
    c:SetMouseVisible(false);
    return c;
end

function CS.IconWindow.Build()
    local s = CS.settings;
    local size = CS.ICON_SIZE;
    local w = Turbine.UI.Window();
    CS.iconWindow = w;
    w:SetSize(size, size);
    w:SetPosition(s.iconX, s.iconY);
    w:SetBackColor(CS.COL_ICON_BG);
    w:SetZOrder(10);
    w:SetMouseVisible(true);

    Border(w, 0, 0, size, 1);
    Border(w, 0, size - 1, size, 1);
    Border(w, 0, 0, 1, size);
    Border(w, size - 1, 0, 1, size);

    local text = Turbine.UI.Label();
    text:SetParent(w);
    text:SetPosition(0, 0);
    text:SetSize(size, size);
    text:SetFont(CS.FONT_ICON);
    text:SetForeColor(CS.COL_GOLD);
    text:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    text:SetFontStyle(Turbine.UI.FontStyle.Outline);
    text:SetOutlineColor(CS.COL_BLACK);
    text:SetText("CS");
    text:SetMouseVisible(false);
    CS.iconText = text;

    w.MouseEnter = function() w:SetBackColor(CS.COL_ICON_BG_HOVER); end
    w.MouseLeave = function() w:SetBackColor(CS.COL_ICON_BG); end

    -- mouse: left click = toggle, left drag = move, right click = menu
    w.MouseDown = function(sender, args)
        if (args.Button == Turbine.UI.MouseButton.Left) then
            drag = { x = args.X, y = args.Y, moved = false };
        end
    end
    w.MouseMove = function(sender, args)
        if (drag == nil or CS.settings.iconLocked) then return; end
        if (not drag.moved and math.abs(args.X - drag.x) + math.abs(args.Y - drag.y) < CS.DRAG_THRESHOLD) then
            return;
        end
        drag.moved = true;
        local nx = CS.Util.Clamp(w:GetLeft() + args.X - drag.x, 0, CS.Settings.DisplayWidth() - size);
        local ny = CS.Util.Clamp(w:GetTop() + args.Y - drag.y, 0, CS.Settings.DisplayHeight() - size);
        w:SetPosition(nx, ny);
    end
    w.MouseUp = function(sender, args)
        if (args.Button == Turbine.UI.MouseButton.Left and drag ~= nil) then
            local moved = drag.moved;
            drag = nil;
            if (moved) then CS.Settings.SaveSoon(); else CS.ToggleMain(); end
        elseif (args.Button == Turbine.UI.MouseButton.Right) then
            CS.IconWindow.ShowMenu();
        end
    end

    -- HUD toggle (F12): hide / restore both windows, without saving
    -- (a hidden window still receives the key - LotroPointTracker)
    CS.hudHidden = false;
    w:SetWantsKeyEvents(true);
    w.KeyDown = function(sender, args)
        if (args.Action ~= CS.ACTION_HUD_TOGGLE) then return; end
        CS.SetHudHidden(not CS.hudHidden);
    end

    CS.IconWindow.BuildMenu();
    w:SetVisible(s.iconVisible);
end

------------------------------------------------------------------------
-- CONTEXT MENU
------------------------------------------------------------------------

function CS.IconWindow.BuildMenu()
    local menu = Turbine.UI.ContextMenu();
    CS.iconMenu = menu;
    local items = menu:GetItems();

    local function Add(key, text, onClick)
        local mi = Turbine.UI.MenuItem(text);
        mi.Click = function(sender, args) onClick(); end
        items:Add(mi);
        menuItems[key] = mi;
    end

    Add("toggle", "Show stats window", function() CS.ToggleMain(); end);
    Add("refresh", "Refresh", function() CS.MarkDirty(true); end);
    Add("expand", "Expand all", function()
        CS.ShowMain(true);
        CS.StatsWindow.ExpandAll();
    end);
    Add("collapse", "Collapse all", function()
        CS.ShowMain(true);
        CS.StatsWindow.CollapseAll();
    end);
    Add("lock", "Lock icon position", function()
        CS.settings.iconLocked = not CS.settings.iconLocked;
        CS.Settings.SaveSoon();
        CS.OptionsPanel.Refresh();
    end);
    Add("hide", "Hide this icon", function()
        CS.IconWindow.SetShown(false);
        Turbine.Shell.WriteLine("CharacterStats: icon hidden - type /cstats icon to show it again.");
    end);
    Add("options", "Options...", function() CS.OpenOptions(); end);
end

function CS.IconWindow.UpdateMenuText()
    local toggle = menuItems.toggle;
    if (toggle ~= nil and CS.mainWindow ~= nil) then
        toggle:SetText(CS.mainWindow:IsVisible() and "Hide stats window" or "Show stats window");
    end
    local lock = menuItems.lock;
    if (lock ~= nil and CS.Util.Has(lock, "SetChecked")) then
        pcall(lock.SetChecked, lock, CS.settings.iconLocked == true);
    end
end

function CS.IconWindow.ShowMenu()
    CS.IconWindow.UpdateMenuText();
    CS.iconMenu:ShowMenu();
end

-- Shows / hides the icon and remembers it (also while the HUD is hidden:
-- an explicit command wins, the F12 state is not touched).
function CS.IconWindow.SetShown(show)
    CS.settings.iconVisible = show;
    CS.iconWindow:SetVisible(show);
    CS.Settings.SaveSoon();
    CS.OptionsPanel.Refresh();
end

-- Opens the plugin manager options. The U49 docs name
-- Turbine.LotroPluginManager.ShowOptions, the in-game API dump only has
-- Turbine.PluginManager.ShowOptions - neither is confirmed, so try both
-- and fall back to a hint.
function CS.OpenOptions()
    if (CS.thisPlugin ~= nil) then
        local managers = { Turbine.LotroPluginManager, Turbine.PluginManager };
        for i = 1, 2 do
            local manager = managers[i];
            if (type(manager) == "table" and type(manager.ShowOptions) == "function") then
                if (pcall(manager.ShowOptions, CS.thisPlugin)) then return; end
            end
        end
    end
    Turbine.Shell.WriteLine("Open the plugin manager and select " .. CS.PLUGIN_NAME .. " -> Options.");
end
