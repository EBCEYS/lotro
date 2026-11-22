--[[=========================================================================

    CharacterStats -- Ticker.lua
    The update loop: debounced saves, value polling and throttled
    refreshes / row relayouts. Game events only set dirty flags; the
    work happens here. The loop sleeps while the main window is hidden
    and no save is pending; Wake() restarts it.

=========================================================================]]

CS.Ticker = { };

local lastRefresh, lastPoll = 0, 0;
local awake = false;

function CS.Ticker.Wake()
    if (CS.ticker == nil or CS.unloaded or awake) then return; end
    awake = true;
    CS.ticker:SetWantsUpdates(true);
end

local function Sleep()
    awake = false;
    CS.ticker:SetWantsUpdates(false);
end

function CS.Ticker.Start()
    CS.ticker = Turbine.UI.Control();       -- kept alive by the CS global
    function CS.ticker:Update()
        local now = Turbine.Engine.GetGameTime();
        if (CS.saveAt ~= nil and now >= CS.saveAt) then
            CS.saveAt = nil;
            pcall(CS.Settings.Save);
        end
        if (not CS.mainWindow:IsVisible()) then
            if (CS.saveAt == nil) then Sleep(); end
            return;
        end
        if (now - lastRefresh < CS.REFRESH_MIN_INTERVAL) then return; end

        -- window resized: relayout the rows at most 4x per second
        if (CS.dirty.layout) then
            lastRefresh = now;
            local pending = (CS.dirty.full or CS.dirty.values);
            local ok, err = pcall(CS.StatsWindow.RelayoutRows, not pending);
            if (not ok) then
                CS.dirty.layout = false;
                CS.ReportError(err);
            end
            if (not pending) then return; end
            CS.dirty.full = true;       -- the refresh below rebuilds the list
        end

        -- stats have no change events (buffs, regen...): poll them
        if (now - lastPoll >= CS.POLL_INTERVAL) then
            lastPoll = now;
            CS.dirty.values = true;
        end
        if (CS.dirty.full or CS.dirty.values) then
            lastRefresh = now;
            local ok, err = pcall(CS.StatsWindow.Refresh);
            if (not ok) then
                CS.dirty.full = false;
                CS.dirty.values = false;
                CS.ReportError(err);
            end
        end
    end
    awake = false;
    CS.Ticker.Wake();
end
