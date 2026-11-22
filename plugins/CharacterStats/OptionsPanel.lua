--[[=========================================================================

    CharacterStats -- OptionsPanel.lua
    Panel shown in the plugin manager (CharacterStats -> Options).

=========================================================================]]

CS.OptionsPanel = { };

local PANEL_W = 340;
local LEFT    = 10;
local controls = { };
local syncing = false;

local function OptionLabel(text, x, y, w, font, colour, align)
    local label = Turbine.UI.Label();
    label:SetParent(CS.optionsPanel);
    label:SetPosition(x, y);
    label:SetSize(w, 20);
    label:SetFont(font or CS.FONT_OPTION);
    label:SetForeColor(colour or CS.COL_LABEL);
    label:SetTextAlignment(align or Turbine.UI.ContentAlignment.MiddleLeft);
    label:SetText(text);
    return label;
end

local function OptionCheckBox(text, y, onChanged)
    local cb = Turbine.UI.Lotro.CheckBox();
    cb:SetParent(CS.optionsPanel);
    cb:SetPosition(LEFT, y);
    cb:SetSize(PANEL_W - 2 * LEFT, 20);
    cb:SetFont(CS.FONT_OPTION);
    cb:SetForeColor(CS.COL_LABEL);
    cb:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    cb:SetText(" " .. text);
    cb.CheckedChanged = function(sender)
        if (not syncing) then onChanged(sender:IsChecked()); end
    end
    return cb;
end

local function StepButton(text, x, y, onClick)
    local b = Turbine.UI.Lotro.Button();
    b:SetParent(CS.optionsPanel);
    b:SetPosition(x, y);
    b:SetSize(24, 20);
    b:SetText(text);
    b.Click = function() onClick(); end
    return b;
end

-- Applies a new share line length everywhere.
function CS.OptionsPanel.SetMaxLen(value)
    CS.settings.maxLen = CS.Util.Clamp(math.floor(value), CS.MAXLEN_MIN, CS.MAXLEN_MAX);
    CS.Settings.SaveSoon();
    CS.SharePanel.Update(CS.snapshot);
    CS.OptionsPanel.Refresh();
end

-- Equipment rows show / hide their ItemControl on the next full rebuild.
function CS.OptionsPanel.ApplyIconSetting()
    CS.MarkDirty(true);
end

function CS.OptionsPanel.Build()
    CS.optionsPanel = Turbine.UI.Control();
    CS.optionsPanel:SetSize(PANEL_W, 216);
    CS.optionsPanel:SetBackColor(CS.COL_TRANSPARENT);

    OptionLabel("CharacterStats v" .. CS.PLUGIN_VERSION, LEFT, 10, PANEL_W - 2 * LEFT,
        CS.FONT_TITLE, CS.COL_GOLD);

    controls.icon = OptionCheckBox("Show the screen icon", 36, function(checked)
        CS.IconWindow.SetShown(checked);
    end);
    controls.lock = OptionCheckBox("Lock icon position", 62, function(checked)
        CS.settings.iconLocked = checked;
        CS.Settings.SaveSoon();
    end);
    controls.hideEmpty = OptionCheckBox("Hide empty equipment slots", 88, function(checked)
        CS.settings.hideEmpty = checked;
        CS.Settings.SaveSoon();
        CS.MarkDirty(true);
    end);
    controls.showIcons = OptionCheckBox("Show item icons", 114, function(checked)
        CS.settings.showIcons = checked;
        CS.Settings.SaveSoon();
        CS.OptionsPanel.ApplyIconSetting();
    end);
    controls.nativeItems = OptionCheckBox("Game item icons (tooltip, clickable!)", 140, function(checked)
        CS.settings.nativeItems = checked;
        CS.Settings.SaveSoon();
        CS.OptionsPanel.ApplyIconSetting();
    end);

    OptionLabel("Share line length:", LEFT, 166, 150);
    StepButton("-", LEFT + 154, 166, function()
        CS.OptionsPanel.SetMaxLen(CS.settings.maxLen - CS.MAXLEN_STEP);
    end);
    controls.maxLen = OptionLabel("", LEFT + 182, 166, 44, CS.FONT_OPTION, CS.COL_VALUE,
        Turbine.UI.ContentAlignment.MiddleCenter);
    StepButton("+", LEFT + 230, 166, function()
        CS.OptionsPanel.SetMaxLen(CS.settings.maxLen + CS.MAXLEN_STEP);
    end);
    OptionLabel("Lower it if chat lines get cut off.", LEFT, 190, PANEL_W - 2 * LEFT,
        CS.FONT_SMALL, CS.COL_DIM);

    CS.OptionsPanel.Refresh();
end

-- Writes the current settings into the controls.
function CS.OptionsPanel.Refresh()
    if (controls.icon == nil) then return; end
    syncing = true;
    controls.icon:SetChecked(CS.settings.iconVisible == true);
    controls.lock:SetChecked(CS.settings.iconLocked == true);
    controls.hideEmpty:SetChecked(CS.settings.hideEmpty == true);
    controls.showIcons:SetChecked(CS.settings.showIcons == true);
    controls.nativeItems:SetChecked(CS.settings.nativeItems == true);
    controls.maxLen:SetText(tostring(CS.settings.maxLen));
    syncing = false;
end
