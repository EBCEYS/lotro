--[[=========================================================================

    CharacterStats -- Commands.lua
    /cstats and /characterstats shell command.

=========================================================================]]

CS.Commands = { };

local HELP = table.concat({
    "CharacterStats commands (/cstats or /characterstats):",
    "  /cstats [toggle]       show / hide the stats window",
    "  /cstats show | hide    show or hide the stats window",
    "  /cstats refresh        re-read all stats",
    "  /cstats icon [show|hide]  toggle / show / hide the screen icon",
    "  /cstats expand | collapse  expand or collapse all groups",
    "  /cstats share [channel]    list channels or choose the share channel",
    "  /cstats maxlen <" .. CS.MAXLEN_MIN .. "-" .. CS.MAXLEN_MAX .. ">  share line length",
    "  /cstats print          print all share pages to your chat window",
    "  /cstats reset          reset window positions and sizes",
    "  /cstats options        open the plugin manager options",
}, "\n");

local function ChannelList()
    local ids = { };
    for _, ch in ipairs(CS.CHANNELS) do table.insert(ids, ch.id); end
    return table.concat(ids, ", ");
end

-- Resets positions / sizes to the defaults and saves.
local function ResetLayout()
    local d = CS.Settings.Defaults();
    local s = CS.settings;
    s.mainX, s.mainY, s.mainW, s.mainH = d.mainX, d.mainY, d.mainW, d.mainH;
    s.iconX, s.iconY = d.iconX, d.iconY;
    CS.mainWindow:SetSize(s.mainW, s.mainH);
    CS.mainWindow:SetPosition(s.mainX, s.mainY);
    CS.iconWindow:SetPosition(s.iconX, s.iconY);
    pcall(CS.Settings.Save);
end

CS.command = Turbine.ShellCommand();

function CS.command:GetHelp()
    return HELP;
end

function CS.command:GetShortHelp()
    return "Shows your character stats window";
end

function CS.command:Execute(commandName, args)
    local text = string.lower(args or "");
    local word, rest = string.match(text, "^%s*(%S*)%s*(.-)%s*$");
    word = word or "";
    rest = rest or "";

    if (word == "" or word == "toggle") then
        CS.ToggleMain();
    elseif (word == "show") then
        CS.ShowMain(true);
    elseif (word == "hide") then
        CS.ShowMain(false);
    elseif (word == "refresh") then
        CS.MarkDirty(true);
    elseif (word == "icon") then
        if (rest == "show") then
            CS.IconWindow.SetShown(true);
        elseif (rest == "hide") then
            CS.IconWindow.SetShown(false);
        else
            CS.IconWindow.SetShown(not CS.iconWindow:IsVisible());
        end
    elseif (word == "expand") then
        CS.ShowMain(true);
        CS.StatsWindow.ExpandAll();
    elseif (word == "collapse") then
        CS.ShowMain(true);
        CS.StatsWindow.CollapseAll();
    elseif (word == "share") then
        if (rest == "") then
            Turbine.Shell.WriteLine("CharacterStats: share channels: " .. ChannelList()
                .. " (current: " .. CS.settings.channel .. ")");
        elseif (CS.SharePanel.SetChannel(rest)) then
            CS.ShowMain(true);
            Turbine.Shell.WriteLine("CharacterStats: sharing to " .. rest .. ".");
        else
            Turbine.Shell.WriteLine("CharacterStats: unknown channel. Use one of: " .. ChannelList());
        end
    elseif (word == "maxlen") then
        local n = tonumber(rest);
        if (n == nil or n < CS.MAXLEN_MIN or n > CS.MAXLEN_MAX) then
            Turbine.Shell.WriteLine("Usage: /cstats maxlen <" .. CS.MAXLEN_MIN .. "-" .. CS.MAXLEN_MAX .. ">");
        else
            CS.OptionsPanel.SetMaxLen(n);
            Turbine.Shell.WriteLine("CharacterStats: share line length " .. CS.settings.maxLen .. ".");
        end
    elseif (word == "print") then
        CS.SharePanel.PrintAll();
    elseif (word == "reset") then
        ResetLayout();
        Turbine.Shell.WriteLine("CharacterStats: window positions reset.");
    elseif (word == "options" or word == "settings") then
        CS.OpenOptions();
    else
        Turbine.Shell.WriteLine(self:GetHelp());
    end
end

function CS.Commands.Register()
    -- AddCommand returns how many names were registered (0 if taken)
    for _, name in ipairs({ "cstats", "characterstats" }) do
        local ok, registered = pcall(Turbine.Shell.AddCommand, name, CS.command);
        if (not ok or registered == false or registered == 0) then
            Turbine.Shell.WriteLine(CS.PLUGIN_NAME .. ": /" .. name .. " could not be registered.");
        end
    end
end
