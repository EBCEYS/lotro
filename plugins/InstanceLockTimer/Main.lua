--[[=========================================================================

    InstanceLockTimer v1.0  --  The Lord of the Rings Online plugin
    -------------------------------------------------------------------

    * Press the button to start a 1-hour instance lock timer.
    * An "Active" counter shows how many timers are running; it decreases
      automatically whenever a timer expires.
    * A "Today" counter counts how many timers you started during the
      current server day. It is drawn in a gradient colour, green at 0
      up to red at 100, with a matching progress bar.
    * The daily counter resets at the server day change (07:00 UTC).
      Active timers are never reset by the day change - they keep
      counting down until they expire. Removing a timer with its "X"
      on the same day you started it also gives that start back to
      the daily counter (it never goes below 0).
    * Click the name of a timer to rename it: type the new name and
      press Enter (or click anywhere else) to confirm, Escape to cancel.
    * Everything is saved per character: active timers survive logout
      and /ui reload (they keep running in real time), and the daily
      counter survives relogging. If the server day changed while you
      were offline, the daily counter resets on load.

    INSTALLATION
    ------------
    1. Create this folder:
       Documents\The Lord of the Rings Online\Plugins\InstanceLockTimer\
    2. Save this file as Main.lua inside that folder.
    3. In the SAME folder create a text file "InstanceLockTimer.plugin"
       with EXACTLY this content:
         <?xml version="1.0" encoding="utf-8"?>
         <Plugin>
           <Information>
             <Name>InstanceLockTimer</Name>
             <Author>Ebceys</Author>
             <Version>1.0</Version>
             <Description>One-hour instance lock timers with per-day usage counter.</Description>
           </Information>
           <Package>InstanceLockTimer.Main</Package>
           <Configuration Apartment="InstanceLockTimer" />
         </Plugin>
       (The <Package> entry is the code entrypoint: it must be the dot path
       from the Plugins root to this file minus the .lua extension. If you
       install under an author folder instead, e.g.
       Plugins\Ebceys\InstanceLockTimer\, the entry must be
       <Package>Ebceys.InstanceLockTimer.Main</Package>.)
    4. In game:  /plugins load InstanceLockTimer

    COMMANDS
    --------
    /ilt show           show the main window
    /ilt add <minutes>  start a custom-length timer (handy for testing:
                        "/ilt add 1" starts a 1-minute test timer)
    /ilt resetdaily     reset the daily counter
    /ilt help           command overview

    TUNING
    ------
    All tweakable values are in the CONFIGURATION section below.

=========================================================================]]

import "Turbine";
import "Turbine.UI";
import "Turbine.UI.Lotro";

------------------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------------------

local PLUGIN_NAME        = "InstanceLockTimer";
local PLUGIN_VERSION     = "1.0";

local TIMER_DURATION     = 3600;  -- length of a standard timer, seconds (1 hour)
local DAY_RESET_UTC_HOUR = 7;     -- hour (UTC) when the daily counter resets
local DAILY_MAX          = 100;   -- daily gradient: green at 0 -> red at DAILY_MAX

local MAX_VISIBLE_ROWS   = 8;     -- timer rows shown before a "+N more" line appears
local SAVE_KEY           = "InstanceLockTimerData";

local W                  = 300;   -- window width
local INNER_W            = W - 40; -- width of the content area
local ROW_H              = 26;     -- height of one timer row
local ROWS_TOP           = 120;    -- y position of the timer list
local MIN_HEIGHT         = 176;
local CONTENT_TOP        = 34;     -- in a Lotro.Window, child coordinates
                                   -- start at the very top edge of the
                                   -- window: the title bar covers roughly
                                   -- the first 30px, so all content must
                                   -- begin below it

local DAY_SECONDS        = 86400;
local RESET_OFFSET       = DAY_RESET_UTC_HOUR * 3600;

------------------------------------------------------------------------
-- FORWARD DECLARATIONS
------------------------------------------------------------------------

local SaveAll;          -- defined in the PERSISTENCE section

------------------------------------------------------------------------
-- UTILITIES
------------------------------------------------------------------------

-- Current game server time in seconds (GMT based). If the engine clock is
-- not available on this client, fall back to the local clock (durations
-- stay correct; only the UTC day boundary would follow the client clock).
local function GetServerTime()
    if (type(Turbine.Engine.GetServerTime) == "function") then
        return Turbine.Engine.GetServerTime();
    end
    return Turbine.Engine.GetLocalTime();
end

--[[
    Stable key for the current server day. The key changes exactly when
    the server day flips (DAY_RESET_UTC_HOUR UTC). Two moments share a key
    if and only if they belong to the same server day.
]]
local function GetDayKey(serverTime)
    return math.floor((serverTime - RESET_OFFSET) / DAY_SECONDS);
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

-- Starts a new timer of the given duration (seconds) and counts its start
-- towards the current server day.
function Manager:StartTimer(duration, startedAtText)
    local now = GetServerTime();
    local rec = {
        expiresAt     = now + duration,
        startedAt     = now,
        duration      = duration,
        startedAtText = startedAtText or "",
        name          = "Timer " .. (#self.timers + 1),
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

-- Resets the daily counter when the server day (DAY_RESET_UTC_HOUR UTC)
-- changes. Active timers are deliberately left untouched.
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
    if (self:CheckDayChange()) then
        self:Save();
    end
    local expired = false;
    for i = #self.timers, 1, -1 do
        if (now >= self.timers[i].expiresAt) then
            local rec = table.remove(self.timers, i);
            Notify("Expired", rec);
            expired = true;
        end
    end
    if (expired) then
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
            if (type(rec) == "table" and type(rec.expiresAt) == "number") then
                if (type(rec.duration) ~= "number") then rec.duration = TIMER_DURATION; end
                if (type(rec.startedAtText) ~= "string") then rec.startedAtText = ""; end
                if (type(rec.name) ~= "string" or rec.name == "") then rec.name = "Timer " .. i; end
                table.insert(self.timers, rec);
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

    self.dailyDayKey = data.dailyDayKey;
    self.dailyCount = type(data.dailyCount) == "number" and data.dailyCount or 0;

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

-- "win" and "tickControl" (in the BOOT section below) are GLOBALS on
-- purpose: LOTRO garbage-collects any control whose last Lua reference is
-- a local that goes out of scope when the script finishes loading. That
-- silently kills the update loop (frozen text, bars that never move,
-- timers that only expire on the next /plugins load). Long-running
-- production plugins keep their top-level controls in globals for this
-- reason. Everything else hangs off "win", and the engine keeps the
-- child controls of a live window alive.
local startButton, activeLabel, dailyLabel, dailyTrack, dailyFill;
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
    -- LOTRO delivers key presses as "Action" codes; there is no KeyCode
    -- enum. 162 = Enter, 145 = Escape (the codes used by the major UI
    -- plugins such as CombatAnalysis).
    editor.KeyDown = function(_, args)
        if (args.Action == 162) then
            CloseEditor(row, true);
        elseif (args.Action == 145) then
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
    row.time:SetForeColor(Turbine.UI.Color(1, 1, 1));

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

    -- paint the initial remaining time and bar right away, so the row is
    -- correct even before the first tick
    local now = GetServerTime();
    row.time:SetText(FormatDuration(rec.expiresAt - now));
    local frac0 = math.min(math.max((rec.expiresAt - now) / rec.duration, 0), 1);
    row.fill:SetSize(math.floor(INNER_W * frac0), ROW_H - 3);

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
    local timers = currentManager:GetTimers();
    local count = #timers;
    local visible = math.min(count, MAX_VISIBLE_ROWS);
    local listHeight = visible * ROW_H;

    for i = 1, visible do
        rows[i] = CreateRow(timers[i], i);
    end

    local emptyH = 0;
    local moreH = 0;
    if (count == 0) then emptyH = 24; end
    if (count > MAX_VISIBLE_ROWS) then moreH = 18; end

    rowsContainer:SetSize(INNER_W, listHeight);
    emptyLabel:SetVisible(count == 0);
    moreLabel:SetVisible(count > MAX_VISIBLE_ROWS);
    if (count > MAX_VISIBLE_ROWS) then
        moreLabel:SetText("+" .. (count - MAX_VISIBLE_ROWS) .. " more");
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
end

local function BuildWindow(manager, data)
    currentManager = manager;

    win = Turbine.UI.Lotro.Window();
    win:SetSize(W, MIN_HEIGHT);
    win:SetPosition(data.winX or 150, data.winY or 150);
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
    startButton:SetSize(INNER_W, 24);
    startButton:SetText("Start 1h Timer");
    startButton.Click = function()
        manager:StartTimer(TIMER_DURATION, GetClockStamp());
    end

    -- active timer count
    activeLabel = Turbine.UI.Label();
    activeLabel:SetParent(win);
    activeLabel:SetPosition(20, CONTENT_TOP + 32);
    activeLabel:SetSize(130, 20);
    activeLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    activeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    activeLabel:SetForeColor(Turbine.UI.Color(0.9, 0.9, 0.9));

    -- daily counter, drawn in the gradient colour
    dailyLabel = Turbine.UI.Label();
    dailyLabel:SetParent(win);
    dailyLabel:SetPosition(150, CONTENT_TOP + 28);
    dailyLabel:SetSize(INNER_W - 130, 24);
    dailyLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro18);
    dailyLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleRight);

    -- daily progress bar (0 .. DAILY_MAX)
    dailyTrack = Turbine.UI.Control();
    dailyTrack:SetParent(win);
    dailyTrack:SetPosition(20, CONTENT_TOP + 56);
    dailyTrack:SetSize(INNER_W, 10);
    dailyTrack:SetBackColor(Turbine.UI.Color(0.08, 0.08, 0.08));

    dailyFill = Turbine.UI.Control();
    dailyFill:SetParent(dailyTrack);
    dailyFill:SetPosition(1, 1);
    dailyFill:SetSize(0, 8);
    dailyFill:SetBackColor(GetDailyColour(0));

    -- separator between the counters and the timer list
    local separator = Turbine.UI.Control();
    separator:SetParent(win);
    separator:SetPosition(20, CONTENT_TOP + 74);
    separator:SetSize(INNER_W, 1);
    separator:SetBackColor(Turbine.UI.Color(0.4, 0.4, 0.4));

    -- timer rows
    rowsContainer = Turbine.UI.Control();
    rowsContainer:SetParent(win);
    rowsContainer:SetPosition(20, ROWS_TOP);
    rowsContainer:SetSize(INNER_W, MAX_VISIBLE_ROWS * ROW_H);

    emptyLabel = Turbine.UI.Label();
    emptyLabel:SetParent(win);
    emptyLabel:SetPosition(20, ROWS_TOP + 4);
    emptyLabel:SetSize(INNER_W, 20);
    emptyLabel:SetFont(Turbine.UI.Lotro.Font.TrajanPro14);
    emptyLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    emptyLabel:SetForeColor(Turbine.UI.Color(0.55, 0.55, 0.55));
    emptyLabel:SetText("No active timers");

    moreLabel = Turbine.UI.Label();
    moreLabel:SetParent(win);
    moreLabel:SetPosition(20, ROWS_TOP);
    moreLabel:SetSize(INNER_W, 16);
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

    RebuildRows();
    RefreshCounts();
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

data = LoadData();
Manager:Initialize(data);
BuildWindow(Manager, data);

-- master clock: the standard LOTRO update loop (an invisible control with
-- SetWantsUpdates, the pattern used by the actively maintained plugins)
-- drives everything, throttled to one pass per second.
-- GLOBAL on purpose - see the comment at the top of the UI section. A
-- local update control gets collected after loading and its Update stops
-- firing without any error message.
tickControl = Turbine.UI.Control();
local lastSecond = -1;
function tickControl:Update()
    local now = GetServerTime();
    local sec = math.floor(now);
    if (sec == lastSecond) then return; end
    lastSecond = sec;

    -- save the window position a few seconds after a drag
    if (posDirtyTicks > 0) then
        posDirtyTicks = posDirtyTicks - 1;
        if (posDirtyTicks == 0) then
            pcall(SaveAll);
        end
    end
    Manager:Update(now);
    TickRows(now);
end;
tickControl:SetWantsUpdates(true);

------------------------------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------------------------------

local command = Turbine.ShellCommand();

function command:GetHelp()
    return "Usage: /ilt show | /ilt add <minutes> | /ilt resetdaily | /ilt help";
end

function command:GetShortHelp()
    return "Controls InstanceLockTimer";
end

function command:Execute(commandName, args)
    local text = string.lower((args or ""));
    local word, rest = string.match(text, "(%S+)%s+(.-)$");
    if (word == nil) then
        word = text;
        rest = "";
    end

    if (word == "" or word == "show") then
        win:SetVisible(true);
    elseif (word == "add") then
        local minutes = tonumber(rest);
        if (minutes == nil or minutes <= 0 or minutes > 1440) then
            Turbine.Shell.WriteLine("Usage: /ilt add <minutes>");
        else
            Manager:StartTimer(minutes * 60, GetClockStamp());
            Turbine.Shell.WriteLine("Started a " .. minutes .. " minute timer.");
        end
    elseif (word == "resetdaily") then
        Manager:ResetDaily();
        Turbine.Shell.WriteLine("Daily counter reset.");
    elseif (word == "help") then
        Turbine.Shell.WriteLine(command:GetHelp());
    else
        Turbine.Shell.WriteLine("Unknown argument. " .. command:GetHelp());
    end
end

-- each alias is registered as its own command
for _, name in ipairs({ "InstanceLockTimer", "ilt" }) do
    local ok = pcall(Turbine.Shell.AddCommand, name, command);
    if (not ok) then
        Turbine.Shell.WriteLine(PLUGIN_NAME .. ": /" .. name .. " could not be registered.");
    end
end

------------------------------------------------------------------------
-- CLEANUP ON PLUGIN UNLOAD
------------------------------------------------------------------------

local function OnUnload()
    pcall(SaveAll);
    pcall(Turbine.Shell.RemoveCommand, command);
end

-- Two unload hooks, both used by long-running LOTRO plugins in production
-- (Turbine.Plugin.Unload and Plugins[name].Unload). They may both fire,
-- which is harmless - OnUnload only saves and unregisters the command.

function Turbine.Plugin.Unload()
    OnUnload();
end

local plugin = Plugins and Plugins[PLUGIN_NAME];
if (plugin ~= nil) then
    plugin.Unload = OnUnload;
end

Turbine.Shell.WriteLine(
    PLUGIN_NAME .. " v" .. PLUGIN_VERSION .. " loaded. Type /ilt help for commands.");