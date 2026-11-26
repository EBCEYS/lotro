--[[=========================================================================

    ItemsTracker v1.0.0  --  The Lord of the Rings Online plugin
    -------------------------------------------------------------------

    * A small window with item slots. Drag any item from your bags onto
      a slot and the slot shows how many of that item you carry in your
      bags (all stacks added up). The count updates live: right away
      when items are added, removed or moved, and every 2 seconds for
      stacks that grow or shrink in place.
    * An item that is used up stays in its slot with a red "0" and a
      darkened icon, so you see at once what to restock.
    * Dropping an item on a filled slot replaces it; dropping an item
      that is already tracked in another slot moves it there.
    * Ctrl+drag: hold Ctrl over a tracked slot and the real item from
      your bags appears over its icon; drag it like from the bags, e.g.
      into the auction house search box. The slot keeps tracking the
      item. While Ctrl is held that item control is the game's own:
      Ctrl+click may use the item, and dropping it on the ground may ask
      to destroy it, as from the bags. An item with count 0 (not in the
      bags) cannot be dragged.
    * Right click a slot for a menu: set / clear the target count, clear
      the slot, clear all slots, options. Hover a slot (or left click it
      to pin it) to see the item name and its count in the line under
      the slots.
    * Target count: each slot can have an expected count (double-click
      a tracked slot, "Set target..." in the slot menu, or /itr target).
      The count then changes colour from red (none) over yellow (half)
      to green (target reached), and a thin bar at the bottom of the
      slot shows the progress.
    * The number of slots (1-30) can be changed with the "-" / "+"
      buttons at the top of the window or in the options; the slots per
      row (1-12) in the options. Items in slots beyond the number of
      slots are kept, only hidden, and come back when the number is
      raised again.
    * A small "IT" screen icon: left click shows / hides the window, left
      drag moves the icon, right click opens a menu (lock / unlock the
      icon position, show / hide the main window, craft calculator,
      options). The HUD toggle (F12) hides the icon, the window and the
      craft calculator and restores them on the next press.
    * A craft calculator (its own window, also from the icon menu or
      /itr craft): pick a learned profession, a mode (Proficiency,
      Mastery or Full tier) and a recipe of the next tier, and it shows
      the crafts needed for the XP you are missing and the direct
      ingredients for them. "Apply to tracker" starts a PICK MODE: the
      calculator's previous auto targets are cleared, the empty slots
      of the main window light up, and a left click on one assigns the
      next ingredient to it (click the slot again to take it back;
      slots that already track an item are never touched, and the
      calculator never changes the number of slots). "Done: N of M"
      (the same button) confirms what you picked - a partial
      assignment is fine - while "Stop picking" or Escape in the main
      window throws the picks away (Escape needs no window focus: the
      key events reach the window while the picking is on, like the
      F12 toggle). While you pick, the picked slots are protected:
      clearing, re-targeting or re-dropping one is refused with a
      hint until the picking is stopped, the target editor stays
      closed, and "N of M" counts only what is really assignable (an
      ingredient that got tracked elsewhere is skipped). The picked
      slots and their targets update live while you craft; "Clear
      auto targets" removes the calculator's targets again (details
      in ItemsTracker.md).
    * The tracked items and their targets, the window and icon positions
      and whether the window is shown are remembered per character; the
      craft calculator's choices too.

    SETTINGS (plugin manager -> ItemsTracker -> Options, or /itr options)
    --------
    * Number of slots (also "-" / "+" in the window), slots per row
    * Lock icon position
    * Craft calculator (open / toggle it; its choices are stored per
      character)
    Settings are stored account-wide.

    INSTALLATION
    ------------
    1. Copy the ItemsTracker folder (containing Main.lua,
       CraftingDataProvider.lua, CraftingWindow.lua and
       ItemsTracker.plugin) into the game Plugins directory:
         Documents\The Lord of the Rings Online\Plugins\
       so that the files end up as:
         ...\Plugins\ItemsTracker\Main.lua
         ...\Plugins\ItemsTracker\CraftingDataProvider.lua
         ...\Plugins\ItemsTracker\CraftingWindow.lua
         ...\Plugins\ItemsTracker\ItemsTracker.plugin
       Nothing needs to be created or edited.
    2. In game:  /plugins load ItemsTracker

    COMMANDS
    --------
    /itr show           show the main window
    /itr hide           hide the main window
    /itr toggle         show / hide the main window
    /itr options        open the settings in the plugin manager
    /itr slots <n>      number of slots (1-30)
    /itr perrow <n>     slots per row (1-12)
    /itr target <n> <count>
                        expected count of the item in slot n (1-999999,
                        digits; "1,000" / "1.000" / "1'000" are 1000);
                        "/itr target <n> clear" (or 0) removes it
    /itr clear <n>      clear slot n ("/itr clear all" clears every slot)
                        (a slot the craft pick is using refuses)
    /itr list           list the tracked items, counts and targets in chat
                        (calculator targets are marked "(auto)")
    /itr craft [show|hide|toggle|clear|debug]
                        the craft calculator: show / hide / toggle it,
                        "clear" removes its auto targets (targets set by
                        hand are kept), "debug" prints the character's
                        crafting data (troubleshooting)
    /itr debug          print every drop event (slot or window, with
                        coordinates), drop errors and the Ctrl+drag
                        steps (troubleshooting)
    /itr help           command overview

    LIMITATIONS
    -----------
    * Only the bags are counted: not the vault, shared storage, equipped
      items or wallet currencies.
    * Items are recognised by name: different items with the same name
      are added up, and after switching the client language the items
      have to be dragged in again.
    * A stack that changes in place can take up to 2 seconds to update.
    * The slot shows a static icon: no native item tooltip, and clicking
      a slot never uses the item - unless Ctrl is held (Ctrl+drag).
    * Craft calculator: estimates only (no critical successes or bonus
      XP), direct ingredients only (no sub-recipes), optional
      ingredients and ingredient packs ignored, ingredients matched by
      name (client language), recipe tiers as the game reports them.
      The calculator never changes the number of slots: an assignment
      only goes into an EMPTY slot that you click yourself, so if fewer
      empty slots are visible than the recipe has ingredients, pick
      what fits (or add slots with the "+" button first). The crafting
      events are not yet verified in game; a check every 3 seconds
      covers them.

    LICENSE
    -------
    "THE BEER-WARE LICENSE" (Revision 42):
    https://github.com/EBCEYS wrote this file. As long as you retain this
    notice you can do whatever you want with it. If we meet some day, and
    you think this stuff is worth it, you can buy me a beer in return.

=========================================================================]]

import "Turbine";
import "Turbine.Gameplay";
import "Turbine.UI";
import "Turbine.UI.Lotro";

-- the plugin's shared table (GLOBAL): the craft calculator files only
-- define functions in it when imported; ITR.Craft.Init runs after BOOT
ITR = { };
import "ItemsTracker.CraftingDataProvider";
import "ItemsTracker.CraftingWindow";

------------------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------------------

local PLUGIN_NAME        = "ItemsTracker";
local PLUGIN_VERSION     = "1.0.0";

local SAVE_KEY           = "ItemsTrackerData";       -- per character
local SETTINGS_KEY       = "ItemsTrackerSettings";   -- account wide

-- defaults of the user settings (changed in the plugin manager options)
local DEFAULT_SETTINGS = {
    slotCount   = 6,      -- visible slots
    slotsPerRow = 6,      -- grid columns
    iconLocked  = false,  -- screen icon cannot be dragged
};

local MIN_SLOTS,   MAX_SLOTS   = 1, 30;
local MIN_PER_ROW, MAX_PER_ROW = 1, 12;

local CONTENT_TOP        = 34;     -- Lotro.Window: the title bar covers
                                   -- roughly the first 30px
local PAD_X              = 20;     -- left / right padding
local SLOT_SIZE          = 40;
local SLOT_GAP           = 4;
local ICON_INSET         = 4;      -- 32x32 item icon inside the 40x40 slot
local NAME_H             = 18;     -- name line under the grid
local NAME_CHAR_W        = 7;      -- estimated px per character (Verdana12)
local STEP_H             = 20;     -- "[-] 6 slots [+]" row at the top, left-aligned
                                   -- (never moves when the window resizes)
local STEP_BTN_W         = 24;
local STEP_LABEL_W       = 70;
local STEP_GAP           = 4;
local BOTTOM_PAD         = 14;
local MIN_WIN_W          = 180;    -- room for the title "Items Tracker" (and
                                   -- the 126 px stepper row)
local BAR_H              = 3;      -- target progress bar at the slot bottom
local EDIT_W             = 64;     -- target editor TextBox (right end of the name line)
local EDIT_GRACE         = 0.3;    -- s after opening the editor in which a FocusLost
                                   -- re-focuses it instead of committing (TARGET COUNT)

local MIN_TARGET, MAX_TARGET = 1, 999999;

local SCAN_THROTTLE      = 0.25;   -- s between event-triggered scans
local POLL_INTERVAL      = 2;      -- s between periodic scans (a stack that
                                   -- changes in place fires no event)
local DROP_SET_SUCCESSFUL = false; -- report drops as successful (PLAN 4.1)
local DROP_PAIR_TIME     = 0.2;    -- s: a window drop this soon after a slot
                                   -- drop is the same drop (see DRAG & DROP)
local HINT_REPEAT        = 2;      -- s before the same hint is printed again
local DRAG_TIMEOUT       = 10;     -- s a Ctrl+drag keeps the drag source shown
                                   -- while the mouse is away (DRAG SOURCE)
local DRAG_GRACE         = 1;      -- s after DragStart before the mouse over the
                                   -- source slot without Ctrl ends the drag
local CTRL_DRAG_HINT     = " - Ctrl+drag";   -- name line, if it fits

local ACTION_HUD_TOGGLE  = 0x100000B3;  -- "toggle HUD" (F12 by default)
local ACTION_ENTER       = 162;
local ACTION_ESCAPE      = 145;

-- screen icon (same look as the InstanceLockTimer / CharacterStats icons)
local ICON_SIZE          = 36;
local ICON_GAP           = 8;      -- default gap between the icon and the main window
local DRAG_THRESHOLD     = 3;      -- px before a left press becomes a drag
local COL_GOLD           = Turbine.UI.Color(1, 0.82, 0.30);
local COL_BLACK          = Turbine.UI.Color(0, 0, 0);
local COL_ICON_BG        = Turbine.UI.Color(0.85, 0.08, 0.07, 0.05);   -- ARGB
local COL_ICON_BG_HOVER  = Turbine.UI.Color(0.95, 0.20, 0.16, 0.08);

-- slots (4 arguments = ARGB)
local COL_SLOT_BORDER    = Turbine.UI.Color(0.45, 0.45, 0.45);
local COL_SLOT_INNER     = Turbine.UI.Color(0.9, 0.06, 0.06, 0.06);
local COL_SLOT_HOVER     = Turbine.UI.Color(0.95, 0.18, 0.15, 0.08);
local COL_PLUS           = Turbine.UI.Color(0.40, 0.40, 0.40);
local COL_COUNT          = Turbine.UI.Color(1, 1, 1);
local COL_COUNT_ZERO     = Turbine.UI.Color(1, 0.40, 0.35);
local COL_ZERO_DIM       = Turbine.UI.Color(0.6, 0, 0, 0);   -- overlay at count 0
local COLOR_HEADER       = COL_GOLD;
local COLOR_TEXT         = Turbine.UI.Color(0.9, 0.9, 0.9);
local COLOR_HINT         = Turbine.UI.Color(0.65, 0.65, 0.65);

-- item icon layers, bottom -> top, and their keys in the saved data
local IMAGE_GETTERS = { "GetBackgroundImageID", "GetUnderlayImageID", "GetShadowImageID", "GetIconImageID" };
local IMAGE_KEYS    = { "bg", "under", "shadow", "icon" };

------------------------------------------------------------------------
-- STATE / FORWARD DECLARATIONS
------------------------------------------------------------------------

local settings;            -- user settings, see DEFAULT_SETTINGS
local data;                -- per-character data (positions, winVisible, slots)
local trackedSlots = { };  -- [1..MAX_SLOTS] = { name, quality, images, scType, scData, count, target } or nil
local unloaded = false;    -- set by OnUnload (CLEANUP section)
local hudHidden = false;   -- the game HUD is hidden (F12), see SCREEN ICON
local hudApplying = false; -- windows are being hidden / restored for the HUD
local debugDrops = false;  -- /itr debug: print every drop event (session only)
local saveDirty = false;   -- character data changed, saved by the clock
local settingsDirty = false; -- settings changed by the window stepper, saved by the clock
local posDirtyTicks = 0;   -- seconds until the moved window position is saved
-- Ctrl+drag source (DRAG SOURCE): slot = slot the item control is shown
-- on (nil = hidden), tried = slot already looked up during this Ctrl
-- press, dragging / dragAt / leftWin / leftSlot = a drag started from it,
-- stale = the bags changed while it was shown, recheck = hovered slot
-- whose MouseLeave may have been missed, keyFn / keySelf / keyFailed =
-- the working IsControlKeyDown form; plus the section's functions
local dragSrc = { };

local SaveAll;             -- PERSISTENCE
local SyncWinVisible;      -- PERSISTENCE
local MarkDirty;           -- INVENTORY COUNTER
local PaintSlot;           -- USER INTERFACE
local PaintSlots;          -- USER INTERFACE
local RefreshNameLine;     -- USER INTERFACE
local RefreshOptions;      -- OPTIONS PANEL
local ChangeSettings;      -- OPTIONS PANEL
local OpenOptions;         -- OPTIONS PANEL

------------------------------------------------------------------------
-- UTILITIES
------------------------------------------------------------------------

local function Clamp(value, min, max)
    if (value ~= value) then return min; end   -- NaN: every comparison is false
    if (value < min) then return min; end
    if (value > max) then return max; end
    return value;
end

-- Calls obj:name(...) if that method exists; nil on any error. Used for
-- every item / backpack / drag & drop call (several are dump-only).
local function Call(obj, name, ...)
    if (obj == nil) then return nil; end
    local okF, f = pcall(function() return obj[name]; end);
    if (not okF or type(f) ~= "function") then return nil; end
    local ok, a, b, c = pcall(f, obj, ...);
    if (ok) then return a, b, c; end
    return nil;
end

-- Safe field lookup on a table / API object (nil on error).
local function Field(obj, name)
    if (obj == nil) then return nil; end
    local ok, v = pcall(function() return obj[name]; end);
    if (ok) then return v; end
    return nil;
end

--[[
    Text from a game getter, ready to show. For a missing localised
    string the client returns "<string table error: tableDID [..] token
    [..]>" (seen in game). Such segments are removed (up to ">" or the end
    of the line); "" if nothing meaningful remains.
]]
local STRING_TABLE_ERROR = "string table error";

local function CleanGameText(s)
    if (type(s) ~= "string") then return ""; end
    while (true) do
        local a, b = string.find(string.lower(s), STRING_TABLE_ERROR, 1, true);
        if (a == nil) then break; end
        if (a > 1 and string.sub(s, a - 1, a - 1) == "<") then a = a - 1; end
        local e = string.find(s, ">", b + 1, true);
        local nl = string.find(s, "\n", b + 1, true);
        if (nl ~= nil and (e == nil or nl < e)) then e = nl - 1; end
        if (e == nil) then e = string.len(s); end
        s = string.sub(s, 1, a - 1) .. string.sub(s, e + 1);
    end
    s = string.gsub(s, "^%s+", "");
    s = string.gsub(s, "%s+$", "");
    if (not string.find(s, "[%w\128-\255]")) then return ""; end
    return s;
end

-- Item names are stored as plain ASCII: every byte outside 0x20..0x7E and
-- "%" itself become "%XX" (PluginData is picky about other characters).
local function EncodeText(s)
    return (string.gsub(s, ".", function(c)
        local b = string.byte(c);
        if (b < 0x20 or b > 0x7E or b == 0x25) then return string.format("%%%02X", b); end
        return c;
    end));
end

local function DecodeText(s)
    return (string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)); end));
end

-- Whole number from a saved / API / typed value, nil if it is not a
-- finite number (tonumber accepts "nan", "inf" and "1e999").
local function WholeNumber(v)
    local n = tonumber(v);
    if (n == nil or n ~= n or n == math.huge or n == -math.huge) then return nil; end
    return math.floor(n);
end

-- Valid target count from a saved / typed value, nil if there is none
-- (not a finite number, or below 1).
local function ReadTarget(v)
    local n = WholeNumber(v);
    if (n == nil or n < MIN_TARGET) then return nil; end
    return Clamp(n, MIN_TARGET, MAX_TARGET);
end

-- Typed target text -> valid, n. Only digits with optional thousands
-- separators (spaces, ",", ".", "'") are valid: "1,000", "1 000", "1.000"
-- and "1'000" are all 1000 (so "7.9" is 79). "1e3", "0x10", signs and
-- anything else are not (valid = false). "" and 0 mean "no target"
-- (n = nil); other values are clamped to MIN_TARGET..MAX_TARGET.
local function ParseTargetText(text)
    text = string.gsub(text or "", "\194\160", " ");        -- no-break space
    text = string.gsub(text, "\226\128\175", " ");         -- narrow no-break space
    text = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "");
    if (text == "") then return true, nil; end
    if (not string.find(text, "^[%d%s,%.']+$") or not string.find(text, "%d")) then return false, nil; end
    local n = tonumber((string.gsub(text, "%D", "")));
    if (n == nil) then return false, nil; end
    if (n == 0) then return true, nil; end
    return true, Clamp(n, MIN_TARGET, MAX_TARGET);
end

-- Progress fraction of a slot with a target (0..1), nil without a target
-- or while the count is unknown.
local function TargetFraction(t)
    if (t == nil or t.target == nil or t.count == nil) then return nil; end
    return math.min(math.max(t.count, 0) / t.target, 1);
end

-- Gradient colour for the target progress: red (0) -> yellow (0.5) ->
-- green (1); like InstanceLockTimer's GetDailyColour, reversed. The red
-- end is a light red (1, 0.35, 0.3): pure red is hard to read on the
-- dark slot.
local function TargetColour(fraction)
    local h = Clamp(fraction, 0, 1) * 2;   -- 0 = red end, 2 = green end
    if (h <= 1) then                       -- light red -> yellow
        return Turbine.UI.Color(1, math.min(1, 0.35 + 0.65 * h), math.max(0, 0.3 * (1 - h)));
    end
    return Turbine.UI.Color(2 - h, 1, 0);  -- yellow -> green
end

-- Count shown in a slot: "37", "9999", "12k", "3M".
local function FormatCount(n)
    if (n == nil) then return "?"; end
    if (n < 10000) then return tostring(n); end
    if (n < 1000000) then return math.floor(n / 1000) .. "k"; end
    return math.floor(n / 1000000) .. "M";
end

-- Game text for a chat line: "<...>" would be read as markup, so tags and
-- stray "<" / ">" are removed (like CharacterStats' SanitizeChat).
local function ChatSafe(s)
    s = string.gsub(s, "<[^>]*>", "");
    s = string.gsub(s, "[<>]", "");
    s = string.gsub(s, "[\r\n\t]", " ");
    s = string.gsub(s, "%s+", " ");
    s = string.gsub(s, "^%s+", "");
    s = string.gsub(s, "%s+$", "");
    return s;
end

-- Top-left corner that keeps a w x h box on the screen. A box wider /
-- taller than the screen goes to x = 0 / y = 0, so its top-left part
-- (for the main window: title bar and "[-] N slots [+]" row) stays
-- reachable.
local function ClampToDisplay(x, y, w, h)
    local sw, sh = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
    x, y = math.floor(x), math.floor(y);
    if (type(sw) == "number") then x = (sw > w) and Clamp(x, 0, sw - w) or 0; end
    if (type(sh) == "number") then y = (sh > h) and Clamp(y, 0, sh - h) or 0; end
    return x, y;
end

-- First bytes of s, at most maxBytes long, never ending inside a UTF-8
-- multibyte sequence (continuation bytes are 0x80..0xBF).
local function Utf8Truncate(s, maxBytes)
    if (string.len(s) <= maxBytes) then return s; end
    local n = math.max(0, maxBytes);
    while (n > 0) do
        local b = string.byte(s, n + 1);
        if (b == nil or b < 0x80 or b >= 0xC0) then break; end
        n = n - 1;
    end
    return string.sub(s, 1, n);
end

-- s, or s cut and ended with "..." so it is at most maxBytes long; ""
-- if not even one character and "..." fit.
local function Shorten(s, maxBytes)
    if (string.len(s) <= maxBytes) then return s; end
    if (maxBytes < 4) then return ""; end
    local cut = string.gsub(Utf8Truncate(s, maxBytes - 3), "%s+$", "");
    if (cut == "") then return ""; end
    return cut .. "...";
end

-- "long" if it fits into maxBytes, else "short" (shortened if needed).
local function FitText(long, short, maxBytes)
    if (string.len(long) <= maxBytes) then return long; end
    return Shorten(short, maxBytes);
end

-- Item name colours by ItemQuality value (built from the enum names: the
-- values are not a rank).
local QUALITY_COLOR = { };
do
    local byName = {
        Common       = Turbine.UI.Color(1, 1, 1),
        Uncommon     = Turbine.UI.Color(1, 0.93, 0.35),
        Rare         = Turbine.UI.Color(0.78, 0.45, 1),
        Incomparable = Turbine.UI.Color(0.30, 0.90, 0.85),
        Legendary    = Turbine.UI.Color(1, 0.60, 0.15),
    };
    local qualities = Field(Turbine.Gameplay, "ItemQuality");
    for name, colour in pairs(byName) do
        local value = Field(qualities, name);
        if (type(value) == "number") then QUALITY_COLOR[value] = colour; end
    end
end

-- One chat line; the same text at most once every HINT_REPEAT seconds.
local lastHint = { };      -- text, at
local function Hint(text)
    local now = Turbine.Engine.GetGameTime();
    if (text == lastHint.text and lastHint.at ~= nil and now - lastHint.at < HINT_REPEAT) then return; end
    lastHint.text, lastHint.at = text, now;
    Turbine.Shell.WriteLine(PLUGIN_NAME .. ": " .. text);
end

local function HasTracked()
    for i = 1, MAX_SLOTS do
        if (trackedSlots[i] ~= nil) then return true; end
    end
    return false;
end

-- Number of tracked items in slots first..MAX_SLOTS.
local function CountTrackedFrom(first)
    local n = 0;
    for i = first, MAX_SLOTS do
        if (trackedSlots[i] ~= nil) then n = n + 1; end
    end
    return n;
end

------------------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------------------

local function LoadSettings()
    local ok, saved = pcall(
        Turbine.PluginData.Load, Turbine.DataScope.Account, SETTINGS_KEY);
    if (not ok or type(saved) ~= "table") then saved = { }; end

    local s = { };
    for key, default in pairs(DEFAULT_SETTINGS) do
        local value = saved[key];
        -- numbers may come back as strings depending on the client locale;
        -- NaN / inf fall back to the default
        if (type(default) == "number") then value = WholeNumber(value); end
        if (type(default) == "boolean" and type(value) == "string") then
            value = (value == "true");
        end
        if (type(value) ~= type(default)) then value = default; end
        s[key] = value;
    end
    s.slotCount   = Clamp(math.floor(s.slotCount), MIN_SLOTS, MAX_SLOTS);
    s.slotsPerRow = Clamp(math.floor(s.slotsPerRow), MIN_PER_ROW, MAX_PER_ROW);
    return s;
end

local function SaveSettings()
    pcall(Turbine.PluginData.Save, Turbine.DataScope.Account, SETTINGS_KEY, settings, nil);
end

------------------------------------------------------------------------
-- PERSISTENCE
--
-- data.slots uses string keys "s1".."s30" (no sparse integer arrays in
-- PluginData); names are stored with EncodeText, numbers as whole numbers.
------------------------------------------------------------------------

-- One saved slot -> in-memory record, or nil if it is not usable.
local function ReadSlotRecord(rec)
    if (type(rec) ~= "table" or type(rec.name) ~= "string") then return nil; end
    local name = CleanGameText(DecodeText(rec.name));
    if (name == "") then return nil; end
    local t = { name = name, images = { } };
    t.quality = WholeNumber(rec.quality);
    for k, key in ipairs(IMAGE_KEYS) do
        local id = WholeNumber(rec[key]);
        if (id ~= nil and id ~= 0) then t.images[k] = id; end
    end
    t.scType = WholeNumber(rec.scType);
    if (type(rec.scData) == "string") then t.scData = DecodeText(rec.scData); end
    t.target = ReadTarget(rec.target);
    -- craft calculator tags (AUTO TARGETS): only with a target, and
    -- "autoSlot" only together with "autoTarget"
    if (t.target ~= nil and (rec.autoTarget == true or rec.autoTarget == "true")) then
        t.autoTarget = true;
        if (rec.autoSlot == true or rec.autoSlot == "true") then t.autoSlot = true; end
    end
    return t;
end

local function LoadData()
    local ok, saved = pcall(
        Turbine.PluginData.Load, Turbine.DataScope.Character, SAVE_KEY);
    if (not ok or type(saved) ~= "table") then saved = { }; end

    local d = { };
    d.winX  = WholeNumber(saved.winX);
    d.winY  = WholeNumber(saved.winY);
    d.iconX = WholeNumber(saved.iconX);
    d.iconY = WholeNumber(saved.iconY);
    d.winVisible = saved.winVisible;
    if (type(d.winVisible) == "string") then d.winVisible = (d.winVisible ~= "false"); end
    if (type(d.winVisible) ~= "boolean") then d.winVisible = true; end
    trackedSlots = { };
    if (type(saved.slots) == "table") then
        for i = 1, MAX_SLOTS do
            trackedSlots[i] = ReadSlotRecord(saved.slots["s" .. i]);
        end
    end
    return d;
end

SaveAll = function()
    if (data == nil) then return; end
    pcall(function()
        if (win ~= nil) then
            data.winX = math.floor(win:GetLeft());
            data.winY = math.floor(win:GetTop());
        end
        if (iconWin ~= nil) then
            data.iconX = math.floor(iconWin:GetLeft());
            data.iconY = math.floor(iconWin:GetTop());
        end
        local slots = { };
        for i = 1, MAX_SLOTS do
            local t = trackedSlots[i];
            if (t ~= nil) then
                local rec = { name = EncodeText(t.name), quality = t.quality, scType = t.scType,
                    target = t.target };
                for k, key in ipairs(IMAGE_KEYS) do rec[key] = t.images[k]; end
                if (t.scData ~= nil) then rec.scData = EncodeText(t.scData); end
                if (t.autoTarget) then
                    rec.autoTarget = true;
                    if (t.autoSlot) then rec.autoSlot = true; end
                end
                slots["s" .. i] = rec;
            end
        end
        data.slots = slots;
        Turbine.PluginData.Save(Turbine.DataScope.Character, SAVE_KEY, data, nil);
    end);
end

-- Stores whether the main window is shown. data.winVisible is only
-- changed here, so hiding the window during unload or for the HUD toggle
-- never persists "hidden".
SyncWinVisible = function()
    if (unloaded or hudApplying or data == nil or win == nil) then return; end
    local visible = win:IsVisible();
    if (data.winVisible ~= visible) then
        data.winVisible = visible;
        pcall(SaveAll);
    end
end

------------------------------------------------------------------------
-- EVENT HOOKS
--
-- The backpack is shared by all plugins: the previous handler keeps being
-- called, and on unload ours is removed (or, if another plugin chained on
-- top of it, turned into a pass-through).
------------------------------------------------------------------------

local hooks = { };

local function Hook(object, eventName, fn)
    if (object == nil) then return; end
    local h = { object = object, name = eventName, active = true };
    local okPrev, prev = pcall(function() return object[eventName]; end);
    h.prev = okPrev and prev or nil;
    h.wrapper = function(sender, args)
        if (type(h.prev) == "function") then pcall(h.prev, sender, args); end
        if (h.active) then pcall(fn, sender, args); end
    end;
    pcall(function() object[eventName] = h.wrapper; end);
    table.insert(hooks, h);
end

local function UnhookAll()
    for i = #hooks, 1, -1 do
        local h = hooks[i];
        h.active = false;
        pcall(function()
            if (h.object[h.name] == h.wrapper) then h.object[h.name] = h.prev; end
        end);
    end
    hooks = { };
end

------------------------------------------------------------------------
-- INVENTORY COUNTER
--
-- Backpack events only mark the counts dirty; the clock scans the bags
-- (throttled), plus every POLL_INTERVAL seconds because a stack that
-- grows or shrinks in place fires no event. Scans only run while the
-- main window is shown and something is tracked.
------------------------------------------------------------------------

local backpack;            -- acquired lazily
local dirty = true;        -- a scan is needed
local lastScan = -1000;    -- GetGameTime of the last scan

MarkDirty = function()
    dirty = true;
    dragSrc.stale = true;   -- a shown drag source looks its item up again
end

local function AcquireBackpack()
    if (backpack ~= nil) then return backpack; end
    -- GetInstance is a static function (no self)
    local ok, player = pcall(Turbine.Gameplay.LocalPlayer.GetInstance);
    if (not ok) then player = nil; end
    backpack = Call(player, "GetBackpack");
    if (backpack ~= nil) then
        Hook(backpack, "ItemAdded",   MarkDirty);
        Hook(backpack, "ItemRemoved", MarkDirty);
        Hook(backpack, "ItemMoved",   MarkDirty);
        Hook(backpack, "SizeChanged", MarkDirty);
    end
    return backpack;
end

-- Stack size of an item (Item:GetQuantity is dump-only); 1 if unknown.
local function ReadQuantity(item)
    local q = WholeNumber(Call(item, "GetQuantity"));
    if (q == nil or q < 1) then q = 1; end
    return q;
end

-- Cleaned name of an item ("" if unreadable) and its ItemInfo.
local function ReadItemName(item)
    local info = Call(item, "GetItemInfo");
    local name = CleanGameText(Call(info, "GetName"));
    if (name == "") then name = CleanGameText(Call(item, "GetName")); end
    return name, info;
end

-- Icon layer image IDs of an ItemInfo (or Item); 0 / nil are skipped.
local function ReadImages(obj)
    local images = { };
    for k, getter in ipairs(IMAGE_GETTERS) do
        local id = WholeNumber(Call(obj, getter));
        if (id ~= nil and id ~= 0) then images[k] = id; end
    end
    return images;
end

local function HasImages(images)
    for k = 1, #IMAGE_GETTERS do
        if (images[k] ~= nil) then return true; end
    end
    return false;
end

-- Refreshes the saved look (images, quality) of a slot from a live item.
-- Returns true if anything changed.
local function UpdateLook(t, info)
    local changed = false;
    local images = ReadImages(info);
    if (HasImages(images)) then
        for k = 1, #IMAGE_GETTERS do
            if (t.images[k] ~= images[k]) then changed = true; end
        end
        t.images = images;
    end
    local quality = WholeNumber(Call(info, "GetQuality"));
    if (quality ~= nil and quality ~= t.quality) then
        t.quality = quality;
        changed = true;
    end
    return changed;
end

local function ScanBackpack()
    local want, any = { }, false;
    for i = 1, MAX_SLOTS do
        local t = trackedSlots[i];
        if (t ~= nil) then want[t.name] = 0; any = true; end
    end
    if (not any) then return; end

    local bp = AcquireBackpack();
    if (bp == nil) then return; end   -- counts stay "?" until it is there

    local matchInfo = { };
    local size = Clamp(WholeNumber(Call(bp, "GetSize")) or 0, 0, 1000);
    for i = 1, size do
        local item = Call(bp, "GetItem", i);
        if (item ~= nil) then
            local name, info = ReadItemName(item);
            if (want[name] ~= nil) then
                want[name] = want[name] + ReadQuantity(item);
                if (matchInfo[name] == nil) then matchInfo[name] = info or item; end
            end
        end
    end

    -- only slots whose count or look changed are repainted (the poll runs
    -- every 2 s and usually changes nothing)
    local anyChanged = false;
    for i = 1, MAX_SLOTS do
        local t = trackedSlots[i];
        if (t ~= nil) then
            local changed = (t.count ~= want[t.name]);
            t.count = want[t.name];
            local info = matchInfo[t.name];
            if (info ~= nil and UpdateLook(t, info)) then
                saveDirty = true;
                changed = true;
            end
            if (changed) then
                anyChanged = true;
                if (i <= settings.slotCount) then PaintSlot(i); end
            end
        end
    end
    if (anyChanged) then RefreshNameLine(); end
end

------------------------------------------------------------------------
-- USER INTERFACE
--
-- "win", "slotMenu", "optionsPanel", "iconWin", "iconMenu" and
-- "tickControl" are GLOBALS on purpose: LOTRO garbage-collects any
-- control whose last Lua reference is a local that goes out of scope
-- when the script finishes loading. The slot controls, the "[-] N slots
-- [+]" row and the target editor are children of "win" and live as long
-- as it does.
--
-- A slot is a plain Control with SetAllowDrop(true) - no Quickslot and
-- no ItemControl, which would use or move the item on a click / drag.
-- Only while Ctrl is held a native ItemControl ("dragItemControl", a
-- GLOBAL) is shown over the hovered slot's icon (DRAG SOURCE).
------------------------------------------------------------------------

slotMenu = nil;            -- GLOBAL, shared by all slots
dragItemControl = nil;     -- GLOBAL, the Ctrl+drag source (DRAG SOURCE)
local slots = { };         -- UI of slot i: { back, inner, layers, plus, dim, bar, count }
local nameLabel;
local stepper = { };       -- slot count row: { minus, value, plus }
-- target editor state (TARGET COUNT): prompt = label left of the editor,
-- box = the TextBox while open, slot = slot being edited, openedAt =
-- GetGameTime when it opened, pending / pendingAt = slot waiting to be
-- opened in the next frame, refocus = give the focus back next frame
local edit = { };
-- slots the UI points at: hover = under the mouse, pinned = last
-- left-clicked tracked slot, menu = the slot menu was opened for it
local sel = { };
local slotMenuItems = { };
-- drop state (DRAG & DROP): lastSlotAt = GetGameTime of the last drop a
-- slot handled, pending = window drop waiting one frame
local dropState = { };

PaintSlot = function(i)
    local s = slots[i];
    if (s == nil) then return; end
    -- gold border: the slot whose target is being edited
    s.back:SetBackColor((edit.slot == i) and COL_GOLD or COL_SLOT_BORDER);
    local t = trackedSlots[i];
    if (t == nil) then
        for k = 1, #s.layers do s.layers[k]:SetVisible(false); end
        s.dim:SetVisible(false);
        s.bar:SetVisible(false);
        s.plus:SetVisible(true);
        s.count:SetText("");
        -- craft pick mode (AUTO TARGETS): highlight the empty slots
        if (ITR.Tracker ~= nil and ITR.Tracker.PickPaint ~= nil) then ITR.Tracker.PickPaint(i); end
        return;
    end

    s.plus:SetVisible(false);
    local zero = (t.count == 0);
    for k = 1, #s.layers do
        local layer = s.layers[k];
        local id = t.images[k];
        if (id ~= nil and layer.imageId ~= id) then
            layer.imageId = id;
            layer.imageOk = pcall(layer.SetBackground, layer, id);
        end
        layer:SetVisible(id ~= nil and layer.imageOk == true);
    end
    -- used up: a dark translucent box over the icon (the docs say only
    -- windows honour SetOpacity, so child controls are not faded)
    s.dim:SetVisible(zero);
    s.count:SetText(FormatCount(t.count));

    -- with a target: count and progress bar in the red -> green gradient
    local fraction = TargetFraction(t);
    local barW = 0;
    if (fraction ~= nil) then
        local colour = TargetColour(fraction);
        s.count:SetForeColor(colour);
        barW = math.floor(fraction * (SLOT_SIZE - 2));
        if (barW > 0) then
            s.bar:SetWidth(barW);
            s.bar:SetBackColor(colour);
        end
    elseif (t.target ~= nil) then
        s.count:SetForeColor(COL_COUNT);   -- count unknown ("?")
    else
        s.count:SetForeColor(zero and COL_COUNT_ZERO or COL_COUNT);
    end
    s.bar:SetVisible(barW > 0);
    -- craft pick mode (AUTO TARGETS): empty slots are highlighted; a
    -- slot that just got an assignment is painted normally
    if (ITR.Tracker ~= nil and ITR.Tracker.PickPaint ~= nil) then ITR.Tracker.PickPaint(i); end
end

PaintSlots = function()
    for i = 1, settings.slotCount do PaintSlot(i); end
end

-- "<count>" or "<count> / <target>" ("?" while the count is unknown).
local function CountText(t)
    local text = (t.count ~= nil) and tostring(t.count) or "?";
    if (t.target ~= nil) then text = text .. " / " .. tostring(t.target); end
    return text;
end

-- "<name>: <count> in bags" ("<name>: <count> / <target> in bags") in at
-- most maxBytes: first " in bags" is dropped, then the compact
-- ": <count>/<target>" is used, and only then the name is shortened; if
-- not even one character of the name fits, only the count is shown.
local function SlotLine(i, maxBytes)
    local t = trackedSlots[i];
    if (t.count == nil and t.target == nil) then return Shorten(t.name, maxBytes); end
    local count = (t.count ~= nil) and tostring(t.count) or "?";
    local suffixes;
    if (t.target ~= nil) then
        suffixes = { ": " .. count .. " / " .. t.target .. " in bags", ": " .. count .. " / " .. t.target,
            ": " .. count .. "/" .. t.target };
    else
        suffixes = { ": " .. count .. " in bags", ": " .. count };
    end
    for _, suffix in ipairs(suffixes) do
        if (string.len(t.name) + string.len(suffix) <= maxBytes) then return t.name .. suffix; end
    end
    local suffix = suffixes[#suffixes];
    local name = Shorten(t.name, maxBytes - string.len(suffix));
    if (name == "") then return string.sub(suffix, 3); end
    return name .. suffix;
end

RefreshNameLine = function()
    if (nameLabel == nil) then return; end
    -- craft pick mode (AUTO TARGETS): the line shows what is assigned next
    if (ITR.Tracker ~= nil and ITR.Tracker.PickLine ~= nil) then
        local pt1, pt2, ptColour = ITR.Tracker.PickLine();
        if (pt1 ~= nil) then
            local maxBytes = math.floor(nameLabel:GetWidth() / NAME_CHAR_W);
            nameLabel:SetForeColor(ptColour or COLOR_HINT);
            nameLabel:SetText(FitText(pt1, pt2 or pt1, maxBytes));
            return;
        end
    end
    local maxBytes = math.floor(nameLabel:GetWidth() / NAME_CHAR_W);
    local text, colour = nil, COLOR_HINT;
    local shown = sel.hover;
    if (shown == nil and sel.pinned ~= nil and trackedSlots[sel.pinned] ~= nil) then
        shown = sel.pinned;
    end
    if (shown ~= nil and trackedSlots[shown] ~= nil) then
        local t = trackedSlots[shown];
        text = SlotLine(shown, maxBytes);
        -- hovered and in the bags: mention Ctrl+drag, only if it fits
        if (shown == sel.hover and dragItemControl ~= nil and t.count ~= nil and t.count > 0
            and string.len(text) + string.len(CTRL_DRAG_HINT) <= maxBytes) then
            text = text .. CTRL_DRAG_HINT;
        end
        colour = QUALITY_COLOR[t.quality or -1] or COLOR_TEXT;
    elseif (shown ~= nil) then
        text = FitText("Drag an item from your bags here", "Drop an item here", maxBytes);
    elseif (not HasTracked()) then
        text = FitText("Drag items from your bags onto a slot", "Drag items here", maxBytes);
    else
        text = FitText("Hover a slot to see the item", "Hover a slot", maxBytes);
    end
    nameLabel:SetForeColor(colour);
    nameLabel:SetText(text);
end

--[[
    TARGET COUNT

    trackedSlots[i].target is a whole number 1..MAX_TARGET or nil. It is
    set with an inline TextBox at the right end of the name line (like
    InstanceLockTimer's rename editor), opened by a double-click on a
    tracked slot or by "Set target..." in the slot menu, or with
    /itr target. The prompt left of it names the item, and the slot gets
    a gold border while it is edited. Only one editor exists at a time.

    Opening (unverified in game, so defensive): the editor is opened one
    frame after the click (RequestTargetEdit -> MASTER CLOCK), when the
    context menu has closed; the window is activated before the TextBox
    gets the focus, and a FocusLost within EDIT_GRACE seconds after
    opening gives the focus back in the next frame instead of committing.

    Closing:
    * Enter: a valid number is applied and the editor closes; invalid
      text keeps it open with a red "Number?" prompt and a chat hint.
    * Escape: closes, nothing changes.
    * FocusLost (after the grace time), opening the editor for another
      slot, a layout change ("-" / "+", slot count, slots per row):
      valid text is committed, invalid text is discarded with a hint.
    * Clearing / replacing the slot, a drop, hiding the window (also the
      HUD toggle), /itr target for that slot and unload: discarded.
]]

-- Sets (n) or removes (nil) the target of slot i; false if refused or
-- if i is empty. A target set by hand makes the slot manual (AUTO
-- TARGETS). While the pick mode is on, a picked slot is owned by it
-- (PickOwnsSlot): re-targeting it would desync the pick - refused.
local function SetTarget(i, n)
    local t = trackedSlots[i];
    if (t == nil) then return false; end
    if (ITR.Tracker.pick ~= nil and ITR.Tracker.PickOwnsSlot(i)) then
        Hint("the craft calculator picked this slot - stop the picking first (Escape).");
        return false;
    end
    t.autoTarget = nil;
    t.autoSlot = nil;
    t.target = n;
    PaintSlot(i);
    RefreshNameLine();
    pcall(SaveAll);
    return true;
end

-- Typed editor text -> target (see ParseTargetText). Returns false, with
-- a chat hint, if the text is not valid; the target is then unchanged.
local function ApplyTargetText(i, text)
    local valid, n = ParseTargetText(text);
    if (not valid) then
        Hint("the target must be a whole number like 1000 or 1,000 (0 or empty removes it).");
        return false;
    end
    SetTarget(i, n);
    return true;
end

-- Activates the main window and focuses the open editor.
local function FocusTargetEditor()
    local editor = edit.box;
    if (editor == nil) then return; end
    Call(win, "Activate");
    pcall(editor.Focus, editor);
end

-- Closes the target editor (and drops a pending open request). "commit":
-- valid text is applied, invalid text discarded with a hint.
local function CloseTargetEditor(commit)
    edit.pending = nil;
    edit.refocus = false;
    local editor = edit.box;
    if (editor == nil) then return; end
    local i = edit.slot;
    edit.box = nil;
    edit.slot = nil;
    if (commit and i ~= nil) then ApplyTargetText(i, editor:GetText()); end
    -- detaching the editor fires FocusLost; edit.box is already nil, so
    -- that is a no-op instead of a double commit
    editor:SetParent(nil);
    edit.prompt:SetVisible(false);
    nameLabel:SetVisible(true);
    if (i ~= nil) then PaintSlot(i); end   -- border back to normal
    RefreshNameLine();
end

-- "Target for <name>:", or the shortened "<name>:", in maxBytes.
local function TargetPromptText(name, maxBytes)
    local text = "Target for " .. name .. ":";
    if (string.len(text) <= maxBytes) then return text; end
    local short = Shorten(name, maxBytes - 12);
    if (string.len(short) >= 7) then return "Target for " .. short .. ":"; end
    short = Shorten(name, maxBytes - 1);
    if (short == "") then return "Target:"; end
    return short .. ":";
end

-- Opens the target editor for tracked slot i at the right end of the
-- name line (call through RequestTargetEdit from mouse / menu clicks).
-- During the pick mode the editor stays closed (AUTO TARGETS): the pick
-- owns the slots and Escape should always stop the picking, not commit
-- a typed target.
local function BeginTargetEdit(i)
    local t = trackedSlots[i];
    if (t == nil or i > settings.slotCount or unloaded or hudHidden or not win:IsVisible()) then return; end
    if (ITR.Tracker.pick ~= nil) then
        Hint("the target editor is closed while the craft picking is on (Escape stops it).");
        return;
    end
    if (edit.box ~= nil) then
        if (edit.slot == i) then FocusTargetEditor(); return; end
        CloseTargetEditor(true);   -- switching slots keeps valid typed text
    end
    dragSrc.Hide("target editor");
    sel.pinned = i;

    local x, y, w = nameLabel:GetLeft(), nameLabel:GetTop(), nameLabel:GetWidth();
    local promptW = math.max(0, w - EDIT_W - 4);
    nameLabel:SetVisible(false);
    edit.prompt:SetPosition(x, y);
    edit.prompt:SetSize(promptW, NAME_H);
    edit.prompt:SetForeColor(COLOR_TEXT);
    edit.prompt:SetText(TargetPromptText(t.name, math.floor(promptW / NAME_CHAR_W)));
    edit.prompt:SetVisible(true);

    local editor = Turbine.UI.Lotro.TextBox();
    editor:SetParent(win);
    editor:SetPosition(x + w - EDIT_W, y - 1);
    editor:SetSize(EDIT_W, NAME_H + 2);
    editor:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    editor:SetForeColor(Turbine.UI.Color(1, 1, 1));
    editor:SetBackColor(Turbine.UI.Color(0.05, 0.05, 0.05));
    editor:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    editor:SetMultiline(false);
    editor:SetText(t.target ~= nil and tostring(t.target) or "");
    editor.KeyDown = function(sender, args)
        if (edit.box ~= editor) then return; end
        if (args.Action == ACTION_ENTER) then
            if (ApplyTargetText(i, editor:GetText())) then
                CloseTargetEditor(false);
            else
                edit.prompt:SetForeColor(COL_COUNT_ZERO);
                edit.prompt:SetText("Number?");
            end
        elseif (args.Action == ACTION_ESCAPE) then
            CloseTargetEditor(false);
        end
    end
    -- clicking anywhere outside the editor commits; right after opening
    -- (menu closing, window activation) the focus is taken back instead
    editor.FocusLost = function()
        if (edit.box ~= editor) then return; end
        if (Turbine.Engine.GetGameTime() - edit.openedAt < EDIT_GRACE) then
            edit.refocus = true;
            return;
        end
        CloseTargetEditor(true);
    end
    edit.box = editor;
    edit.slot = i;
    edit.openedAt = Turbine.Engine.GetGameTime();
    PaintSlot(i);
    FocusTargetEditor();
    Call(editor, "SelectAll");   -- typing replaces a prefilled target
end

-- Asks for the target editor of slot i; it opens in the next frame
-- (ProcessTargetEdit, called by the MASTER CLOCK).
local function RequestTargetEdit(i)
    if (trackedSlots[i] == nil or i > settings.slotCount) then return; end
    edit.pending = i;
    edit.pendingAt = Turbine.Engine.GetGameTime();
end

-- MASTER CLOCK: opens a requested editor once a later frame has started,
-- and gives the focus back to the editor after an early FocusLost.
local function ProcessTargetEdit(now)
    if (edit.pending ~= nil and now > edit.pendingAt) then
        local i = edit.pending;
        edit.pending = nil;
        BeginTargetEdit(i);
    end
    if (edit.refocus) then
        edit.refocus = false;
        FocusTargetEditor();
    end
end

-- Clears tracked slot i; false if refused. During the pick mode a picked
-- slot is owned by it (PickOwnsSlot): clearing it would desync the pick
-- - refused (the command handler reports the refusal, not "cleared").
local function ClearSlot(i)
    if (ITR.Tracker.pick ~= nil and ITR.Tracker.PickOwnsSlot(i)) then
        Hint("the craft calculator picked this slot - stop the picking first (Escape).");
        return false;
    end
    if (edit.slot == i) then CloseTargetEditor(false); end
    if (dragSrc.slot == i) then dragSrc.Hide("slot cleared"); end
    trackedSlots[i] = nil;
    if (sel.pinned == i) then sel.pinned = nil; end
    PaintSlot(i);
    RefreshNameLine();
    pcall(SaveAll);
    return true;
end

-- Clears every slot; false if refused. During the pick mode refused: the
-- picked slots belong to it (the slot menu entry and /itr clear all come
-- through here).
local function ClearAllSlots()
    if (ITR.Tracker.pick ~= nil) then
        Hint("the craft picking is on - stop it first (Escape), then clear the slots.");
        return false;
    end
    CloseTargetEditor(false);
    dragSrc.Hide("slots cleared");
    for i = 1, MAX_SLOTS do trackedSlots[i] = nil; end
    sel.pinned = nil;
    PaintSlots();
    RefreshNameLine();
    pcall(SaveAll);
    return true;
end

--[[
    AUTO TARGETS (craft calculator, CraftingWindow.lua)

    The calculator turns the ingredients of a recipe into targets in a
    PICK MODE. "Apply to tracker" first clears ALL previous auto targets
    (auto slots are emptied, auto targets on other slots are cleared -
    this is not undone, not even when the picking is stopped). The main
    window then highlights its empty slots: a left click on an EMPTY
    slot assigns the next pending ingredient (a fresh auto slot with
    the item's look and its target), a click on a slot the calculator
    assigned in this session takes that ingredient back (it is pending
    again), and any other non-empty slot is rejected with a hint: an
    assignment never merges into a slot that already tracks an item.
    The calculator's Apply button turns into "Done: N of M" and
    confirms the assigned slots (a partial assignment is fine);
    "Stop picking" or Escape in the main window finalizes nothing
    (Escape needs no focus: SetWantsKeyEvents delivers the game
    actions to the window globally, like the screen icon's HUD
    toggle). While the picking is on, the picked slots are protected:
    clearing, re-targeting or re-dropping a picked slot is refused
    with a chat hint (ClearSlot / ClearAllSlots / SetTarget /
    HandleDrop / ClearAutoTargets / BeginTargetEdit / BeginPick all
    check the pick state), and the target editor stays closed. The
    pick verifies its assignments by slot NAME, not by the tags:
    a slot emptied or replaced outside the pick state is un-assigned
    (the ingredient is pending again, the counters stay honest).
    The number of slots is never changed by the calculator: if there
    are fewer empty visible slots than ingredients, its status line
    says how many more are needed and that the "+" button adds slots.
    The slots carry two tags: autoTarget = the target was set by the
    calculator, autoSlot = the calculator created the slot (the slot
    was empty when it got the assignment). A slot without tags is
    manual: a target set by hand (editor, slot menu, /itr target) or a
    new drop clears both tags, and the calculator never touches a
    manual target. All functions are fields of ITR.Tracker (no new
    top-level locals in this file).
]]
ITR.Tracker = { };
ITR.Tracker.pick = nil;      -- active pick mode (see BeginPick), nil otherwise
ITR.Tracker.pickWin = nil;   -- the main window (AttachPickKeys): Escape stops

-- Removes every auto target: auto slots are emptied, auto targets on
-- other slots are cleared (manual slots and targets are never touched).
-- During the pick mode refused (the picked slots belong to it; the
-- calculator's button is "Stop picking" by then). Returns the number of
-- slots that were changed (0 when refused).
ITR.Tracker.ClearAutoTargets = function()
    if (ITR.Tracker.pick ~= nil) then
        Hint("the craft picking is on - stop it first (Escape), then clear the auto targets.");
        return 0;
    end
    CloseTargetEditor(true);
    dragSrc.Hide("craft targets");
    local n = 0;
    for i = 1, MAX_SLOTS do
        local t = trackedSlots[i];
        if (t ~= nil and t.autoTarget) then
            if (t.autoSlot) then
                trackedSlots[i] = nil;
                if (sel.pinned == i) then sel.pinned = nil; end
            else
                t.target = nil;
                t.autoTarget = nil;
            end
            n = n + 1;
        end
    end
    if (n > 0) then
        MarkDirty();
        PaintSlots();
        RefreshNameLine();
        pcall(SaveAll);
    end
    return n;
end

-- Live XP updates (the applied session): strictly by name, only the
-- targets of existing auto slots change - never creates, moves or
-- removes slots. Returns whether anything changed.
ITR.Tracker.UpdateAutoTargets = function(list)
    if (type(list) ~= "table") then list = { }; end
    local want = { };
    for _, e in ipairs(list) do want[e.name] = e; end
    local changed = false;
    for i = 1, MAX_SLOTS do
        local t = trackedSlots[i];
        if (t ~= nil and t.autoTarget and want[t.name] ~= nil) then
            local n = ReadTarget(want[t.name].qty);
            if (n ~= nil and n ~= t.target) then
                t.target = n;
                changed = true;
                if (i <= settings.slotCount) then PaintSlot(i); end
            end
        end
    end
    if (changed) then
        RefreshNameLine();
        pcall(SaveAll);
    end
    return changed;
end

-- Starts the pick mode for "list" ({ { name, qty, info } ... }, the
-- grouped BuildTargets ingredients): first the old auto targets are
-- cleared (not restored later), then every ingredient waits for an
-- empty slot the user picks by clicking. Returns the number of auto
-- slots / targets that were cleared and the number of ingredients.
ITR.Tracker.BeginPick = function(list)
    if (type(list) ~= "table") then list = { }; end
    -- only one pick at a time (a caller during a pick would silently
    -- rebuild the state); the calculator's Apply confirms instead
    if (ITR.Tracker.pick ~= nil) then
        Hint("the craft picking is already on - done or stop it first.");
        return 0, 0;
    end
    local cleared = ITR.Tracker.ClearAutoTargets();
    CloseTargetEditor(false);
    dragSrc.Hide("pick slots");
    local pending = { };
    for _, e in ipairs(list) do
        -- an ingredient that is tracked already (a manual slot kept it)
        -- cannot be picked at all - names are unique per slot
        if (type(e) == "table" and type(e.name) == "string" and ITR.Tracker.GetNameState(e.name) == nil) then
            table.insert(pending, e);
        end
    end
    local p = { pending = pending, assigned = { }, denied = 0 };
    ITR.Tracker.pick = p;
    -- Escape in the main window stops the picking ("Stop picking" in
    -- the calculator is the same); the window is handed over by
    -- AttachPickKeys (EXPORTS), this section has no access to it
    local w = ITR.Tracker.pickWin;
    if (w ~= nil) then
        pcall(w.SetWantsKeyEvents, w, true);
        -- the previous KeyDown is chained (EVENT HOOKS convention), not
        -- replaced: a future main-window key handler keeps working during
        -- the pick and is back when the pick ends
        p.prevKeyDown = (type(w.KeyDown) == "function") and w.KeyDown or nil;
        w.KeyDown = function(sender, args)
            if (type(p.prevKeyDown) == "function") then pcall(p.prevKeyDown, sender, args); end
            if (args ~= nil and args.Action == ACTION_ESCAPE) then
                ITR.Tracker.PickEscape();
            end
        end
    end
    MarkDirty();
    PaintSlots();
    RefreshNameLine();
    pcall(SaveAll);
    if (type(ITR.Tracker.OnPickChange) == "function") then ITR.Tracker.OnPickChange(); end
    return cleared, #pending;
end

-- Does the active pick own slot i? The ownership is the slot NAME (the
-- assigned entry's name must still be in the slot), not the tags: a tag
-- stripped by hand cannot make a picked item vanish or stay behind.
ITR.Tracker.PickOwnsSlot = function(i)
    local p = ITR.Tracker.pick;
    if (p == nil) then return false; end
    local e = p.assigned[i];
    local t = trackedSlots[i];
    return (e ~= nil and t ~= nil and t.name == e.name);
end

-- Hands slot i's pick assignment back to the pending queue (in front).
-- Used when the slot was emptied / replaced outside the pick state: the
-- ingredient is offered again instead of being silently lost, and the
-- "Done: N of M" count stays in sync. Returns whether it released.
ITR.Tracker.PickRelease = function(i)
    local p = ITR.Tracker.pick;
    if (p == nil or p.assigned[i] == nil) then return false; end
    table.insert(p.pending, 1, p.assigned[i]);
    p.assigned[i] = nil;
    return true;
end

-- Ends the pick mode. keep = true (confirm, or the plugin is unloaded)
-- keeps the assigned slots: they are normal auto slots by now. keep =
-- false (Stop picking / Escape) undoes them - by NAME: a picked slot
-- whose tags were stripped by hand is emptied / cleared too, so nothing
-- of the pick is left in the slots. Returns
-- { assigned, total, denied, entries = { { name, slot, target } } } -
-- the entries describe what was kept ("total" = pending + assigned:
-- ingredients skipped while picking no longer count).
ITR.Tracker.EndPick = function(keep)
    local p = ITR.Tracker.pick;
    if (p == nil) then
        return { assigned = 0, total = 0, denied = 0, entries = { } };
    end
    ITR.Tracker.pick = nil;
    local w = ITR.Tracker.pickWin;
    if (w ~= nil) then
        pcall(w.SetWantsKeyEvents, w, false);
        w.KeyDown = p.prevKeyDown;   -- the previous handler, nil if there was none
    end
    local report = { assigned = 0, total = 0, denied = p.denied, entries = { } };
    -- ownership by name first: an entry whose slot no longer holds the
    -- item goes back to the pending queue and counts as never assigned
    local owned = { };
    for i in pairs(p.assigned) do
        local t = trackedSlots[i];
        if (t ~= nil and t.name == p.assigned[i].name) then
            owned[i] = p.assigned[i];
        else
            table.insert(p.pending, 1, p.assigned[i]);
        end
    end
    local order = { };
    for i in pairs(owned) do table.insert(order, i); end
    table.sort(order);
    for _, i in ipairs(order) do
        local e = owned[i];
        local t = trackedSlots[i];
        if (not keep) then
            -- nothing is finalized: the assignment is undone the same way
            -- ClearAutoTargets does it (an auto slot is emptied, an auto
            -- target on a kept slot is stripped)
            if (t.autoSlot) then
                trackedSlots[i] = nil;
                if (sel.pinned == i) then sel.pinned = nil; end
            else
                t.target = nil;
                t.autoTarget = nil;
            end
        else
            table.insert(report.entries, { name = e.name, slot = i, target = t.target });
            report.assigned = report.assigned + 1;
        end
        -- a slot emptied by hand in the meantime simply counts as
        -- never assigned
    end
    report.total = #p.pending + report.assigned;
    MarkDirty();
    PaintSlots();
    RefreshNameLine();
    pcall(SaveAll);
    if (type(ITR.Tracker.OnPickChange) == "function") then ITR.Tracker.OnPickChange(); end
    return report;
end

ITR.Tracker.FinishPick = function()
    return ITR.Tracker.EndPick(true);
end

ITR.Tracker.CancelPick = function()
    return ITR.Tracker.EndPick(false);
end

ITR.Tracker.PickEscape = function()
    return ITR.Tracker.EndPick(false);
end

-- Unload: what was assigned stays (it is a normal auto slot by now,
-- SaveAll keeps it); the pick mode itself is dropped.
ITR.Tracker.Unload = function()
    return ITR.Tracker.EndPick(true);
end

-- A left click on slot i while picking: an EMPTY slot gets the next
-- pending ingredient, a picked slot that is still owned (by name) gives
-- its ingredient back (it is pending again, in front), and every other
-- non-empty slot is rejected (an assignment never merges into a tracked
-- item). A stale assignment - the slot was emptied or replaced by hand
-- through a path the pick state could not see - is released to the
-- queue first, so it is never lost and never overwritten silently.
-- Returns whether the click was handled.
ITR.Tracker.SlotClick = function(i)
    local p = ITR.Tracker.pick;
    if (p == nil) then return false; end
    local t = trackedSlots[i];
    if (t == nil) then
        if (p.assigned[i] ~= nil) then ITR.Tracker.PickRelease(i); end
        local e = p.pending[1];
        if (e == nil) then return true; end              -- all assigned
        if (ITR.Tracker.GetNameState(e.name) ~= nil) then
            -- the item became tracked elsewhere while picking (a manual
            -- slot): skip it, otherwise it would block the rest forever
            p.denied = p.denied + 1;
            table.remove(p.pending, 1);
            Hint(e.name .. " is tracked already - it cannot be assigned again.");
            if (type(ITR.Tracker.OnPickChange) == "function") then ITR.Tracker.OnPickChange(); end
            return true;
        end
        trackedSlots[i] = { name = e.name, images = ReadImages(e.info),
            quality = WholeNumber(Call(e.info, "GetQuality")), target = ReadTarget(e.qty),
            autoTarget = true, autoSlot = true };
        table.remove(p.pending, 1);
        p.assigned[i] = e;
        PaintSlot(i);
        RefreshNameLine();
        pcall(SaveAll);
        if (type(ITR.Tracker.OnPickChange) == "function") then ITR.Tracker.OnPickChange(); end
        return true;
    end
    if (p.assigned[i] ~= nil and t.name == p.assigned[i].name) then
        -- take this session's assignment back: the ingredient is
        -- pending again (in front, so the next click re-assigns it)
        trackedSlots[i] = nil;
        table.insert(p.pending, 1, p.assigned[i]);
        p.assigned[i] = nil;
        if (sel.pinned == i) then sel.pinned = nil; end
        if (edit.slot == i) then CloseTargetEditor(false); end
        PaintSlot(i);
        RefreshNameLine();
        pcall(SaveAll);
        if (type(ITR.Tracker.OnPickChange) == "function") then ITR.Tracker.OnPickChange(); end
        return true;
    end
    if (p.assigned[i] ~= nil) then
        ITR.Tracker.PickRelease(i);   -- stale foreign slot: pending again
    end
    p.denied = p.denied + 1;
    Hint("Slot " .. i .. " already tracks an item - only empty slots can be picked.");
    return true;
end

-- The pick mode's state (nil otherwise) - the assignments are re-verified
-- by slot NAME first: an entry whose slot no longer holds the item is
-- un-assigned (the ingredient is pending again), so the counters never
-- report a slot that was emptied or replaced by hand. total = pending +
-- assigned is recomputed here (what was skipped meanwhile no longer
-- counts), assigned = the assignments that still sit in their slots,
-- skipped = the ingredients skipped while picking, moreSlots = how many
-- MORE empty visible slots are needed for the rest (no slot is ever
-- added by the plugin itself).
ITR.Tracker.PickInfo = function()
    local p = ITR.Tracker.pick;
    if (p == nil) then return nil; end
    local assigned = 0;
    for i in pairs(p.assigned) do
        local t = trackedSlots[i];
        if (t ~= nil and t.name == p.assigned[i].name) then
            assigned = assigned + 1;
        else
            ITR.Tracker.PickRelease(i);
        end
    end
    local empty = 0;
    for i = 1, settings.slotCount do
        if (trackedSlots[i] == nil) then empty = empty + 1; end
    end
    local more = #p.pending - empty;
    if (more < 0) then more = 0; end
    return { total = #p.pending + assigned, assigned = assigned, pending = #p.pending,
        skipped = p.denied, moreSlots = more };
end

ITR.Tracker.IsPicking = function()
    return ITR.Tracker.pick ~= nil;
end

-- The name line while picking (nil otherwise): the next ingredient and
-- how far the picking is.
ITR.Tracker.PickLine = function()
    local p = ITR.Tracker.pick;
    if (p == nil) then return nil; end
    local info = ITR.Tracker.PickInfo();
    local assigned, total = info.assigned, info.total;
    local e = p.pending[1];
    local count = " (" .. assigned .. " of " .. total .. " set)";
    if (e == nil) then
        return "All " .. total .. " ingredient(s) assigned - click Done in the calculator (Escape stops)",
            count .. " - Done confirms";
    end
    return e.name .. " x" .. tostring(e.qty) .. " - click an empty slot" .. count .. " - Escape stops",
        count .. " - next: " .. e.name;
end

-- Called from PaintSlot: while picking, the empty visible slots get
-- the gold border (a click will assign to them).
ITR.Tracker.PickPaint = function(i)
    local p = ITR.Tracker.pick;
    if (p == nil) then return; end
    if (i > settings.slotCount) then return; end
    local s = slots[i];
    if (s ~= nil and trackedSlots[i] == nil) then s.back:SetBackColor(COL_GOLD); end
end

-- The main window hands itself over (EXPORTS): Escape then stops the
-- picking. Nothing else happens while no pick mode is running.
ITR.Tracker.AttachPickKeys = function(mainWin)
    ITR.Tracker.pickWin = mainWin;
end

ITR.Tracker.HasAutoTargets = function()
    for i = 1, MAX_SLOTS do
        if (trackedSlots[i] ~= nil and trackedSlots[i].autoTarget) then return true; end
    end
    return false;
end

-- state ("manual" | "auto" | "tracked" | nil), slot, target of an item name.
ITR.Tracker.GetNameState = function(name)
    for i = 1, MAX_SLOTS do
        local t = trackedSlots[i];
        if (t ~= nil and t.name == name) then
            if (t.autoTarget) then return "auto", i, t.target; end
            if (t.target ~= nil) then return "manual", i, t.target; end
            return "tracked", i, nil;
        end
    end
    return nil;
end

--[[
    DRAG & DROP

    Every slot and the window accept drops. Whether the client fires
    DragDrop on the slot, on the window or on both, in which order, and in
    which coordinate space the window's X / Y are, is unverified (the
    event dump shows X = 505 on a 500 px wide window). So:
    * a slot's DragDrop is handled at once and always wins;
    * a window DragDrop is only remembered and handled in the next frame
      (MASTER CLOCK), and only if no slot handled a drop in the meantime
      or just before it (DROP_PAIR_TIME);
    * the window fallback finds the slot from win:GetMousePosition()
      (doc: relative to the control), read in the event; X / Y are used
      only when there is no mouse position and they lie inside the window.
    Everything the drop carries is read while the event runs.
]]

local function DebugLine(text)
    if (debugDrops) then Turbine.Shell.WriteLine(PLUGIN_NAME .. " debug: " .. text); end
end

local function EventText(source, args, mx, my)
    return "DragDrop event on " .. source .. " X=" .. tostring(Field(args, "X"))
        .. " Y=" .. tostring(Field(args, "Y")) .. " mouse=" .. tostring(mx) .. "," .. tostring(my);
end

-- Visible slot under a window-relative point, or nil.
local function HitTest(x, y)
    if (type(x) ~= "number" or type(y) ~= "number") then return nil; end
    for i = 1, settings.slotCount do
        local back = slots[i].back;
        local sx, sy = back:GetLeft(), back:GetTop();
        if (x >= sx and x < sx + SLOT_SIZE and y >= sy and y < sy + SLOT_SIZE) then return i; end
    end
    return nil;
end

-- The slot a window drop was meant for (see the section comment), or nil.
local function WindowDropSlot(drop)
    if (type(drop.mouseX) == "number" and type(drop.mouseY) == "number") then
        return HitTest(drop.mouseX, drop.mouseY);
    end
    local x, y = drop.x, drop.y;
    if (type(x) == "number" and type(y) == "number"
        and x >= 0 and y >= 0 and x < win:GetWidth() and y < win:GetHeight()) then
        return HitTest(x, y);
    end
    return nil;
end

-- Everything a drop carries, read while the DragDrop event runs.
local function ReadDrop(args)
    local d = { x = Field(args, "X"), y = Field(args, "Y"), name = "" };
    d.info = Field(args, "DragDropInfo");
    d.sc = Call(d.info, "GetShortcut");
    d.scType = Call(d.sc, "GetType");
    d.scData = Call(d.sc, "GetData");
    local itemType = Field(Field(Turbine.UI.Lotro, "ShortcutType"), "Item");
    d.isItem = (d.sc ~= nil and itemType ~= nil and d.scType == itemType);
    if (d.isItem) then
        d.item = Call(d.sc, "GetItem");
        if (d.item ~= nil) then
            d.name, d.itemInfo = ReadItemName(d.item);
            d.images = ReadImages(d.itemInfo);
            if (not HasImages(d.images)) then d.images = ReadImages(d.item); end
            d.quality = WholeNumber(Call(d.itemInfo, "GetQuality"));
            if (d.quality == nil) then d.quality = WholeNumber(Call(d.item, "GetQuality")); end
        end
    end
    return d;
end

-- A drop on slot "index" (nil: on the window outside any slot). "source"
-- is "slot" or "window" (for /itr debug).
local function HandleDrop(index, d, source)
    DebugLine("drop on " .. tostring(source)
        .. " X=" .. tostring(d.x) .. " Y=" .. tostring(d.y)
        .. " slot=" .. tostring(index) .. " shortcut=" .. tostring(d.sc ~= nil)
        .. " type=" .. tostring(d.scType) .. " data=" .. tostring(d.scData)
        .. " item=" .. tostring(d.item ~= nil) .. " name=" .. d.name);

    if (index == nil) then Hint("drop the item onto a slot."); return; end
    if (index > settings.slotCount) then return; end
    if (d.sc == nil) then Hint("nothing to track."); return; end
    if (not d.isItem) then
        Hint("only items can be tracked (not skills, aliases, emotes ...).");
        return;
    end
    if (d.item == nil) then Hint("could not read that item."); return; end
    if (d.name == "") then Hint("this item has no readable name and cannot be tracked."); return; end

    -- while picking, a drop must not disturb a picked slot: the picked
    -- slot itself is guarded, and so is moving the item that some other
    -- picked slot tracks (the move below would empty it). A drop on a
    -- slot with an unrelated item stays allowed.
    if (ITR.Tracker.pick ~= nil) then
        if (ITR.Tracker.PickOwnsSlot(index)) then
            Hint("the craft calculator picked this slot - stop the picking first (Escape).");
            return;
        end
        for j = 1, MAX_SLOTS do
            if (j ~= index and ITR.Tracker.PickOwnsSlot(j) and trackedSlots[j].name == d.name) then
                Hint(d.name .. " is picked by the craft calculator - stop the picking first (Escape).");
                return;
            end
        end
    end

    CloseTargetEditor(false);
    dragSrc.Hide("drop");

    -- the target stays with the item: kept when the same item is dropped
    -- again or moved here, reset when a different item replaces it
    local target;
    if (trackedSlots[index] ~= nil and trackedSlots[index].name == d.name) then
        target = trackedSlots[index].target;
    end
    -- the same item tracked in another slot moves here
    for j = 1, MAX_SLOTS do
        if (j ~= index and trackedSlots[j] ~= nil and trackedSlots[j].name == d.name) then
            if (target == nil) then target = trackedSlots[j].target; end
            trackedSlots[j] = nil;
            if (sel.pinned == j) then sel.pinned = nil; end
            PaintSlot(j);
        end
    end

    local t = { name = d.name, images = d.images, quality = d.quality, scType = WholeNumber(d.scType),
        target = target };
    if (type(d.scData) == "string" or type(d.scData) == "number") then t.scData = tostring(d.scData); end
    trackedSlots[index] = t;

    if (DROP_SET_SUCCESSFUL) then Call(d.info, "SetSuccessful", true); end

    MarkDirty();
    pcall(ScanBackpack);
    PaintSlot(index);
    RefreshNameLine();
    pcall(SaveAll);
end

-- HandleDrop in pcall; in debug mode an error is printed, not swallowed.
local function RunDrop(index, drop, source)
    local ok, err = pcall(HandleDrop, index, drop, source);
    if (not ok) then DebugLine("drop error: " .. tostring(err)); end
end

-- DragDrop on slot i.
local function OnSlotDrop(i, sender, args)
    local now = Turbine.Engine.GetGameTime();
    local text = EventText("slot " .. i, args, Call(sender, "GetMousePosition"));
    if (dropState.lastSlotAt == now) then
        DebugLine(text .. " (duplicate, ignored)");
        return;
    end
    dropState.lastSlotAt = now;
    DebugLine(text);
    local ok, drop = pcall(ReadDrop, args);
    if (not ok) then DebugLine("drop error: " .. tostring(drop)); return; end
    RunDrop(i, drop, "slot");
    if (dragSrc.dragging) then dragSrc.Hide("drop"); end
end

-- DragDrop on the window: remembered for the next frame.
local function OnWindowDrop(args)
    local now = Turbine.Engine.GetGameTime();
    local mx, my = Call(win, "GetMousePosition");
    local text = EventText("window", args, mx, my);
    if (dropState.lastSlotAt ~= nil and now - dropState.lastSlotAt <= DROP_PAIR_TIME) then
        DebugLine(text .. " (a slot handled this drop, ignored)");
        return;
    end
    local ok, drop = pcall(ReadDrop, args);
    if (not ok) then DebugLine("drop error: " .. tostring(drop)); return; end
    drop.at, drop.mouseX, drop.mouseY = now, mx, my;
    dropState.pending = drop;
    if (dragSrc.dragging) then dragSrc.Hide("drop"); end
    DebugLine(text .. " (waiting one frame for a slot)");
end

-- Called by the clock every frame: handles a remembered window drop once
-- a later frame has started, unless a slot handled the drop.
local function ProcessWindowDrop(now)
    local drop = dropState.pending;
    if (drop == nil or now <= drop.at) then return; end
    dropState.pending = nil;
    if (dropState.lastSlotAt ~= nil and dropState.lastSlotAt >= drop.at) then
        DebugLine("window drop ignored: a slot handled it");
        return;
    end
    RunDrop(WindowDropSlot(drop), drop, "window");
end

--[[
    DRAG SOURCE (Ctrl+drag)

    A plugin cannot start a drag from a plain Control; only native
    controls carry a real game item. So while Ctrl is held over a tracked
    slot, ONE shared Turbine.UI.Lotro.ItemControl (GLOBAL dragItemControl,
    child of win) is placed over that slot's icon with a live Item from
    the bags; the user drags it like an item from the bags (e.g. into the
    auction search box). It is the real item: a Ctrl+click on it acts
    like a click in the bags (may use the item). Tracking never changes
    by a drag; a drop back on a slot goes through DRAG & DROP.

    * The clock calls dragSrc.Update only while a slot is hovered or the
      control is shown. The bags are searched only when Ctrl goes down
      over a slot (once per slot and Ctrl press) or after a bag event
      while it is shown - never every frame.
    * The control captures the mouse, so the slot may get MouseLeave:
      while it is shown, "inside the slot" comes from the slot's
      GetMousePosition, and that slot's MouseLeave is ignored (checked
      again after hiding, dragSrc.recheck).
    * Hidden when Ctrl is released or the mouse leaves the slot - except
      during a drag (DragStart, args empty in the event dump): then it
      stays until the mouse comes back over the window after leaving it,
      another slot gets MouseEnter, a drop on the window / a slot, or
      DRAG_TIMEOUT seconds. A drag that ends inside the window fires none
      of these, so the mouse over the source slot without Ctrl also ends
      it (after it left the slot, or DRAG_GRACE seconds): the item is
      never left clickable without Ctrl.
    * Also hidden on: HUD hide, window hide, layout change, slot clear /
      replace / any drop, target editor, unload.
]]

-- Mouse inside the visible slot i: true / false, nil if unknown.
dragSrc.Inside = function(i)
    local back = slots[i] and slots[i].back;
    if (back == nil) then return nil; end
    local ok, mx, my = pcall(back.GetMousePosition, back);
    if (not ok or type(mx) ~= "number" or type(my) ~= "number") then return nil; end
    return (back:IsVisible() and mx >= 0 and my >= 0 and mx < SLOT_SIZE and my < SLOT_SIZE);
end

-- Mouse inside the main window: true / false, nil if unknown.
dragSrc.InWindow = function()
    local ok, mx, my = pcall(win.GetMousePosition, win);
    if (not ok or type(mx) ~= "number" or type(my) ~= "number") then return nil; end
    return (mx >= 0 and my >= 0 and mx < win:GetWidth() and my < win:GetHeight());
end

-- Ctrl held (false if unknown). The dump lists IsControlKeyDown as a
-- Control member, the docs show the static form Control.IsControlKeyDown():
-- both are tried once, the one that answers with a boolean is kept.
dragSrc.CtrlDown = function()
    local f = dragSrc.keyFn;
    if (f ~= nil) then
        local ok, v;
        if (dragSrc.keySelf ~= nil) then ok, v = pcall(f, dragSrc.keySelf); else ok, v = pcall(f); end
        return (ok and v == true);
    end
    if (dragSrc.keyFailed) then return false; end
    f = Field(win, "IsControlKeyDown");
    if (type(f) == "function") then
        local ok, v = pcall(f, win);
        if (ok and type(v) == "boolean") then
            dragSrc.keyFn, dragSrc.keySelf = f, win;
            return v;
        end
    end
    f = Field(Field(Turbine.UI, "Control"), "IsControlKeyDown");
    if (type(f) == "function") then
        local ok, v = pcall(f);
        if (ok and type(v) == "boolean") then
            dragSrc.keyFn, dragSrc.keySelf = f, nil;
            return v;
        end
    end
    dragSrc.keyFailed = true;
    DebugLine("IsControlKeyDown does not work: Ctrl+drag is off");
    return false;
end

-- First item in the bags with this (cleaned) name, or nil. Looked up
-- right before showing: Item objects may be stale after bag changes.
dragSrc.FindItem = function(name)
    local bp = AcquireBackpack();
    if (bp == nil) then return nil; end
    local size = Clamp(WholeNumber(Call(bp, "GetSize")) or 0, 0, 1000);
    for k = 1, size do
        local item = Call(bp, "GetItem", k);
        if (item ~= nil and ReadItemName(item) == name) then return item; end
    end
    return nil;
end

dragSrc.Hide = function(reason)
    local i = dragSrc.slot;
    dragSrc.dragging = false;
    dragSrc.leftWin = false;
    dragSrc.leftSlot = false;
    if (i == nil) then return; end
    dragSrc.slot = nil;
    dragSrc.stale = false;
    local ctl = dragItemControl;
    if (ctl ~= nil) then
        pcall(ctl.SetVisible, ctl, false);
        Call(ctl, "SetItem", nil);   -- drop the item reference (if supported)
    end
    if (sel.hover == i) then dragSrc.recheck = i; end
    DebugLine("Ctrl+drag source hidden on slot " .. i .. " (" .. tostring(reason) .. ")");
end

-- Shows the drag source on tracked slot i if the item is in the bags.
dragSrc.Show = function(i)
    local ctl, t = dragItemControl, trackedSlots[i];
    if (ctl == nil or t == nil or t.count == 0) then return; end
    local item = dragSrc.FindItem(t.name);
    if (item == nil) then
        DebugLine("Ctrl over slot " .. i .. ": " .. t.name .. " is not in the bags");
        return;
    end
    if (not pcall(ctl.SetItem, ctl, item)) then
        DebugLine("Ctrl over slot " .. i .. ": SetItem failed");
        return;
    end
    local back = slots[i].back;
    ctl:SetPosition(back:GetLeft() + ICON_INSET, back:GetTop() + ICON_INSET);
    ctl:SetVisible(true);
    dragSrc.slot = i;
    dragSrc.stale = false;
    dragSrc.recheck = nil;
    DebugLine("Ctrl+drag source shown on slot " .. i .. " (" .. t.name .. ")");
end

-- DragStart on the drag source.
dragSrc.Started = function()
    if (dragSrc.slot == nil) then return; end
    dragSrc.dragging = true;
    dragSrc.dragAt = Turbine.Engine.GetGameTime();
    dragSrc.leftWin = false;
    dragSrc.leftSlot = false;
    DebugLine("DragStart on the Ctrl+drag source (slot " .. dragSrc.slot .. ")");
end

-- MouseEnter on slot i: a new hover may look the item up again; during
-- a drag another slot (or the source slot after the mouse left the
-- window) ends it.
dragSrc.SlotEntered = function(i)
    dragSrc.tried = nil;
    if (dragSrc.dragging and (i ~= dragSrc.slot or dragSrc.leftWin)) then
        dragSrc.Hide("drag ended");
    end
end

-- MASTER CLOCK, while a slot is hovered or the drag source is shown.
dragSrc.Update = function(now)
    -- hidden window: a MouseLeave may never come, so the hover is
    -- dropped here (and this stops being called every frame)
    if (not win:IsVisible()) then
        local h = sel.hover;
        sel.hover = nil;
        dragSrc.recheck = nil;
        dragSrc.tried = nil;
        if (dragSrc.slot ~= nil) then dragSrc.Hide("window hidden"); end
        if (h ~= nil and slots[h] ~= nil) then
            slots[h].inner:SetBackColor(COL_SLOT_INNER);
            RefreshNameLine();
        end
        return;
    end

    if (dragSrc.slot ~= nil and dragSrc.dragging) then
        local inWin = dragSrc.InWindow();
        if (inWin == false) then dragSrc.leftWin = true; end
        local inside = dragSrc.Inside(dragSrc.slot);
        if (inside == false) then dragSrc.leftSlot = true; end
        if (now - dragSrc.dragAt >= DRAG_TIMEOUT) then
            dragSrc.Hide("drag timeout");
        elseif ((dragSrc.leftWin and inWin == true)
            or (inside == true and (dragSrc.leftSlot or now - dragSrc.dragAt >= DRAG_GRACE)
                and not dragSrc.CtrlDown())) then
            -- back over the window, or over the item without Ctrl (a drag
            -- that ended inside the window): the rules below apply
            dragSrc.dragging = false;
            dragSrc.leftWin = false;
            dragSrc.leftSlot = false;
            DebugLine("Ctrl+drag: drag over");
        else
            return;
        end
    end

    -- the hovered slot was under the drag source: its MouseLeave may
    -- have gone to the item control
    local r = dragSrc.recheck;
    if (r ~= nil) then
        if (sel.hover ~= r) then
            dragSrc.recheck = nil;
        elseif (dragSrc.Inside(r) == false) then
            dragSrc.recheck = nil;
            sel.hover = nil;
            slots[r].inner:SetBackColor(COL_SLOT_INNER);
            RefreshNameLine();
        end
    end

    if (not dragSrc.CtrlDown()) then
        dragSrc.tried = nil;
        if (dragSrc.slot ~= nil) then dragSrc.Hide("Ctrl released"); end
        return;
    end

    local i = dragSrc.slot;
    if (i ~= nil) then
        local inside = dragSrc.Inside(i);
        if (inside == false or (inside == nil and sel.hover ~= i)) then
            dragSrc.Hide("mouse left the slot");
        elseif (dragSrc.stale) then
            -- bags changed: the item is looked up again and swapped in
            -- place (hiding it would reset a press on it)
            dragSrc.stale = false;
            local t = trackedSlots[i];
            local item = (t ~= nil) and dragSrc.FindItem(t.name) or nil;
            if (item == nil) then
                dragSrc.Hide("not in the bags any more");
            elseif (not pcall(dragItemControl.SetItem, dragItemControl, item)) then
                dragSrc.Hide("SetItem failed");
            else
                DebugLine("Ctrl+drag source on slot " .. i .. ": item looked up again");
            end
            return;
        else
            return;
        end
    end

    local h = sel.hover;
    if (h == nil) then dragSrc.tried = nil; return; end
    if (dragSrc.tried == h) then return; end
    dragSrc.tried = h;
    if (unloaded or hudHidden or edit.box ~= nil or not win:IsVisible() or h > settings.slotCount
        or dragSrc.Inside(h) == false) then
        return;
    end
    dragSrc.Show(h);
end

local function CloseSlotMenu()
    if (slotMenu ~= nil and type(slotMenu.Close) == "function") then
        pcall(slotMenu.Close, slotMenu);
    end
end

local function BuildSlotMenu()
    slotMenu = Turbine.UI.ContextMenu();
    local items = slotMenu:GetItems();

    local function Add(key, text, onClick)
        local mi = Turbine.UI.MenuItem(text);
        mi.Click = function() onClick(); end
        items:Add(mi);
        slotMenuItems[key] = mi;
    end

    -- opened in the next frame, after the menu has closed (TARGET COUNT)
    Add("target", "Set target...", function()
        if (sel.menu ~= nil and trackedSlots[sel.menu] ~= nil) then RequestTargetEdit(sel.menu); end
    end);
    Add("clearTarget", "Clear target", function()
        if (sel.menu ~= nil and trackedSlots[sel.menu] ~= nil) then
            if (edit.slot == sel.menu) then CloseTargetEditor(false); end
            SetTarget(sel.menu, nil);
        end
    end);
    Add("clear", "Clear slot", function()
        if (sel.menu ~= nil and trackedSlots[sel.menu] ~= nil) then ClearSlot(sel.menu); end
    end);
    Add("clearAll", "Clear all slots", ClearAllSlots);
    Add("options", "Options...", function() OpenOptions(); end);
end

local function ShowSlotMenu(i)
    sel.menu = i;
    local t = trackedSlots[i];
    Call(slotMenuItems.target, "SetText", (t ~= nil and t.target ~= nil)
        and ("Set target (" .. t.target .. (t.autoTarget and ", auto" or "") .. ")...") or "Set target...");
    Call(slotMenuItems.target, "SetEnabled", t ~= nil);
    Call(slotMenuItems.clearTarget, "SetEnabled", t ~= nil and t.target ~= nil);
    Call(slotMenuItems.clear, "SetEnabled", t ~= nil);
    slotMenu:ShowMenu();
end

local function CreateSlot(i)
    local s = { layers = { } };

    -- the 1px border is the back colour around the inner box
    s.back = Turbine.UI.Control();
    s.back:SetParent(win);
    s.back:SetSize(SLOT_SIZE, SLOT_SIZE);
    s.back:SetBackColor(COL_SLOT_BORDER);
    s.back:SetMouseVisible(true);
    s.back:SetAllowDrop(true);

    s.inner = Turbine.UI.Control();
    s.inner:SetParent(s.back);
    s.inner:SetPosition(1, 1);
    s.inner:SetSize(SLOT_SIZE - 2, SLOT_SIZE - 2);
    s.inner:SetBackColor(COL_SLOT_INNER);
    s.inner:SetMouseVisible(false);

    for k = 1, #IMAGE_GETTERS do
        local layer = Turbine.UI.Control();
        layer:SetParent(s.back);
        layer:SetPosition(ICON_INSET, ICON_INSET);
        layer:SetSize(SLOT_SIZE - 2 * ICON_INSET, SLOT_SIZE - 2 * ICON_INSET);
        layer:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
        layer:SetMouseVisible(false);
        layer:SetVisible(false);
        s.layers[k] = layer;
    end

    s.plus = Turbine.UI.Label();
    s.plus:SetParent(s.back);
    s.plus:SetPosition(1, 1);
    s.plus:SetSize(SLOT_SIZE - 2, SLOT_SIZE - 2);
    s.plus:SetFont(Turbine.UI.Lotro.Font.TrajanPro20);
    s.plus:SetForeColor(COL_PLUS);
    s.plus:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    s.plus:SetText("+");
    s.plus:SetMouseVisible(false);

    -- darkens the icon of a used-up item (count 0); above the layers
    s.dim = Turbine.UI.Control();
    s.dim:SetParent(s.back);
    s.dim:SetPosition(1, 1);
    s.dim:SetSize(SLOT_SIZE - 2, SLOT_SIZE - 2);
    s.dim:SetBackColor(COL_ZERO_DIM);
    s.dim:SetMouseVisible(false);
    s.dim:SetVisible(false);

    -- target progress along the bottom inside the border; width and
    -- colour are set by PaintSlot (hidden without a target)
    s.bar = Turbine.UI.Control();
    s.bar:SetParent(s.back);
    s.bar:SetPosition(1, SLOT_SIZE - 1 - BAR_H);
    s.bar:SetSize(SLOT_SIZE - 2, BAR_H);
    s.bar:SetBackColor(TargetColour(0));
    s.bar:SetMouseVisible(false);
    s.bar:SetVisible(false);

    -- created last so it is drawn above the icon layers; it ends just
    -- above the progress bar so the digits never sit on it
    s.count = Turbine.UI.Label();
    s.count:SetParent(s.back);
    s.count:SetPosition(2, 22 - BAR_H);
    s.count:SetSize(SLOT_SIZE - 4, 16);
    s.count:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    s.count:SetForeColor(COL_COUNT);
    s.count:SetTextAlignment(Turbine.UI.ContentAlignment.BottomRight);
    s.count:SetFontStyle(Turbine.UI.FontStyle.Outline);
    s.count:SetOutlineColor(COL_BLACK);
    Call(s.count, "SetMarkupEnabled", false);
    s.count:SetMouseVisible(false);
    s.count:SetText("");

    local function Highlight(on)
        s.inner:SetBackColor(on and COL_SLOT_HOVER or COL_SLOT_INNER);
    end

    s.back.DragDrop = function(sender, args)
        Highlight(sel.hover == i);
        pcall(OnSlotDrop, i, sender, args);
    end
    s.back.DragEnter = function() Highlight(true); end
    s.back.DragLeave = function() Highlight(sel.hover == i); end
    s.back.MouseEnter = function()
        dragSrc.SlotEntered(i);
        sel.hover = i;
        Highlight(true);
        RefreshNameLine();
    end
    s.back.MouseLeave = function()
        -- the mouse went onto the Ctrl+drag item control above this slot
        -- (DRAG SOURCE decides by the mouse position instead)
        if (dragSrc.slot == i) then return; end
        if (sel.hover == i) then sel.hover = nil; end
        Highlight(false);
        RefreshNameLine();
    end
    s.back.MouseClick = function(sender, args)
        if (args ~= nil and args.Button == Turbine.UI.MouseButton.Right) then
            ShowSlotMenu(i);
        elseif (args ~= nil and args.Button == Turbine.UI.MouseButton.Left) then
            -- craft pick mode (AUTO TARGETS): the click assigns / takes
            -- back / is rejected; when it handled the click, stop here
            if (ITR.Tracker ~= nil and ITR.Tracker.SlotClick ~= nil and ITR.Tracker.SlotClick(i)) then return; end
            if (trackedSlots[i] ~= nil) then sel.pinned = i; end
            RefreshNameLine();
        end
    end
    -- double-click on a tracked slot: edit its target (next frame);
    -- while the craft pick mode is on, the editor stays closed
    s.back.MouseDoubleClick = function(sender, args)
        if (args ~= nil and args.Button ~= nil and args.Button ~= Turbine.UI.MouseButton.Left) then return; end
        if (ITR.Tracker ~= nil and ITR.Tracker.IsPicking ~= nil and ITR.Tracker.IsPicking()) then return; end
        RequestTargetEdit(i);
    end

    slots[i] = s;
end

-- Keeps the whole main window on the screen (boot, resolution change,
-- the window growing at the screen edge).
local function KeepWindowOnScreen()
    local x, y = ClampToDisplay(win:GetLeft(), win:GetTop(), win:GetWidth(), win:GetHeight());
    if (x ~= win:GetLeft() or y ~= win:GetTop()) then win:SetPosition(x, y); end
end

-- "[-] 6 slots [+]": "-" is disabled at the minimum, "+" at the maximum.
local function RefreshStepper()
    local n = settings.slotCount;
    stepper.value:SetText(n .. ((n == 1) and " slot" or " slots"));
    stepper.minus:SetEnabled(n > MIN_SLOTS);
    stepper.plus:SetEnabled(n < MAX_SLOTS);
end

-- One "-" / "+" click: the same path as the options stepper and
-- /itr slots (clamp, layout, options panel, hidden-slots hint); the
-- settings are saved by the clock a moment later (many quick clicks,
-- one save).
local function StepSlots(direction)
    ChangeSettings(function(s)
        s.slotCount = Clamp(s.slotCount + direction, MIN_SLOTS, MAX_SLOTS);
    end, true);
end

-- Sizes the window and places the visible slots (boot and whenever the
-- number of slots or the slots per row change). The "[-] N slots [+]"
-- row is at the top left, so its buttons stay under the mouse while the
-- window grows or shrinks; the grid is below it, the name line last.
local function ApplyLayout()
    CloseTargetEditor(true);   -- valid typed text is kept
    dragSrc.Hide("layout");

    local n     = settings.slotCount;
    local cols  = math.min(settings.slotsPerRow, n);
    local rows  = math.ceil(n / cols);
    local gridW = cols * SLOT_SIZE + (cols - 1) * SLOT_GAP;
    local gridH = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP;
    local W     = math.max(MIN_WIN_W, 2 * PAD_X + gridW);
    local gridX = math.floor((W - gridW) / 2);
    local stepY = CONTENT_TOP;
    local gridY = stepY + STEP_H + 6;
    local nameY = gridY + gridH + 6;
    local H     = nameY + NAME_H + BOTTOM_PAD;

    for i = 1, MAX_SLOTS do
        local back = slots[i].back;
        if (i <= n) then
            local col = (i - 1) % cols;
            local row = math.floor((i - 1) / cols);
            back:SetPosition(gridX + col * (SLOT_SIZE + SLOT_GAP), gridY + row * (SLOT_SIZE + SLOT_GAP));
            back:SetVisible(true);
        else
            back:SetVisible(false);
        end
    end
    if (sel.hover ~= nil and sel.hover > n) then sel.hover = nil; end
    if (sel.pinned ~= nil and sel.pinned > n) then sel.pinned = nil; end

    nameLabel:SetPosition(PAD_X, nameY);
    nameLabel:SetSize(W - 2 * PAD_X, NAME_H);

    local stepX = PAD_X;
    stepper.minus:SetPosition(stepX, stepY);
    stepper.value:SetPosition(stepX + STEP_BTN_W + STEP_GAP, stepY);
    stepper.plus:SetPosition(stepX + STEP_BTN_W + STEP_LABEL_W + 2 * STEP_GAP, stepY);
    RefreshStepper();

    win:SetSize(W, H);
    KeepWindowOnScreen();

    PaintSlots();
    RefreshNameLine();
end

local function BuildWindow()
    win = Turbine.UI.Lotro.Window();
    win:SetPosition(data.winX or 200, data.winY or 200);
    -- the title has to stay short: the LOTRO title bar clips long text
    win:SetText("Items Tracker");
    win:SetVisible(data.winVisible ~= false);
    -- fallback drop target (in case child controls get no drops): handled
    -- one frame later, and only if no slot got the drop (DRAG & DROP)
    win:SetAllowDrop(true);
    win.DragDrop = function(sender, args)
        pcall(OnWindowDrop, args);
    end

    -- remember the window position a few seconds after it is dragged
    win.PositionChanged = function()
        posDirtyTicks = 4;
    end
    -- remember whether the window is shown (icon, commands, title-bar X)
    win.VisibleChanged = function()
        SyncWinVisible();
        if (win:IsVisible()) then
            MarkDirty();
        else
            CloseTargetEditor(false);
            dragSrc.Hide("window hidden");
        end
    end
    win.Closed = function()
        SyncWinVisible();
    end

    for i = 1, MAX_SLOTS do CreateSlot(i); end

    nameLabel = Turbine.UI.Label();
    nameLabel:SetParent(win);
    nameLabel:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    nameLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    nameLabel:SetMultiline(false);
    Call(nameLabel, "SetMarkupEnabled", false);
    nameLabel:SetMouseVisible(false);

    -- "Target for <name>:" shown instead of the name line while a target
    -- is edited (placed and sized by BeginTargetEdit)
    edit.prompt = Turbine.UI.Label();
    edit.prompt:SetParent(win);
    edit.prompt:SetSize(50, NAME_H);
    edit.prompt:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    edit.prompt:SetForeColor(COLOR_TEXT);
    edit.prompt:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    edit.prompt:SetMultiline(false);
    Call(edit.prompt, "SetMarkupEnabled", false);
    edit.prompt:SetText("Target:");
    edit.prompt:SetMouseVisible(false);
    edit.prompt:SetVisible(false);

    -- "[-] 6 slots [+]" (placed by ApplyLayout)
    stepper.minus = Turbine.UI.Lotro.Button();
    stepper.minus:SetParent(win);
    stepper.minus:SetSize(STEP_BTN_W, STEP_H);
    stepper.minus:SetText("-");
    stepper.minus.Click = function() StepSlots(-1); end

    stepper.value = Turbine.UI.Label();
    stepper.value:SetParent(win);
    stepper.value:SetSize(STEP_LABEL_W, STEP_H);
    stepper.value:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    stepper.value:SetForeColor(COLOR_TEXT);
    stepper.value:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    stepper.value:SetMouseVisible(false);

    stepper.plus = Turbine.UI.Lotro.Button();
    stepper.plus:SetParent(win);
    stepper.plus:SetSize(STEP_BTN_W, STEP_H);
    stepper.plus:SetText("+");
    stepper.plus.Click = function() StepSlots(1); end

    -- Ctrl+drag source (DRAG SOURCE): created last, so it is drawn above
    -- the slots; hidden until Ctrl is held over a tracked slot. Without
    -- it the slots work as before (no Ctrl+drag).
    local ok, ctl = pcall(Turbine.UI.Lotro.ItemControl);
    if (ok and ctl ~= nil) then
        dragItemControl = ctl;
        ctl:SetParent(win);
        ctl:SetSize(SLOT_SIZE - 2 * ICON_INSET, SLOT_SIZE - 2 * ICON_INSET);
        ctl:SetVisible(false);
        Call(ctl, "SetAllowDrop", false);   -- drops go to the slot / window
        ctl.DragStart = function() pcall(dragSrc.Started); end
    end

    BuildSlotMenu();
end

------------------------------------------------------------------------
-- BOOT
------------------------------------------------------------------------

settings = LoadSettings();
data = LoadData();
BuildWindow();
ApplyLayout();   -- also keeps the window on the screen (resolution change)
MarkDirty();

------------------------------------------------------------------------
-- OPTIONS PANEL (plugin manager -> ItemsTracker -> Options)
------------------------------------------------------------------------

local PANEL_W = 420;
local LEFT    = 20;

-- GLOBAL on purpose (see the UI section)
optionsPanel = Turbine.UI.Control();
optionsPanel:SetSize(PANEL_W, 400);
optionsPanel:SetBackColor(Turbine.UI.Color(0, 0, 0, 0));

local optionControls = { };
local updatingOptions = false;

local function OptionLabel(text, x, y, w, font, colour, align)
    local label = Turbine.UI.Label();
    label:SetParent(optionsPanel);
    label:SetPosition(x, y);
    label:SetSize(w, 20);
    label:SetFont(font or Turbine.UI.Lotro.Font.Verdana14);
    label:SetForeColor(colour or COLOR_TEXT);
    label:SetTextAlignment(align or Turbine.UI.ContentAlignment.MiddleLeft);
    label:SetText(text);
    return label;
end

local function OptionHeader(text, y)
    OptionLabel(text, LEFT, y, PANEL_W - 2 * LEFT,
        Turbine.UI.Lotro.Font.TrajanPro16, COLOR_HEADER);
    local line = Turbine.UI.Control();
    line:SetParent(optionsPanel);
    line:SetPosition(LEFT, y + 21);
    line:SetSize(PANEL_W - 2 * LEFT, 1);
    line:SetBackColor(Turbine.UI.Color(0.45, 0.45, 0.45));
end

local function OptionCheckBox(text, x, y, onChanged)
    local cb = Turbine.UI.Lotro.CheckBox();
    cb:SetParent(optionsPanel);
    cb:SetPosition(x, y);
    cb:SetSize(PANEL_W - x - LEFT, 20);
    cb:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    cb:SetForeColor(COLOR_TEXT);
    cb:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    cb:SetText(" " .. text);
    cb.CheckedChanged = function(sender)
        if (not updatingOptions) then onChanged(sender:IsChecked()); end
    end
    return cb;
end

-- "[-] value [+]" stepper. onStep(direction) changes the setting.
local function OptionStepper(x, y, valueW, onStep)
    local minus = Turbine.UI.Lotro.Button();
    minus:SetParent(optionsPanel);
    minus:SetPosition(x, y);
    minus:SetSize(24, 20);
    minus:SetText("-");
    minus.Click = function() onStep(-1); end

    local value = OptionLabel("", x + 28, y, valueW, Turbine.UI.Lotro.Font.Verdana14,
        Turbine.UI.Color(1, 1, 1), Turbine.UI.ContentAlignment.MiddleCenter);

    local plus = Turbine.UI.Lotro.Button();
    plus:SetParent(optionsPanel);
    plus:SetPosition(x + 32 + valueW, y);
    plus:SetSize(24, 20);
    plus:SetText("+");
    plus.Click = function() onStep(1); end

    return value, x + 56 + valueW;   -- value label, x after the stepper
end

-- Writes the current settings into the option controls.
RefreshOptions = function()
    local c = optionControls;
    if (c.slots == nil) then return; end
    updatingOptions = true;
    c.slots:SetText(tostring(settings.slotCount));
    c.perRow:SetText(tostring(settings.slotsPerRow));
    c.iconLocked:SetChecked(settings.iconLocked);
    updatingOptions = false;
end

-- The single entry point for every settings change (panel, icon menu,
-- slash commands): apply, save, refresh the panel. "saveLater": saved by
-- the clock within a second (window stepper clicks), and on unload.
ChangeSettings = function(change, saveLater)
    local oldCount, oldPerRow = settings.slotCount, settings.slotsPerRow;
    local hiddenBefore = CountTrackedFrom(oldCount + 1);

    change(settings);
    settings.slotCount   = Clamp(math.floor(settings.slotCount), MIN_SLOTS, MAX_SLOTS);
    settings.slotsPerRow = Clamp(math.floor(settings.slotsPerRow), MIN_PER_ROW, MAX_PER_ROW);

    if (settings.slotCount ~= oldCount or settings.slotsPerRow ~= oldPerRow) then
        ApplyLayout();
        MarkDirty();
    end
    -- told once, when tracked items first become hidden (not again on
    -- every further "-" click while some are already hidden)
    local hidden = CountTrackedFrom(settings.slotCount + 1);
    if (hiddenBefore == 0 and hidden > 0) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": " .. hidden .. " tracked item(s) are in hidden slots ("
            .. (settings.slotCount + 1) .. "-" .. MAX_SLOTS .. "); raise the slot count to see them.");
    end
    if (saveLater) then
        settingsDirty = true;
    else
        settingsDirty = false;
        SaveSettings();
    end
    RefreshOptions();
end

local function BuildOptionsPanel()
    local y = 10;
    OptionLabel("Items Tracker  v" .. PLUGIN_VERSION, LEFT, y, PANEL_W - 2 * LEFT,
        Turbine.UI.Lotro.Font.TrajanPro20, COLOR_HEADER, Turbine.UI.ContentAlignment.MiddleCenter);

    -- slots
    y = y + 40;
    OptionHeader("Slots", y);
    y = y + 32;
    OptionLabel("Number of slots (" .. MIN_SLOTS .. "-" .. MAX_SLOTS .. "):", LEFT, y, 190);
    optionControls.slots = OptionStepper(LEFT + 195, y, 40, function(dir)
        ChangeSettings(function(s)
            s.slotCount = Clamp(s.slotCount + dir, MIN_SLOTS, MAX_SLOTS);
        end);
    end);
    y = y + 26;
    OptionLabel("Slots per row (" .. MIN_PER_ROW .. "-" .. MAX_PER_ROW .. "):", LEFT, y, 190);
    optionControls.perRow = OptionStepper(LEFT + 195, y, 40, function(dir)
        ChangeSettings(function(s)
            s.slotsPerRow = Clamp(s.slotsPerRow + dir, MIN_PER_ROW, MAX_PER_ROW);
        end);
    end);
    y = y + 22;
    OptionLabel("Items in slots beyond the number of slots are kept, just hidden.",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);

    -- tracked items
    y = y + 34;
    OptionHeader("Tracked items", y);
    y = y + 32;
    OptionLabel("Drag items from your bags onto a slot. Right click a slot to clear it.",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);
    y = y + 18;
    OptionLabel("Targets: double-click a slot, or right click -> \"Set target...\".",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);
    y = y + 18;
    OptionLabel("Hold Ctrl over a slot to drag the item (e.g. into the auction search box)",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);
    y = y + 24;
    local clearAll = Turbine.UI.Lotro.Button();
    clearAll:SetParent(optionsPanel);
    clearAll:SetPosition(LEFT, y);
    clearAll:SetSize(160, 20);
    clearAll:SetText("Clear all slots");
    clearAll.Click = function() ClearAllSlots(); end

    -- craft calculator (CraftingWindow.lua)
    y = y + 34;
    OptionHeader("Craft calculator", y);
    y = y + 32;
    OptionLabel("Right click the icon -> Show craft calculator, or /itr craft.",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);
    y = y + 22;
    local craft = Turbine.UI.Lotro.Button();
    craft:SetParent(optionsPanel);
    craft:SetPosition(LEFT, y);
    craft:SetSize(160, 20);
    craft:SetText("Craft calculator");
    craft.Click = function()
        if (ITR.Craft ~= nil and ITR.Craft.ready) then
            pcall(ITR.Craft.Toggle);
        else
            Hint("craft calculator unavailable: " .. tostring(ITR.craftError));
        end
    end

    -- screen icon
    y = y + 34;
    OptionHeader("Icon", y);
    y = y + 32;
    optionControls.iconLocked = OptionCheckBox("Lock icon position", LEFT, y,
        function(checked)
            ChangeSettings(function(s) s.iconLocked = checked; end);
        end);
    y = y + 22;
    OptionLabel("Left click the icon to show / hide the window, right click for a menu.",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);

    -- defaults (settings only, the tracked items stay)
    y = y + 34;
    local defaults = Turbine.UI.Lotro.Button();
    defaults:SetParent(optionsPanel);
    defaults:SetPosition(LEFT, y);
    defaults:SetSize(160, 20);
    defaults:SetText("Restore defaults");
    defaults.Click = function()
        ChangeSettings(function(s)
            for key, value in pairs(DEFAULT_SETTINGS) do s[key] = value; end
        end);
    end

    optionsPanel:SetHeight(y + 36);
    RefreshOptions();
end

BuildOptionsPanel();

local thisPlugin = plugin or (Plugins and Plugins[PLUGIN_NAME]);
if (thisPlugin ~= nil) then
    thisPlugin.GetOptionsPanel = function()
        RefreshOptions();
        return optionsPanel;
    end
end

-- Opens this plugin's page in the plugin manager. The U49 docs name
-- Turbine.LotroPluginManager.ShowOptions, the in-game API dump only has
-- Turbine.PluginManager.ShowOptions - neither is confirmed, so try both.
OpenOptions = function()
    if (thisPlugin ~= nil) then
        local managers = { Turbine.LotroPluginManager, Turbine.PluginManager };
        for i = 1, 2 do
            local manager = managers[i];
            if (type(manager) == "table" and type(manager.ShowOptions) == "function") then
                if (pcall(manager.ShowOptions, thisPlugin)) then return; end
            end
        end
    end
    Turbine.Shell.WriteLine("Open the plugin manager and select " .. PLUGIN_NAME .. " -> Options.");
end

------------------------------------------------------------------------
-- SCREEN ICON
--
-- A small frameless window (same look as the InstanceLockTimer icon):
-- left click shows / hides the main window, left drag moves the icon
-- (unless locked), right click opens the context menu, the HUD toggle
-- (F12) hides / restores the icon and the main window.
-- "iconWin" and "iconMenu" are GLOBALS on purpose (see the UI section).
------------------------------------------------------------------------

local function ShowMainWindow(show)
    if (show and hudHidden) then
        -- an explicit "show" (command, menu) ends the HUD-hidden state;
        -- otherwise the window would show stale counts until F12 twice
        hudHidden = false;
        if (iconWin ~= nil) then iconWin:SetVisible(true); end
        if (ITR.Craft ~= nil and ITR.Craft.ready) then pcall(ITR.Craft.OnHud, false); end
    end
    win:SetVisible(show);
    if (show) then
        win:Activate();
        MarkDirty();
    end
    SyncWinVisible();
end

local function ToggleMainWindow()
    ShowMainWindow(not win:IsVisible());
end

local function IconClick()
    CloseSlotMenu();
    ToggleMainWindow();
end

local function ClampIconPosition(x, y)
    return ClampToDisplay(x, y, ICON_SIZE, ICON_SIZE);
end

-- Default icon position (nothing saved yet): left of the main window,
-- else right of it, above or below - the first that stays on screen
-- without overlapping the window; else the clamped "left" position.
local function GetDefaultIconPosition()
    local wx, wy = win:GetLeft(), win:GetTop();
    local ww, wh = win:GetWidth(), win:GetHeight();
    local candidates = {
        { wx - ICON_SIZE - ICON_GAP, wy },   -- left
        { wx + ww + ICON_GAP, wy },          -- right
        { wx, wy - ICON_SIZE - ICON_GAP },   -- above
        { wx, wy + wh + ICON_GAP },          -- below
    };
    for _, c in ipairs(candidates) do
        local x, y = ClampIconPosition(c[1], c[2]);
        local overlaps = (x < wx + ww and x + ICON_SIZE > wx
            and y < wy + wh and y + ICON_SIZE > wy);
        if (not overlaps) then return x, y; end
    end
    return ClampIconPosition(candidates[1][1], candidates[1][2]);
end

iconWin = nil;
iconMenu = nil;
local iconMenuItems = { };
local iconDrag;        -- { x, y, moved } while the left button is down

local function IconBorder(x, y, w, h)
    local c = Turbine.UI.Control();
    c:SetParent(iconWin);
    c:SetPosition(x, y);
    c:SetSize(w, h);
    c:SetBackColor(COL_GOLD);
    c:SetMouseVisible(false);
end

local function ToggleIconLock()
    ChangeSettings(function(s) s.iconLocked = not s.iconLocked; end);
end

local function CloseIconMenu()
    if (iconMenu ~= nil and type(iconMenu.Close) == "function") then
        pcall(iconMenu.Close, iconMenu);
    end
end

local function BuildIconMenu()
    iconMenu = Turbine.UI.ContextMenu();
    local items = iconMenu:GetItems();

    local function Add(key, text, onClick)
        local mi = Turbine.UI.MenuItem(text);
        mi.Click = function() onClick(); end
        items:Add(mi);
        iconMenuItems[key] = mi;
    end

    Add("lock", "Lock icon", ToggleIconLock);
    Add("toggle", "Hide main window", ToggleMainWindow);
    Add("craft", "Show craft calculator", function()
        if (ITR.Craft ~= nil and ITR.Craft.ready) then
            pcall(ITR.Craft.Toggle);
        else
            Hint("craft calculator unavailable: " .. tostring(ITR.craftError));
        end
    end);
    Add("options", "Options...", function() OpenOptions(); end);
end

-- Menu texts follow the current state; refreshed right before showing.
local function UpdateIconMenu()
    iconMenuItems.lock:SetText(settings.iconLocked and "Unlock icon" or "Lock icon");
    iconMenuItems.toggle:SetText(win:IsVisible() and "Hide main window" or "Show main window");
    do
        local ready = (ITR.Craft ~= nil and ITR.Craft.ready == true);
        local ok, shown = false, false;
        if (ready) then ok, shown = pcall(ITR.Craft.IsShown); end
        iconMenuItems.craft:SetText((ok and shown == true) and "Hide craft calculator" or "Show craft calculator");
        Call(iconMenuItems.craft, "SetEnabled", ready);
    end
end

local function ShowIconMenu()
    UpdateIconMenu();
    iconMenu:ShowMenu();
end

--[[
    HUD toggle (F12): hudHidden mirrors the game's HUD state and changes
    ONLY on the HUD key. Hiding hides the icon and the main window and
    closes the menus; restoring shows the icon and the main window if
    data.winVisible says so. hudApplying keeps SyncWinVisible from saving
    these changes. No scans run while the HUD is hidden.
]]
local function SetHudHidden(hidden)
    hudHidden = hidden;
    hudApplying = true;
    pcall(function()
        if (hidden) then
            iconDrag = nil;
            CloseIconMenu();
            CloseSlotMenu();
            CloseTargetEditor(false);
            dragSrc.Hide("HUD hidden");
            win:SetVisible(false);
            iconWin:SetVisible(false);
        else
            iconWin:SetVisible(true);
            win:SetVisible(data.winVisible == true);
            MarkDirty();
        end
        if (ITR.Craft ~= nil and ITR.Craft.ready) then pcall(ITR.Craft.OnHud, hidden); end
    end);
    hudApplying = false;
end

local function BuildIcon()
    iconWin = Turbine.UI.Window();
    iconWin:SetSize(ICON_SIZE, ICON_SIZE);
    if (data.iconX ~= nil and data.iconY ~= nil) then
        iconWin:SetPosition(ClampIconPosition(data.iconX, data.iconY));
    else
        iconWin:SetPosition(GetDefaultIconPosition());
    end
    iconWin:SetBackColor(COL_ICON_BG);
    iconWin:SetZOrder(10);
    iconWin:SetMouseVisible(true);

    IconBorder(0, 0, ICON_SIZE, 1);
    IconBorder(0, ICON_SIZE - 1, ICON_SIZE, 1);
    IconBorder(0, 0, 1, ICON_SIZE);
    IconBorder(ICON_SIZE - 1, 0, 1, ICON_SIZE);

    local text = Turbine.UI.Label();
    text:SetParent(iconWin);
    text:SetPosition(0, 0);
    text:SetSize(ICON_SIZE, ICON_SIZE);
    text:SetFont(Turbine.UI.Lotro.Font.TrajanProBold16);
    text:SetForeColor(COL_GOLD);
    text:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    text:SetFontStyle(Turbine.UI.FontStyle.Outline);
    text:SetOutlineColor(COL_BLACK);
    text:SetText("IT");
    text:SetMouseVisible(false);

    iconWin.MouseEnter = function() iconWin:SetBackColor(COL_ICON_BG_HOVER); end
    iconWin.MouseLeave = function() iconWin:SetBackColor(COL_ICON_BG); end

    iconWin.MouseDown = function(sender, args)
        if (args.Button == Turbine.UI.MouseButton.Left) then
            iconDrag = { x = args.X, y = args.Y, moved = false };
        end
    end
    -- a press that moves past the threshold is a drag, never a click -
    -- also on a locked icon, which just does not move
    iconWin.MouseMove = function(sender, args)
        if (iconDrag == nil) then return; end
        if (not iconDrag.moved
            and math.abs(args.X - iconDrag.x) + math.abs(args.Y - iconDrag.y) < DRAG_THRESHOLD) then
            return;
        end
        iconDrag.moved = true;
        if (settings.iconLocked) then return; end
        iconWin:SetPosition(ClampIconPosition(
            iconWin:GetLeft() + args.X - iconDrag.x, iconWin:GetTop() + args.Y - iconDrag.y));
    end
    iconWin.MouseUp = function(sender, args)
        if (args.Button == Turbine.UI.MouseButton.Left and iconDrag ~= nil) then
            local moved = iconDrag.moved;
            iconDrag = nil;
            if (not moved) then
                IconClick();
            elseif (not settings.iconLocked) then
                pcall(SaveAll);
            end
        elseif (args.Button == Turbine.UI.MouseButton.Right) then
            ShowIconMenu();
        end
    end

    -- HUD toggle (F12); a hidden window still receives the key
    iconWin:SetWantsKeyEvents(true);
    iconWin.KeyDown = function(sender, args)
        if (args.Action ~= ACTION_HUD_TOGGLE) then return; end
        SetHudHidden(not hudHidden);
    end

    BuildIconMenu();
    iconWin:SetVisible(true);
end

BuildIcon();

------------------------------------------------------------------------
-- CRAFT CALCULATOR INTERFACE
--
-- What CraftingWindow.lua / CraftingDataProvider.lua use from this file
-- (plain assignments: no new top-level locals here), then the
-- calculator's setup - in pcall, so a failing calculator never stops
-- the tracker.
------------------------------------------------------------------------

ITR.PLUGIN_NAME     = PLUGIN_NAME;
ITR.CONTENT_TOP     = CONTENT_TOP;
ITR.MAX_SLOTS       = MAX_SLOTS;
ITR.MAX_TARGET      = MAX_TARGET;
ITR.NAME_CHAR_W     = NAME_CHAR_W;
ITR.COLOR_HEADER    = COLOR_HEADER;
ITR.COLOR_TEXT      = COLOR_TEXT;
ITR.COLOR_HINT      = COLOR_HINT;
ITR.COL_GOLD        = COL_GOLD;
ITR.COL_COUNT_ZERO  = COL_COUNT_ZERO;
ITR.COL_SLOT_BORDER = COL_SLOT_BORDER;
ITR.COL_SLOT_INNER  = COL_SLOT_INNER;
ITR.COL_SLOT_HOVER  = COL_SLOT_HOVER;
ITR.QUALITY_COLOR   = QUALITY_COLOR;
ITR.Call            = Call;
ITR.Field           = Field;
ITR.CleanGameText   = CleanGameText;
ITR.WholeNumber     = WholeNumber;
ITR.Clamp           = Clamp;
ITR.Shorten         = Shorten;
ITR.EncodeText      = EncodeText;
ITR.DecodeText      = DecodeText;
ITR.ClampToDisplay  = ClampToDisplay;
ITR.Hint            = Hint;
ITR.ChatSafe        = ChatSafe;
ITR.ShowMainWindow  = ShowMainWindow;
ITR.GetMainWindow   = function() return win; end

-- The craft pick mode (AUTO TARGETS) gets the main window: a later
-- Escape event on it then stops the picking. Plain guarded call: the
-- calculator does not exist when an import failed.
if (ITR.Tracker ~= nil and type(ITR.Tracker.AttachPickKeys) == "function") then
    pcall(ITR.Tracker.AttachPickKeys, win);
end

if (ITR.Craft ~= nil and type(ITR.Craft.Init) == "function") then
    local ok, err = pcall(ITR.Craft.Init);
    if (not ok) then
        ITR.Craft.ready = false;
        ITR.craftError = tostring(err);
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": craft calculator unavailable: " .. ITR.craftError);
    end
else
    ITR.craftError = "CraftingWindow.lua not loaded";
end

------------------------------------------------------------------------
-- MASTER CLOCK
--
-- Runs every frame but only does a few comparisons: a window drop or a
-- target editor request that waits for the next frame, the Ctrl check
-- while a slot is hovered (DRAG SOURCE), the throttled
-- bag scan while the window is shown, and once per second the delayed
-- saves.
-- GLOBAL on purpose - see the comment at the top of the UI section.
------------------------------------------------------------------------

tickControl = Turbine.UI.Control();
local lastSecond = -1;
function tickControl:Update()
    local now = Turbine.Engine.GetGameTime();

    if (dropState.pending ~= nil) then ProcessWindowDrop(now); end
    if (edit.pending ~= nil or edit.refocus) then ProcessTargetEdit(now); end
    if (sel.hover ~= nil or dragSrc.slot ~= nil) then pcall(dragSrc.Update, now); end

    if (not hudHidden and win:IsVisible() and HasTracked()) then
        if ((dirty and now - lastScan >= SCAN_THROTTLE) or now - lastScan >= POLL_INTERVAL) then
            dirty = false;
            lastScan = now;
            pcall(ScanBackpack);
        end
    end

    local second = math.floor(now);
    if (second == lastSecond) then return; end
    lastSecond = second;

    -- save the window position a few seconds after a drag
    if (posDirtyTicks > 0) then
        posDirtyTicks = posDirtyTicks - 1;
        if (posDirtyTicks == 0) then saveDirty = true; end
    end
    if (saveDirty) then
        saveDirty = false;
        pcall(SaveAll);
    end
    if (settingsDirty) then
        settingsDirty = false;
        SaveSettings();
    end
end
tickControl:SetWantsUpdates(true);

------------------------------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------------------------------

local command = Turbine.ShellCommand();

function command:GetHelp()
    return "Usage: /itr show | hide | toggle | options | slots <1-30> | perrow <1-12>"
        .. " | target <n> <count>|clear | clear <n>|all | list | craft [show|hide|clear|debug] | debug | help";
end

function command:GetShortHelp()
    return "Controls ItemsTracker";
end

local function ListTracked()
    pcall(ScanBackpack);
    if (not HasTracked()) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": no items are tracked.");
        return;
    end
    for i = 1, MAX_SLOTS do
        local t = trackedSlots[i];
        if (t ~= nil) then
            local line = "#" .. i .. " " .. ChatSafe(t.name) .. ": " .. CountText(t);
            if (t.autoTarget) then line = line .. " (auto)"; end
            if (t.target ~= nil and t.count ~= nil and t.count >= t.target) then line = line .. " (done)"; end
            if (i > settings.slotCount) then line = line .. " (hidden)"; end
            Turbine.Shell.WriteLine(line);
        end
    end
end

-- /itr target <slot> <count> | clear  (0 also clears)
local function TargetCommand(rest)
    local usage = "Usage: /itr target <1-" .. MAX_SLOTS .. "> <" .. MIN_TARGET .. "-" .. MAX_TARGET
        .. "> | /itr target <1-" .. MAX_SLOTS .. "> clear";
    local a, b = string.match(rest, "^(%S+)%s+(%S+)$");
    local i = tonumber(a);
    if (i == nil or i ~= WholeNumber(i) or i < 1 or i > MAX_SLOTS) then
        Turbine.Shell.WriteLine(usage);
        return;
    end
    if (trackedSlots[i] == nil) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": slot " .. i .. " is empty.");
        return;
    end
    -- the same rules as the editor (ParseTargetText), one word: "1,000"
    -- works, "1 000" does not
    local valid, n = true, nil;
    if (b ~= "clear") then valid, n = ParseTargetText(b); end
    if (not valid) then
        Turbine.Shell.WriteLine(usage);
        return;
    end
    -- an open editor for this slot would overwrite the value on FocusLost
    if (edit.slot == i) then CloseTargetEditor(false); end
    -- a picked slot refuses (the hint says so); no success line then
    if (not SetTarget(i, n)) then return; end
    local hidden = (i > settings.slotCount) and " (slot is hidden)" or "";
    if (n == nil) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": target of slot " .. i .. " cleared." .. hidden);
    else
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": target of slot " .. i .. " set to " .. n .. "." .. hidden);
    end
end

function command:Execute(commandName, args)
    local text = string.lower(args or "");
    local word, rest = string.match(text, "^%s*(%S+)%s*(.-)%s*$");
    if (word == nil) then
        word = "";
        rest = "";
    end

    if (word == "" or word == "show") then
        ShowMainWindow(true);
    elseif (word == "hide") then
        ShowMainWindow(false);
    elseif (word == "toggle") then
        ToggleMainWindow();
    elseif (word == "options" or word == "settings") then
        OpenOptions();
    elseif (word == "slots") then
        local n = WholeNumber(rest);   -- nil for text, "nan", "inf"
        if (n == nil) then
            Turbine.Shell.WriteLine("Usage: /itr slots <" .. MIN_SLOTS .. "-" .. MAX_SLOTS .. ">");
        else
            ChangeSettings(function(s) s.slotCount = Clamp(n, MIN_SLOTS, MAX_SLOTS); end);
            Turbine.Shell.WriteLine(PLUGIN_NAME .. ": " .. settings.slotCount .. " slot(s).");
        end
    elseif (word == "perrow" or word == "columns") then
        local n = WholeNumber(rest);
        if (n == nil) then
            Turbine.Shell.WriteLine("Usage: /itr perrow <" .. MIN_PER_ROW .. "-" .. MAX_PER_ROW .. ">");
        else
            ChangeSettings(function(s) s.slotsPerRow = Clamp(n, MIN_PER_ROW, MAX_PER_ROW); end);
            Turbine.Shell.WriteLine(PLUGIN_NAME .. ": " .. settings.slotsPerRow .. " slot(s) per row.");
        end
    elseif (word == "clear") then
        local n = tonumber(rest);
        if (rest == "all") then
            -- refused while the craft picking is on (the hint says so)
            if (ClearAllSlots()) then
                Turbine.Shell.WriteLine(PLUGIN_NAME .. ": all slots cleared.");
            end
        elseif (n ~= nil and n == WholeNumber(n) and n >= 1 and n <= MAX_SLOTS) then
            if (ClearSlot(n)) then
                Turbine.Shell.WriteLine(PLUGIN_NAME .. ": slot " .. n .. " cleared.");
            end
        else
            Turbine.Shell.WriteLine("Usage: /itr clear <1-" .. MAX_SLOTS .. "> | /itr clear all");
        end
    elseif (word == "target") then
        TargetCommand(rest);
    elseif (word == "list") then
        ListTracked();
    elseif (word == "craft") then
        if (ITR.Craft ~= nil and ITR.Craft.ready) then
            local ok, err = pcall(ITR.Craft.Command, rest);
            if (not ok) then Turbine.Shell.WriteLine(PLUGIN_NAME .. ": craft calculator error: " .. tostring(err)); end
        else
            Turbine.Shell.WriteLine(PLUGIN_NAME .. ": craft calculator unavailable: " .. tostring(ITR.craftError));
        end
    elseif (word == "debug") then
        debugDrops = not debugDrops;
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": drop debug output " .. (debugDrops and "on." or "off."));
    elseif (word == "help") then
        Turbine.Shell.WriteLine(self:GetHelp());
    else
        Turbine.Shell.WriteLine("Unknown argument. " .. self:GetHelp());
    end
end

-- AddCommand returns how many names were registered (0 if taken)
for _, name in ipairs({ "ItemsTracker", "itr" }) do
    local ok, registered = pcall(Turbine.Shell.AddCommand, name, command);
    if (not ok or registered == false or registered == 0) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": /" .. name .. " could not be registered.");
    end
end

------------------------------------------------------------------------
-- CLEANUP ON PLUGIN UNLOAD
------------------------------------------------------------------------

-- "unloaded" is declared at the top: SyncWinVisible checks it, so hiding
-- the windows below does not store the main window as hidden
local function OnUnload()
    if (unloaded) then return; end
    unloaded = true;
    if (ITR.Craft ~= nil and type(ITR.Craft.Unload) == "function") then pcall(ITR.Craft.Unload); end
    -- end a running craft pick mode: what was assigned stays (AUTO TARGETS)
    if (ITR.Tracker ~= nil and type(ITR.Tracker.Unload) == "function") then pcall(ITR.Tracker.Unload); end
    pcall(SaveAll);
    pcall(SaveSettings);
    pcall(Turbine.Shell.RemoveCommand, command);
    UnhookAll();
    tickControl:SetWantsUpdates(false);
    iconDrag = nil;
    dropState.pending = nil;
    CloseIconMenu();
    CloseSlotMenu();
    pcall(CloseTargetEditor, false);
    pcall(dragSrc.Hide, "unload");
    win:SetVisible(false);
    if (iconWin ~= nil) then
        pcall(iconWin.SetWantsKeyEvents, iconWin, false);
        iconWin:SetVisible(false);
    end
end

if (thisPlugin ~= nil) then
    thisPlugin.Unload = OnUnload;
end

Turbine.Shell.WriteLine(
    PLUGIN_NAME .. " v" .. PLUGIN_VERSION .. " loaded. Type /itr help for commands.");
