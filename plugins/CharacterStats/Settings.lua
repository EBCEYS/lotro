--[[=========================================================================

    CharacterStats -- Settings.lua
    Defaults, load / validate / save (Character scope), debounced save,
    collapse state of the groups.

=========================================================================]]

CS.Settings = { };

local function DisplayWidth()
    local ok, w = pcall(Turbine.UI.Display.GetWidth);
    if (ok and type(w) == "number" and w > 0) then return w; end
    return 1024;
end

local function DisplayHeight()
    local ok, h = pcall(Turbine.UI.Display.GetHeight);
    if (ok and type(h) == "number" and h > 0) then return h; end
    return 768;
end
CS.Settings.DisplayWidth  = DisplayWidth;
CS.Settings.DisplayHeight = DisplayHeight;

function CS.Settings.Defaults()
    return {
        version     = CS.SAVE_VERSION,
        mainX       = math.floor((DisplayWidth() - CS.MAIN_DEFAULT_W) / 2),
        mainY       = 120,
        mainW       = CS.MAIN_DEFAULT_W,
        mainH       = CS.MAIN_DEFAULT_H,
        mainVisible = false,
        iconX       = DisplayWidth() - 120,
        iconY       = 220,
        iconVisible = true,
        iconLocked  = false,
        hideEmpty   = false,
        showIcons   = true,
        nativeItems = false,
        channel     = "say",
        page        = 1,
        maxLen      = CS.MAXLEN_DEFAULT,
        collapsed   = { },
    };
end

-- PluginData may hand numbers back as strings: accept both.
local function ReadNumber(value, default)
    local n = tonumber(value);
    if (n == nil) then return default; end
    return math.floor(n);
end

local function ReadBoolean(value, default)
    if (type(value) == "boolean") then return value; end
    if (value == "true") then return true; end
    if (value == "false") then return false; end
    return default;
end

function CS.Settings.Load()
    local ok, saved = pcall(Turbine.PluginData.Load, Turbine.DataScope.Character, CS.SAVE_KEY);
    if (not ok or type(saved) ~= "table") then saved = { }; end

    local d = CS.Settings.Defaults();
    local s = { };
    for key, default in pairs(d) do
        if (type(default) == "number") then
            s[key] = ReadNumber(saved[key], default);
        elseif (type(default) == "boolean") then
            s[key] = ReadBoolean(saved[key], default);
        elseif (type(default) == "string") then
            s[key] = (type(saved[key]) == "string") and saved[key] or default;
        end
    end

    -- before version 2 item descriptions defaulted to collapsed: forget
    -- those item states so the descriptions show
    local savedVersion = tonumber(saved.version) or 0;
    s.collapsed = { };
    if (type(saved.collapsed) == "table") then
        for id, value in pairs(saved.collapsed) do
            local b = ReadBoolean(value, nil);
            if (type(id) == "string" and b ~= nil) then
                if (savedVersion >= 2 or string.sub(id, 1, 5) ~= "item.") then s.collapsed[id] = b; end
            end
        end
    end

    -- keep everything in range (and windows on screen after a resolution change)
    local dw, dh = DisplayWidth(), DisplayHeight();
    s.version = CS.SAVE_VERSION;
    s.maxLen  = CS.Util.Clamp(s.maxLen, CS.MAXLEN_MIN, CS.MAXLEN_MAX);
    s.mainW   = CS.Util.Clamp(s.mainW, CS.MAIN_MIN_W, CS.MAIN_MAX_W);
    s.mainH   = CS.Util.Clamp(s.mainH, CS.MAIN_MIN_H, math.max(CS.MAIN_MIN_H, dh));
    s.mainX   = CS.Util.Clamp(s.mainX, 0, math.max(0, dw - 40));
    s.mainY   = CS.Util.Clamp(s.mainY, 0, math.max(0, dh - 40));
    s.iconX   = CS.Util.Clamp(s.iconX, 0, math.max(0, dw - 40));
    s.iconY   = CS.Util.Clamp(s.iconY, 0, math.max(0, dh - 40));
    if (s.page < 1) then s.page = 1; end
    if (CS.Util.FindChannel(s.channel) == nil) then s.channel = "say"; end
    return s;
end

function CS.Settings.Save()
    local s = CS.settings;
    if (s == nil) then return; end
    if (CS.mainWindow ~= nil) then
        s.mainX = math.floor(CS.mainWindow:GetLeft());
        s.mainY = math.floor(CS.mainWindow:GetTop());
        s.mainW = math.floor(CS.mainWindow:GetWidth());
        s.mainH = math.floor(CS.mainWindow:GetHeight());
    end
    if (CS.iconWindow ~= nil) then
        s.iconX = math.floor(CS.iconWindow:GetLeft());
        s.iconY = math.floor(CS.iconWindow:GetTop());
    end
    pcall(Turbine.PluginData.Save, Turbine.DataScope.Character, CS.SAVE_KEY, s, nil);
end

-- The ticker saves CS.SAVE_DEBOUNCE seconds after the last call.
function CS.Settings.SaveSoon()
    CS.saveAt = Turbine.Engine.GetGameTime() + CS.SAVE_DEBOUNCE;
    if (CS.Ticker ~= nil) then CS.Ticker.Wake(); end
end

------------------------------------------------------------------------
-- COLLAPSE STATE
------------------------------------------------------------------------

function CS.Settings.IsCollapsed(id)
    local saved = CS.settings.collapsed[id];
    if (saved ~= nil) then return saved; end
    if (CS.DEFAULT_COLLAPSED[id] ~= nil) then return CS.DEFAULT_COLLAPSED[id]; end
    return false;
end

function CS.Settings.SetCollapsed(id, collapsed)
    CS.settings.collapsed[id] = (collapsed == true);
    CS.Settings.SaveSoon();
end
