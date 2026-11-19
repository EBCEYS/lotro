--[[=========================================================================

    InstanceLockTimer v1.3.0  --  The Lord of the Rings Online plugin
    -------------------------------------------------------------------

    * Press the button to start a 1-hour instance lock timer.
    * An "Active" counter shows how many timers are running; it decreases
      automatically whenever a timer expires.
    * A "Today" counter counts how many timers you started during the
      current server day. It is drawn in a gradient colour, green at 0
      up to red at 100, with a matching progress bar.
    * The daily counter resets at the server day change (07:00 UTC in
      summer, 08:00 UTC in winter by default - configurable in the
      plugin manager options). Active timers are never reset by the day
      change - they keep counting down until they expire. Removing a
      timer with its "X" on the same day you started it also gives that
      start back to the daily counter (it never goes below 0).
    * Click the name of a timer to rename it: type the new name and
      press Enter (or click anywhere else) to confirm, Escape to cancel.
    * When you take a mission, the chat line "New Quest: Mission:
      <name>" opens a small offer window - one click starts a 1h
      timer named after that mission (English client text only).
    * Everything is saved per character: active timers survive logout
      and /ui reload (they keep running in real time), and the daily
      counter survives relogging. If the server day changed while you
      were offline, the daily counter resets on load.

    SETTINGS (plugin manager -> InstanceLockTimer -> Options, or /ilt options)
    --------
    * Server reset time (UTC, summer time)
    * Winter time (+1 hour), set manually or detected automatically
    * Offer mission timers on/off
    * Main window width and number of visible timer rows
    Settings are stored account-wide.

    INSTALLATION
    ------------
    1. Copy the InstanceLockTimer folder (containing Main.lua and
       InstanceLockTimer.plugin) into the game Plugins directory:
         Documents\The Lord of the Rings Online\Plugins\
       so that the files end up as:
         ...\Plugins\InstanceLockTimer\Main.lua
         ...\Plugins\InstanceLockTimer\InstanceLockTimer.plugin
       Nothing needs to be created or edited.
    2. In game:  /plugins load InstanceLockTimer

    COMMANDS
    --------
    /ilt show           show the main window
    /ilt options        open the settings in the plugin manager
    /ilt add <minutes>  start a custom-length timer (handy for testing:
                        "/ilt add 1" starts a 1-minute test timer)
    /ilt resetdaily     reset the daily counter
    /ilt help           command overview

=========================================================================]]

import "Turbine";
import "Turbine.UI";
import "Turbine.UI.Lotro";

------------------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------------------

local PLUGIN_NAME        = "InstanceLockTimer";
local PLUGIN_VERSION     = "1.3.0";

local TIMER_DURATION     = 3600;  -- length of a standard timer, seconds (1 hour)
local DAILY_MAX          = 100;   -- daily gradient: green at 0 -> red at DAILY_MAX

local SAVE_KEY           = "InstanceLockTimerData";      -- per character
local SETTINGS_KEY       = "InstanceLockTimerSettings";  -- account wide

-- defaults of the user settings (changed in the plugin manager options)
local DEFAULT_SETTINGS = {
    resetHour     = 7,     -- server day reset, UTC, summer time
    resetMinute   = 0,
    winterTime    = true,  -- manual winter time: reset one hour later
    autoWinter    = true,  -- detect winter time from the US daylight saving dates
    offerMissions = true,  -- watch chat for accepted missions (English client)
    windowWidth   = 300,
    visibleRows   = 8,     -- timer rows shown before a "+N more" line appears
};

local MIN_WIDTH, MAX_WIDTH, WIDTH_STEP = 240, 600, 20;
local MIN_ROWS,  MAX_ROWS              = 1, 20;

local ROW_H              = 26;     -- height of one timer row
local ROWS_TOP           = 120;    -- y position of the timer list
local MIN_HEIGHT         = 176;
local CONTENT_TOP        = 34;     -- in a Lotro.Window, child coordinates
                                   -- start at the very top edge of the
                                   -- window: the title bar covers roughly
                                   -- the first 30px, so all content must
                                   -- begin below it

local DAY_SECONDS        = 86400;

local ACTION_ENTER       = 162;
local ACTION_ESCAPE      = 145;

------------------------------------------------------------------------
-- STATE / FORWARD DECLARATIONS
------------------------------------------------------------------------

local settings;         -- user settings, see DEFAULT_SETTINGS
local W, INNER_W;       -- window width and width of its content area
local SaveAll;          -- defined in the PERSISTENCE section

------------------------------------------------------------------------
-- UTILITIES
------------------------------------------------------------------------

-- Current game server time in whole seconds since 1970 (UTC). If the
-- engine clock is not available on this client, fall back to the local
-- clock. Whole seconds also keep the saved data free of fractional
-- numbers, which PluginData may write with a locale decimal comma and
-- then fail to read back.
local function GetServerTime()
    local t;
    if (type(Turbine.Engine.GetServerTime) == "function") then
        t = Turbine.Engine.GetServerTime();
    end
    if (type(t) ~= "number") then
        t = Turbine.Engine.GetLocalTime();
    end
    return math.floor(t);
end

-- Date helpers (the os library is not available to plugins).
-- Days since 1970-01-01 <-> civil date, proleptic Gregorian calendar.
local function DaysFromCivil(y, m, d)
    if (m <= 2) then y = y - 1; end
    local era = math.floor(y / 400);
    local yoe = y - era * 400;
    local mp  = (m + 9) % 12;
    local doy = math.floor((153 * mp + 2) / 5) + d - 1;
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy;
    return era * 146097 + doe - 719468;
end

local function YearFromDays(z)
    z = z + 719468;
    local era = math.floor(z / 146097);
    local doe = z - era * 146097;
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
        - math.floor(doe / 146096)) / 365);
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100));
    local mp  = math.floor((5 * doy + 2) / 153);
    local y   = yoe + era * 400;
    if (mp >= 10) then y = y + 1; end   -- January / February
    return y;
end

-- Day number of the n-th Sunday of a month (1970-01-01 was a Thursday).
local function NthSunday(y, m, n)
    local first = DaysFromCivil(y, m, 1);
    local weekday = (first + 4) % 7;    -- 0 = Sunday
    return first + (7 - weekday) % 7 + (n - 1) * 7;
end

-- US Eastern daylight saving time (the LOTRO servers follow it):
-- second Sunday of March 02:00 EST (07:00 UTC) until the first Sunday
-- of November 02:00 EDT (06:00 UTC).
local function IsUSSummerTime(t)
    local y = YearFromDays(math.floor(t / DAY_SECONDS));
    local startT = NthSunday(y, 3, 2) * DAY_SECONDS + 7 * 3600;
    local endT   = NthSunday(y, 11, 1) * DAY_SECONDS + 6 * 3600;
    return (t >= startT and t < endT);
end

local function IsWinterTime(t)
    if (settings.autoWinter) then
        return not IsUSSummerTime(t);
    end
    return settings.winterTime;
end

-- Seconds after 00:00 UTC at which the server day changes at time t.
local function GetResetOffset(t)
    local offset = settings.resetHour * 3600 + settings.resetMinute * 60;
    if (IsWinterTime(t)) then
        offset = offset + 3600;
    end
    return offset;
end

--[[
    Stable key for the current server day. The key changes exactly when
    the server day flips. Two moments share a key if and only if they
    belong to the same server day.
]]
local function GetDayKey(serverTime)
    return math.floor((serverTime - GetResetOffset(serverTime)) / DAY_SECONDS);
end

-- Time of the next server day change after "now".
local function GetNextReset(now)
    local base = (GetDayKey(now) + 1) * DAY_SECONDS;
    local candidate = base + GetResetOffset(now);
    -- re-evaluate once in case winter time switches before the reset
    return base + GetResetOffset(candidate);
end

local function FormatClock(seconds)
    seconds = seconds % DAY_SECONDS;
    return string.format("%02d:%02d",
        math.floor(seconds / 3600), math.floor((seconds % 3600) / 60));
end

-- "mm:ss", or "h:mm:ss" for timers of an hour or longer.
local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5));
    if (seconds >= 3600) then
        local h = math.floor(seconds / 3600);
        local m = math.floor((seconds % 3600) / 60);
        local s = seconds % 60;
        return string.format("%d:%02d:%02d", h, m, s);
    end
    local m = math.floor(seconds / 60);
    local s = seconds % 60;
    return string.format("%d:%02d", m, s);
end

-- Gradient colour for the daily counter: green (0) -> yellow -> red (DAILY_MAX).
local function GetDailyColour(count)
    local t = math.min(math.max(count, 0) / DAILY_MAX, 1);
    local h = (1 - t) * 2;                -- 0 = red end, 2 = green end
    local r, g, b;
    if (h <= 1) then
        r, g, b = 1, h, 0;                -- red -> yellow
    else
        r, g, b = 2 - h, 1, 0;            -- yellow -> green
    end
    return Turbine.UI.Color(r, g, b);
end

-- Local "HH:MM" stamp, used only for the "started at" display.
local function GetClockStamp()
    local ok, d = pcall(Turbine.Engine.GetDate);
    if (ok and d ~= nil and d.Hour ~= nil and d.Minute ~= nil) then
        return string.format("%02d:%02d", d.Hour, d.Minute);
    end
    return "";
end

local function Clamp(value, min, max)
    if (value < min) then return min; end
    if (value > max) then return max; end
    return value;
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
        -- numbers may come back as strings depending on the client locale
        if (type(default) == "number") then value = tonumber(value); end
        if (type(value) ~= type(default)) then value = default; end
        s[key] = value;
    end
    s.resetHour   = Clamp(math.floor(s.resetHour), 0, 23);
    s.resetMinute = Clamp(math.floor(s.resetMinute), 0, 59);
    s.windowWidth = Clamp(math.floor(s.windowWidth), MIN_WIDTH, MAX_WIDTH);
    s.visibleRows = Clamp(math.floor(s.visibleRows), MIN_ROWS, MAX_ROWS);
    return s;
end

local function SaveSettings()
    pcall(Turbine.PluginData.Save, Turbine.DataScope.Account, SETTINGS_KEY, settings, nil);
end

------------------------------------------------------------------------
-- TIMER MANAGER
--
-- Owns the list of active timers and the per-server-day counter.
-- The UI registers a callback and gets notified about:
--   "Added" "Removed" "Expired" "DailyChanged"
------------------------------------------------------------------------

local Manager = { };
Manager.timers      = { };  -- active records: { expiresAt, startedAt, duration, startedAtText, name }
Manager.dailyDayKey = nil;  -- dayKey the daily counter belongs to
Manager.dailyCount  = 0;    -- timers started during the current server day
Manager.callbacks   = { };

function Manager:RegisterCallback(fn)
    table.insert(self.callbacks, fn);
end

local function Notify(event, record)
    for _, fn in ipairs(Manager.callbacks) do
        pcall(fn, event, record);
    end
end

function Manager:GetTimers()
    return self.timers;
end

function Manager:GetActiveCount()
    return #self.timers;
end

function Manager:GetDailyCount()
    return self.dailyCount;
end

-- First "Timer N" name that is not used by an active timer.
function Manager:NextDefaultName()
    local used = { };
    for _, t in ipairs(self.timers) do used[t.name] = true; end
    local n = 1;
    while (used["Timer " .. n]) do n = n + 1; end
    return "Timer " .. n;
end

-- Starts a new timer of the given duration (seconds) and counts its start
-- towards the current server day. "name" is optional; without it the timer
-- gets the next free "Timer N" default name.
function Manager:StartTimer(duration, startedAtText, name)
    local now = GetServerTime();
    duration = math.floor(duration);
    local rec = {
        expiresAt     = now + duration,
        startedAt     = now,
        duration      = duration,
        startedAtText = startedAtText or "",
        name          = name or self:NextDefaultName(),
    };
    table.insert(self.timers, rec);

    -- count this start towards the current server day
    local key = GetDayKey(now);
    if (self.dailyDayKey ~= key) then
        self.dailyDayKey = key;
        self.dailyCount = 0;
    end
    self.dailyCount = self.dailyCount + 1;

    Notify("DailyChanged", nil);
    Notify("Added", rec);
    self:Save();
    return rec;
end

-- Removes a timer manually (the "X" button). If the timer was started
-- during the current server day, removing it also gives that start back
-- to the daily counter (it never goes below 0; a timer started on a
-- previous day does not touch today's count).
function Manager:CancelTimer(rec)
    for i, t in ipairs(self.timers) do
        if (t == rec) then
            table.remove(self.timers, i);
            if (self.dailyCount > 0
                and GetDayKey(rec.startedAt) == GetDayKey(GetServerTime())) then
                self.dailyCount = self.dailyCount - 1;
                Notify("DailyChanged", nil);
            end
            Notify("Removed", rec);
            self:Save();
            return true;
        end
    end
    return false;
end

-- Resets the daily counter when the server day changes. Active timers are
-- deliberately left untouched.
function Manager:CheckDayChange()
    local key = GetDayKey(GetServerTime());
    if (self.dailyDayKey ~= key) then
        self.dailyDayKey = key;
        self.dailyCount = 0;
        Notify("DailyChanged", nil);
        return true;
    end
    return false;
end

-- Called once per second: expires finished timers and watches the day change.
function Manager:Update(now)
    local changed = self:CheckDayChange();
    local expired = false;
    for i = #self.timers, 1, -1 do
        if (now >= self.timers[i].expiresAt) then
            table.remove(self.timers, i);
            expired = true;
        end
    end
    if (expired) then
        Notify("Expired", nil);
    end
    if (changed or expired) then
        self:Save();
    end
end

-- Manual reset via slash command.
function Manager:ResetDaily()
    self.dailyDayKey = GetDayKey(GetServerTime());
    self.dailyCount = 0;
    Notify("DailyChanged", nil);
    self:Save();
end

-- Restores state from the PluginData table.
function Manager:Initialize(data)
    self.data = data;
    self.timers = { };

    if (type(data.timers) == "table") then
        for i, rec in ipairs(data.timers) do
            if (type(rec) == "table") then
                rec.expiresAt = tonumber(rec.expiresAt);
                rec.startedAt = tonumber(rec.startedAt);
                rec.duration  = tonumber(rec.duration);
                if (rec.expiresAt ~= nil) then
                    if (rec.duration == nil or rec.duration <= 0) then rec.duration = TIMER_DURATION; end
                    if (rec.startedAt == nil) then rec.startedAt = rec.expiresAt - rec.duration; end
                    if (type(rec.startedAtText) ~= "string") then rec.startedAtText = ""; end
                    if (type(rec.name) ~= "string" or rec.name == "") then rec.name = "Timer " .. i; end
                    table.insert(self.timers, rec);
                end
            end
        end
    end

    -- drop timers that ran out while the plugin was not loaded
    local now = GetServerTime();
    for i = #self.timers, 1, -1 do
        if (self.timers[i].expiresAt <= now) then
            table.remove(self.timers, i);
        end
    end

    self.dailyDayKey = tonumber(data.dailyDayKey);
    self.dailyCount = math.max(0, math.floor(tonumber(data.dailyCount) or 0));

    -- if the server day changed while we were offline, reset the counter
    self:CheckDayChange();
    self:Save();
end

function Manager:Save()
    if (self.data ~= nil) then
        self.data.timers      = self.timers;
        self.data.dailyDayKey = self.dailyDayKey;
        self.data.dailyCount  = self.dailyCount;
    end
    if (SaveAll ~= nil) then
        pcall(SaveAll);
    end
end

------------------------------------------------------------------------
-- USER INTERFACE
------------------------------------------------------------------------

-- "win", "offerWin", "optionsPanel" and "tickControl" are GLOBALS on
-- purpose: LOTRO garbage-collects any control whose last Lua reference is
-- a local that goes out of scope when the script finishes loading. That
-- silently kills the update loop (frozen text, bars that never move,
-- timers that only expire on the next /plugins load). Everything else
-- hangs off those, and the engine keeps the child controls of a live
-- control alive.
local startButton, activeLabel, dailyLabel, dailyTrack, dailyFill, separator;
local rowsContainer, emptyLabel, moreLabel;
local rows = { };
local currentManager;
local posDirtyTicks = 0;

-- Closes the inline name editor of a row. "commit" applies the typed text
-- as the new timer name and saves; otherwise the old name is kept.
local function CloseEditor(row, commit)
    local editor = row.editor;
    if (editor == nil) then return; end
    row.editor = nil;
    if (commit) then
        local text = editor:GetText() or "";
        text = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "");
        if (text ~= "") then
            row.record.name = text;
            if (currentManager ~= nil) then currentManager:Save(); end
        end
        -- repaint the label from the record so the new name is visible
        row.name:SetText(row.record.name);
    end
    -- detaching the editor fires FocusLost; the row.editor guard above
    -- makes that a no-op instead of a double commit
    editor:SetParent(nil);
    row.name:SetVisible(true);
end

-- Opens the inline name editor for a row (only one editor at a time).
local function BeginEdit(row)
    for _, r in ipairs(rows) do
        if (r ~= row and r.editor ~= nil) then CloseEditor(r, false); end
    end
    if (row.editor ~= nil) then return; end
    row.name:SetVisible(false);
    local editor = Turbine.UI.Lotro.TextBox();
    editor:SetParent(row.back);
    editor:SetPosition(78, 0);
    editor:SetSize(INNER_W - 78 - 24, ROW_H - 3);
    editor:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    editor:SetForeColor(Turbine.UI.Color(1, 1, 1));
    editor:SetBackColor(Turbine.UI.Color(0.05, 0.05, 0.05));
    editor:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    editor:SetMultiline(false);
    editor:SetText(row.record.name);
    -- LOTRO delivers key presses as "Action" codes; there is no KeyCode enum
    editor.KeyDown = function(_, args)
        if (args.Action == ACTION_ENTER) then
            CloseEditor(row, true);
        elseif (args.Action == ACTION_ESCAPE) then
            CloseEditor(row, false);
        end
    end
    -- clicking anywhere outside the editor commits the rename
    editor.FocusLost = function()
        CloseEditor(row, true);
    end
    row.editor = editor;
    editor:Focus();
end

local function PaintRow(row, now)
    local rec = row.record;
    local remaining = rec.expiresAt - now;

    row.time:SetText(FormatDuration(remaining));
    if (remaining <= 300) then
        row.time:SetForeColor(Turbine.UI.Color(1, 0.35, 0.25));
    else
        row.time:SetForeColor(Turbine.UI.Color(1, 1, 1));
    end

    local frac = math.min(math.max(remaining / rec.duration, 0), 1);
    row.fill:SetSize(math.floor(INNER_W * frac), ROW_H - 3);
end

local function CreateRow(rec, index)
    local row = { record = rec };

    row.back = Turbine.UI.Control();
    row.back:SetParent(rowsContainer);
    row.back:SetPosition(0, (index - 1) * ROW_H);
    row.back:SetSize(INNER_W, ROW_H - 3);
    row.back:SetBackColor(Turbine.UI.Color(0.12, 0.12, 0.12));

    -- depleting bar showing the remaining fraction of the timer
    row.fill = Turbine.UI.Control();
    row.fill:SetParent(row.back);
    row.fill:SetPosition(0, 0);
    row.fill:SetBackColor(Turbine.UI.Color(0.35, 0.5, 0.8));

    -- remaining time
    row.time = Turbine.UI.Label();
    row.time:SetParent(row.back);
    row.time:SetPosition(8, 0);
    row.time:SetSize(64, ROW_H - 3);
    row.time:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    row.time:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);

    -- timer name (click to rename it)
    row.name = Turbine.UI.Label();
    row.name:SetParent(row.back);
    row.name:SetPosition(78, 0);
    row.name:SetSize(INNER_W - 78 - 24, ROW_H - 3);
    row.name:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    row.name:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    row.name:SetForeColor(Turbine.UI.Color(0.75, 0.75, 0.75));
    row.name:SetMouseVisible(true);
    row.name:SetText(rec.name or "Timer");
    row.name.MouseClick = function()
        BeginEdit(row);
    end

    -- cancel button
    row.cancel = Turbine.UI.Label();
    row.cancel:SetParent(row.back);
    row.cancel:SetPosition(INNER_W - 20, 0);
    row.cancel:SetSize(18, ROW_H - 3);
    row.cancel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    row.cancel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    row.cancel:SetForeColor(Turbine.UI.Color(0.85, 0.35, 0.35));
    row.cancel:SetText("X");
    row.cancel:SetMouseVisible(true);
    row.cancel.MouseClick = function()
        if (currentManager ~= nil) then
            currentManager:CancelTimer(rec);
        end
    end

    -- paint the remaining time and bar right away, so the row is correct
    -- even before the first tick
    PaintRow(row, GetServerTime());
    return row;
end

local function ClearRows()
    for _, r in ipairs(rows) do
        -- neutralise the editor first: detaching controls can fire
        -- FocusLost, and CloseEditor must not run on a torn-down row
        r.editor = nil;
        r.back:SetVisible(false);
        r.back:SetParent(nil);
    end
    rows = { };
end

local function RebuildRows()
    ClearRows();
    local maxRows = settings.visibleRows;
    local timers = currentManager:GetTimers();
    local count = #timers;
    local visible = math.min(count, maxRows);
    local listHeight = visible * ROW_H;

    rowsContainer:SetSize(INNER_W, math.max(listHeight, 1));
    for i = 1, visible do
        rows[i] = CreateRow(timers[i], i);
    end

    local emptyH = 0;
    local moreH = 0;
    if (count == 0) then emptyH = 24; end
    if (count > maxRows) then moreH = 18; end

    emptyLabel:SetVisible(count == 0);
    moreLabel:SetVisible(count > maxRows);
    if (count > maxRows) then
        moreLabel:SetText("+" .. (count - maxRows) .. " more");
        moreLabel:SetPosition(20, ROWS_TOP + listHeight + 2);
    end

    local height = ROWS_TOP + listHeight + emptyH + moreH + 18;
    if (height < MIN_HEIGHT) then height = MIN_HEIGHT; end
    win:SetSize(W, height);
end

local function RefreshCounts()
    local daily = currentManager:GetDailyCount();
    local colour = GetDailyColour(daily);

    activeLabel:SetText("Active: " .. currentManager:GetActiveCount());
    dailyLabel:SetText("Today: " .. daily .. " / " .. DAILY_MAX);
    dailyLabel:SetForeColor(colour);

    dailyFill:SetBackColor(colour);
    local frac = math.min(daily / DAILY_MAX, 1);
    dailyFill:SetSize(math.floor((INNER_W - 2) * frac), 8);
end

-- Called once per second: refreshes remaining times and depleting bars.
local function TickRows(now)
    for _, row in ipairs(rows) do
        PaintRow(row, now);
    end
end

-- Positions every control for the current window width and rebuilds the
-- rows (also used when the width or row count setting changes).
local function ApplyLayout()
    W = settings.windowWidth;
    INNER_W = W - 40;

    startButton:SetSize(INNER_W, 24);
    activeLabel:SetSize(math.floor(INNER_W / 2), 20);
    dailyLabel:SetPosition(20 + math.floor(INNER_W / 2), CONTENT_TOP + 28);
    dailyLabel:SetSize(INNER_W - math.floor(INNER_W / 2), 24);
    dailyTrack:SetSize(INNER_W, 10);
    separator:SetSize(INNER_W, 1);
    emptyLabel:SetSize(INNER_W, 20);
    moreLabel:SetSize(INNER_W, 16);

    RebuildRows();
    RefreshCounts();
end

local function BuildWindow(manager, data)
    currentManager = manager;

    win = Turbine.UI.Lotro.Window();
    win:SetSize(settings.windowWidth, MIN_HEIGHT);
    win:SetPosition(tonumber(data.winX) or 150, tonumber(data.winY) or 150);
    -- the title has to stay short: the LOTRO title bar clips long text
    win:SetText("Lock Timer");
    win:SetVisible(true);

    -- remember the window position a few seconds after it is dragged
    win.PositionChanged = function()
        posDirtyTicks = 4;
    end

    -- the main button: press to start an hour timer
    startButton = Turbine.UI.Lotro.Button();
    startButton:SetParent(win);
    startButton:SetPosition(20, CONTENT_TOP);
    startButton:SetText("Start 1h Timer");
    startButton.Click = function()
        manager:StartTimer(TIMER_DURATION, GetClockStamp());
    end

    -- active timer count
    activeLabel = Turbine.UI.Label();
    activeLabel:SetParent(win);
    activeLabel:SetPosition(20, CONTENT_TOP + 32);
    activeLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    activeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    activeLabel:SetForeColor(Turbine.UI.Color(0.9, 0.9, 0.9));

    -- daily counter, drawn in the gradient colour
    dailyLabel = Turbine.UI.Label();
    dailyLabel:SetParent(win);
    dailyLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro18);
    dailyLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleRight);

    -- daily progress bar (0 .. DAILY_MAX)
    dailyTrack = Turbine.UI.Control();
    dailyTrack:SetParent(win);
    dailyTrack:SetPosition(20, CONTENT_TOP + 56);
    dailyTrack:SetBackColor(Turbine.UI.Color(0.08, 0.08, 0.08));

    dailyFill = Turbine.UI.Control();
    dailyFill:SetParent(dailyTrack);
    dailyFill:SetPosition(1, 1);
    dailyFill:SetSize(0, 8);
    dailyFill:SetBackColor(GetDailyColour(0));

    -- separator between the counters and the timer list
    separator = Turbine.UI.Control();
    separator:SetParent(win);
    separator:SetPosition(20, CONTENT_TOP + 74);
    separator:SetBackColor(Turbine.UI.Color(0.4, 0.4, 0.4));

    -- timer rows
    rowsContainer = Turbine.UI.Control();
    rowsContainer:SetParent(win);
    rowsContainer:SetPosition(20, ROWS_TOP);

    emptyLabel = Turbine.UI.Label();
    emptyLabel:SetParent(win);
    emptyLabel:SetPosition(20, ROWS_TOP + 4);
    emptyLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    emptyLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    emptyLabel:SetForeColor(Turbine.UI.Color(0.55, 0.55, 0.55));
    emptyLabel:SetText("No active timers");

    moreLabel = Turbine.UI.Label();
    moreLabel:SetParent(win);
    moreLabel:SetPosition(20, ROWS_TOP);
    moreLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    moreLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    moreLabel:SetForeColor(Turbine.UI.Color(0.6, 0.6, 0.6));

    -- react to manager events
    manager:RegisterCallback(function(event)
        if (event == "Added" or event == "Removed" or event == "Expired") then
            RebuildRows();
            RefreshCounts();
        elseif (event == "DailyChanged") then
            RefreshCounts();
        end
    end);

    ApplyLayout();
    return win;
end

------------------------------------------------------------------------
-- PERSISTENCE
------------------------------------------------------------------------

local data;

local function LoadData()
    local ok, saved = pcall(
        Turbine.PluginData.Load, Turbine.DataScope.Character, SAVE_KEY);
    if (ok and type(saved) == "table") then
        return saved;
    end
    return { };
end

SaveAll = function()
    if (data == nil) then return; end
    pcall(function()
        if (win ~= nil) then
            data.winX = win:GetLeft();
            data.winY = win:GetTop();
        end
        -- the 4th parameter (an optional completion callback) is passed
        -- explicitly as nil: identical at runtime, but it satisfies API
        -- definition sets that mark it as required
        Turbine.PluginData.Save(Turbine.DataScope.Character, SAVE_KEY, data, nil);
    end);
end

------------------------------------------------------------------------
-- BOOT
------------------------------------------------------------------------

settings = LoadSettings();
W = settings.windowWidth;
INNER_W = W - 40;

data = LoadData();
Manager:Initialize(data);
BuildWindow(Manager, data);

------------------------------------------------------------------------
-- MISSION WATCHER
--
-- The moment you accept a mission, the game writes
-- "New Quest: Mission: <name>" to chat; warping to the mission area
-- later writes "New Quest: <name>" WITHOUT the "Mission:" prefix, which
-- we deliberately ignore. The accept message fires exactly once per
-- mission run, so every occurrence opens the offer window: one click
-- starts a 1h timer named after the mission.
-- The text is matched on the English client; other locales will not
-- trigger the offer.
------------------------------------------------------------------------

-- top-level window => GLOBAL on purpose (see the UI section)
offerWin = nil;
local offerLabel, offerStartButton, offerSkipButton;
local OFFER_W = 280;

local function ShowMissionOffer(name)
    if (offerWin == nil) then
        offerWin = Turbine.UI.Lotro.Window();
        offerWin:SetSize(OFFER_W, 132);
        offerWin:SetText("Mission Started");

        offerLabel = Turbine.UI.Label();
        offerLabel:SetParent(offerWin);
        offerLabel:SetPosition(15, 42);
        offerLabel:SetSize(OFFER_W - 30, 20);
        offerLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
        offerLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
        offerLabel:SetForeColor(Turbine.UI.Color(1, 1, 1));

        offerStartButton = Turbine.UI.Lotro.Button();
        offerStartButton:SetParent(offerWin);
        offerStartButton:SetPosition(15, 74);
        offerStartButton:SetSize(120, 24);
        offerStartButton:SetText("Start 1h Timer");
        offerStartButton.Click = function()
            if (offerWin.missionName ~= nil) then
                Manager:StartTimer(TIMER_DURATION, GetClockStamp(), offerWin.missionName);
                offerWin.missionName = nil;
            end
            offerWin:SetVisible(false);
        end

        offerSkipButton = Turbine.UI.Lotro.Button();
        offerSkipButton:SetParent(offerWin);
        offerSkipButton:SetPosition(145, 74);
        offerSkipButton:SetSize(120, 24);
        offerSkipButton:SetText("Ignore");
        offerSkipButton.Click = function()
            offerWin.missionName = nil;
            offerWin:SetVisible(false);
        end
    end

    offerWin.missionName = name;
    offerLabel:SetText(name);
    -- centre the offer horizontally, near the top of the screen
    offerWin:SetPosition(
        math.floor((Turbine.UI.Display.GetWidth() - OFFER_W) / 2), 100);
    offerWin:SetVisible(true);
    offerWin:Activate();
end

local function HideMissionOffer()
    if (offerWin ~= nil) then
        offerWin.missionName = nil;
        offerWin:SetVisible(false);
    end
end

-- chat handler (the pattern used by LotroPointTracker). Any handler
-- another plugin installed first is chained, so both keep working.
local previousChatHandler = Turbine.Chat.Received;
local function OnChatReceived(sender, args)
    if (previousChatHandler ~= nil) then
        pcall(previousChatHandler, sender, args);
    end
    if (not settings.offerMissions) then return; end
    local message = args and args.Message;
    if (type(message) ~= "string") then return; end

    -- only the "New Quest: Mission: <name>" announcement, on any chat
    -- channel (the quest channel the game uses for it is not documented)
    local name = string.match(message, "^New Quest:%s*Mission:%s*(.-)%s*$");
    if (name == nil or name == "") then return; end

    ShowMissionOffer(name);
end
Turbine.Chat.Received = OnChatReceived;

------------------------------------------------------------------------
-- OPTIONS PANEL (plugin manager -> InstanceLockTimer -> Options)
------------------------------------------------------------------------

local PANEL_W = 520;
local LEFT    = 20;
local COLOR_HEADER = Turbine.UI.Color(1, 0.82, 0.3);
local COLOR_TEXT   = Turbine.UI.Color(0.9, 0.9, 0.9);
local COLOR_HINT   = Turbine.UI.Color(0.65, 0.65, 0.65);

-- GLOBAL on purpose (see the UI section)
optionsPanel = Turbine.UI.Control();
optionsPanel:SetSize(PANEL_W, 420);

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

-- Refreshes the "current reset" line of the options panel.
local function RefreshResetInfo()
    if (optionControls.resetInfo == nil) then return; end
    local now = GetServerTime();
    local nextReset = GetNextReset(now);
    local season = IsWinterTime(nextReset) and "winter time" or "summer time";
    optionControls.resetInfo:SetText("Daily reset at " .. FormatClock(GetResetOffset(nextReset))
        .. " UTC (" .. season .. "), next in " .. FormatDuration(nextReset - now));
end

-- Writes the current settings into the option controls.
local function RefreshOptions()
    local c = optionControls;
    updatingOptions = true;
    c.hour:SetText(string.format("%02d", settings.resetHour));
    c.minute:SetText(string.format("%02d", settings.resetMinute));
    c.autoWinter:SetChecked(settings.autoWinter);
    if (settings.autoWinter) then
        c.winter:SetChecked(IsWinterTime(GetServerTime()));
    else
        c.winter:SetChecked(settings.winterTime);
    end
    c.winter:SetEnabled(not settings.autoWinter);
    c.offer:SetChecked(settings.offerMissions);
    c.width:SetText(tostring(settings.windowWidth));
    c.rows:SetText(tostring(settings.visibleRows));
    updatingOptions = false;
    RefreshResetInfo();
end

-- Changes settings through "change(settings)", keeping the daily counter
-- on the same server day even though the day boundary moves.
local function ChangeSettings(change)
    local now = GetServerTime();
    local oldKey = GetDayKey(now);
    local oldWidth, oldRows = settings.windowWidth, settings.visibleRows;

    change(settings);

    if (Manager.dailyDayKey == oldKey) then
        Manager.dailyDayKey = GetDayKey(now);
        Manager:Save();
    end
    if (settings.windowWidth ~= oldWidth or settings.visibleRows ~= oldRows) then
        ApplyLayout();
    end
    if (not settings.offerMissions) then
        HideMissionOffer();
    end
    SaveSettings();
    RefreshOptions();
end

local function BuildOptionsPanel()
    local y = 10;
    OptionLabel("Instance Lock Timer  v" .. PLUGIN_VERSION, LEFT, y, PANEL_W - 2 * LEFT,
        Turbine.UI.Lotro.Font.TrajanPro20, COLOR_HEADER, Turbine.UI.ContentAlignment.MiddleCenter);

    -- server day reset
    y = y + 40;
    OptionHeader("Server day reset", y);
    y = y + 32;
    OptionLabel("Reset time (UTC, summer):", LEFT, y, 190);
    local hour, x = OptionStepper(LEFT + 195, y, 30, function(dir)
        ChangeSettings(function(s) s.resetHour = (s.resetHour + dir) % 24; end);
    end);
    optionControls.hour = hour;
    OptionLabel(":", x, y, 10, nil, nil, Turbine.UI.ContentAlignment.MiddleCenter);
    optionControls.minute = OptionStepper(x + 14, y, 30, function(dir)
        ChangeSettings(function(s) s.resetMinute = (s.resetMinute + dir * 5) % 60; end);
    end);

    y = y + 28;
    optionControls.winter = OptionCheckBox("Winter time (daily reset 1 hour later)", LEFT, y,
        function(checked)
            ChangeSettings(function(s) s.winterTime = checked; end);
        end);
    y = y + 24;
    optionControls.autoWinter = OptionCheckBox(
        "Detect winter time automatically (US daylight saving dates)", LEFT, y,
        function(checked)
            ChangeSettings(function(s)
                -- keep the manual box on whatever was in effect
                if (not checked) then s.winterTime = IsWinterTime(GetServerTime()); end
                s.autoWinter = checked;
            end);
        end);
    y = y + 26;
    optionControls.resetInfo = OptionLabel("", LEFT, y, PANEL_W - 2 * LEFT,
        Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);

    -- missions
    y = y + 34;
    OptionHeader("Missions", y);
    y = y + 32;
    optionControls.offer = OptionCheckBox(
        "Offer a 1h timer when a mission is accepted (English client)", LEFT, y,
        function(checked)
            ChangeSettings(function(s) s.offerMissions = checked; end);
        end);

    -- main window
    y = y + 36;
    OptionHeader("Main window", y);
    y = y + 32;
    OptionLabel("Width (" .. MIN_WIDTH .. "-" .. MAX_WIDTH .. " px):", LEFT, y, 190);
    optionControls.width = OptionStepper(LEFT + 195, y, 40, function(dir)
        ChangeSettings(function(s)
            s.windowWidth = Clamp(s.windowWidth + dir * WIDTH_STEP, MIN_WIDTH, MAX_WIDTH);
        end);
    end);
    y = y + 26;
    OptionLabel("Visible timer rows (" .. MIN_ROWS .. "-" .. MAX_ROWS .. "):", LEFT, y, 190);
    optionControls.rows = OptionStepper(LEFT + 195, y, 40, function(dir)
        ChangeSettings(function(s)
            s.visibleRows = Clamp(s.visibleRows + dir, MIN_ROWS, MAX_ROWS);
        end);
    end);
    y = y + 22;
    OptionLabel("The height follows the number of timers, up to the visible rows.",
        LEFT, y, PANEL_W - 2 * LEFT, Turbine.UI.Lotro.Font.Verdana12, COLOR_HINT);

    -- defaults
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

------------------------------------------------------------------------
-- MASTER CLOCK
--
-- The standard LOTRO update loop (an invisible control with
-- SetWantsUpdates) drives everything, throttled to one pass per second.
-- GLOBAL on purpose - see the comment at the top of the UI section.
------------------------------------------------------------------------

tickControl = Turbine.UI.Control();
local lastSecond = -1;
function tickControl:Update()
    local now = GetServerTime();
    if (now == lastSecond) then return; end
    lastSecond = now;

    -- save the window position a few seconds after a drag
    if (posDirtyTicks > 0) then
        posDirtyTicks = posDirtyTicks - 1;
        if (posDirtyTicks == 0) then
            pcall(SaveAll);
        end
    end
    Manager:Update(now);
    TickRows(now);
    if (optionsPanel:IsDisplayed()) then
        pcall(RefreshOptions);
    end
end
tickControl:SetWantsUpdates(true);

------------------------------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------------------------------

local command = Turbine.ShellCommand();

function command:GetHelp()
    return "Usage: /ilt show | /ilt options | /ilt add <minutes> | /ilt resetdaily | /ilt help";
end

function command:GetShortHelp()
    return "Controls InstanceLockTimer";
end

function command:Execute(commandName, args)
    local text = string.lower(args or "");
    local word, rest = string.match(text, "^%s*(%S+)%s*(.-)%s*$");
    if (word == nil) then
        word = "";
        rest = "";
    end

    if (word == "" or word == "show") then
        win:SetVisible(true);
        win:Activate();
    elseif (word == "options" or word == "settings") then
        local manager = Turbine.LotroPluginManager;
        if (thisPlugin ~= nil and manager ~= nil and type(manager.ShowOptions) == "function") then
            pcall(manager.ShowOptions, thisPlugin);
        else
            Turbine.Shell.WriteLine("Open the plugin manager and select InstanceLockTimer -> Options.");
        end
    elseif (word == "add") then
        local minutes = tonumber(rest);
        if (minutes == nil or minutes <= 0 or minutes > 1440) then
            Turbine.Shell.WriteLine("Usage: /ilt add <minutes>  (1-1440)");
        else
            Manager:StartTimer(minutes * 60, GetClockStamp());
            Turbine.Shell.WriteLine("Started a " .. minutes .. " minute timer.");
        end
    elseif (word == "resetdaily") then
        Manager:ResetDaily();
        Turbine.Shell.WriteLine("Daily counter reset.");
    elseif (word == "help") then
        Turbine.Shell.WriteLine(self:GetHelp());
    else
        Turbine.Shell.WriteLine("Unknown argument. " .. self:GetHelp());
    end
end

-- AddCommand returns how many names were registered (0 if taken)
for _, name in ipairs({ "InstanceLockTimer", "ilt" }) do
    local ok, registered = pcall(Turbine.Shell.AddCommand, name, command);
    if (not ok or registered == false or registered == 0) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": /" .. name .. " could not be registered.");
    end
end

------------------------------------------------------------------------
-- CLEANUP ON PLUGIN UNLOAD
------------------------------------------------------------------------

local unloaded = false;
local function OnUnload()
    if (unloaded) then return; end
    unloaded = true;
    pcall(SaveAll);
    pcall(SaveSettings);
    pcall(Turbine.Shell.RemoveCommand, command);
    if (Turbine.Chat.Received == OnChatReceived) then
        Turbine.Chat.Received = previousChatHandler;
    end
    tickControl:SetWantsUpdates(false);
    HideMissionOffer();
    win:SetVisible(false);
end

if (thisPlugin ~= nil) then
    thisPlugin.Unload = OnUnload;
end

Turbine.Shell.WriteLine(
    PLUGIN_NAME .. " v" .. PLUGIN_VERSION .. " loaded. Type /ilt help for commands.");
