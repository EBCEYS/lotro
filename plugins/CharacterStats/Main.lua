--[[=========================================================================

    CharacterStats v1.0.0  --  The Lord of the Rings Online plugin
    ----------------------------------------------------------------

    * A window with your character's current stats in collapsible groups:
      Characteristics (general, vitals, main stats, offence, defence,
      mitigations, resistances, class, crafting) and Equipment (every
      equipped item with its name, description and native tooltip).
    * Updates when you equip / unequip items or level up, and once per
      second while the window is open (buffs, regen, ...).
    * A small "CS" icon on screen: left click toggles the window, left
      drag moves it, right click opens a menu (show/hide, refresh, ...).
    * Share your stats to chat: choose a channel, check the preview and
      click the "Send" slot (plugins cannot post to chat on their own).
    * Everything (positions, sizes, collapsed groups, options) is saved
      per character.

    INSTALLATION
    ------------
    Copy the CharacterStats folder into
        Documents\The Lord of the Rings Online\Plugins\
    so that the files end up as ...\Plugins\CharacterStats\Main.lua and
    ...\Plugins\CharacterStats\CharacterStats.plugin, then in game:
        /plugins load CharacterStats

    COMMANDS: /cstats help

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

-- the only global of the plugin: every module, window and control
-- hangs off it (top-level windows must stay referenced by a global)
CS = { };

import "CharacterStats.Constants";
import "CharacterStats.Util";
import "CharacterStats.Settings";
import "CharacterStats.EventHub";
import "CharacterStats.StatsModel";
import "CharacterStats.ShareText";
import "CharacterStats.StatsWindow";
import "CharacterStats.SharePanel";
import "CharacterStats.IconWindow";
import "CharacterStats.OptionsPanel";
import "CharacterStats.Commands";
import "CharacterStats.Ticker";

------------------------------------------------------------------------
-- CLEANUP ON PLUGIN UNLOAD (idempotent)
------------------------------------------------------------------------

function CS.OnUnload()
    if (CS.unloaded) then return; end
    -- set first: hiding the windows below must not save mainVisible = false
    CS.unloaded = true;
    pcall(CS.Settings.Save);
    pcall(CS.EventHub.RemoveAll);
    pcall(Turbine.Shell.RemoveCommand, CS.command);
    pcall(function() CS.ticker:SetWantsUpdates(false); end);
    pcall(function() CS.iconWindow:SetWantsKeyEvents(false); end);
    pcall(function() CS.iconMenu:Close(); end);
    pcall(function() if (CS.channelMenu ~= nil) then CS.channelMenu:Close(); end end);
    pcall(function() CS.mainWindow:SetVisible(false); end);
    pcall(function() CS.iconWindow:SetVisible(false); end);
end

------------------------------------------------------------------------
-- BOOT
------------------------------------------------------------------------

CS.thisPlugin = plugin or (Plugins and Plugins[CS.PLUGIN_NAME]);
CS.settings   = CS.Settings.Load();
CS.player     = Turbine.Gameplay.LocalPlayer.GetInstance();
CS.Util.ResolveSlots();

CS.StatsWindow.Build();            -- CS.mainWindow (+ share panel)
CS.IconWindow.Build();             -- CS.iconWindow, CS.iconMenu
CS.OptionsPanel.Build();           -- CS.optionsPanel
CS.WireGameEvents();
CS.Commands.Register();
CS.Ticker.Start();
CS.MarkDirty(true);                -- first full refresh on the next frame

if (CS.thisPlugin ~= nil) then
    CS.thisPlugin.Unload = CS.OnUnload;
    CS.thisPlugin.GetOptionsPanel = function()
        CS.OptionsPanel.Refresh();
        return CS.optionsPanel;
    end
end

Turbine.Shell.WriteLine(CS.PLUGIN_NAME .. " v" .. CS.PLUGIN_VERSION
    .. " loaded. Type /cstats help for commands.");
