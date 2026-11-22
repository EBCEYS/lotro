--[[=========================================================================

    CharacterStats -- Constants.lua
    Names, layout, colours, fonts, equipment slots, stat definitions and
    chat channels. Only constant tables are created here.

=========================================================================]]

------------------------------------------------------------------------
-- GENERAL
------------------------------------------------------------------------

CS.PLUGIN_NAME    = "CharacterStats";
CS.PLUGIN_VERSION = "1.0.0";
CS.SAVE_KEY       = "CharacterStats_Settings";
CS.SAVE_VERSION   = 2;            -- 2: item descriptions expanded by default

CS.ACTION_HUD_TOGGLE = 0x100000B3;   -- 268435635, "toggle HUD" (F12 by default)

-- timing (seconds, Turbine.Engine.GetGameTime() timeline)
CS.REFRESH_MIN_INTERVAL = 0.25;      -- dirty -> refresh at most 4x per second
CS.POLL_INTERVAL        = 1.0;       -- value polling while the main window is visible
CS.SAVE_DEBOUNCE        = 2.0;       -- save N s after the last position/size/collapse change

-- set to true if the mouse wheel does not scroll the list in game
CS.WHEEL_FALLBACK = false;
CS.WHEEL_STEP     = 40;

------------------------------------------------------------------------
-- LAYOUT
------------------------------------------------------------------------

-- main window
CS.MAIN_DEFAULT_W = 380;  CS.MAIN_DEFAULT_H = 560;
CS.MAIN_MIN_W     = 320;  CS.MAIN_MIN_H     = 360;
CS.MAIN_MAX_W     = 900;  -- max height = Display height
CS.CONTENT_TOP    = 34;   -- in a Lotro.Window the title bar covers the first ~30 px
CS.PAD            = 12;   -- left/right padding inside the window
CS.SCROLL_W       = 10;
CS.TOOLBAR_H      = 22;
CS.SHARE_H        = 96;   -- minimum height of the share panel at the bottom
CS.SHARE_EXTRA_MAX = 72;  -- the preview grows by up to this much in taller windows
CS.BOTTOM_PAD     = 14;   -- keep clear of the resize grip

-- rows
CS.ROW_GROUP_H    = 24;   -- top group header
CS.ROW_SUB_H      = 20;   -- sub-group header
CS.ROW_STAT_H     = 18;
CS.ROW_ITEM_H     = 36;   -- equipment row (32 px icon + 2 + 2)
CS.DESC_LINE_H    = 14;   -- description line height estimate (Verdana12)
CS.DESC_CHAR_W    = 6.5;  -- average char width estimate for Verdana12 (tune in game)
CS.ROW_CHAR_W     = 6.5;  -- average char width estimate for stat rows (Verdana12, as DESC_CHAR_W)
CS.STAT_GAP       = 8;    -- gap between the label and value column of a stat row
CS.LABEL_MIN_SHARE = 0.4; -- a long value never squeezes the label below this share
CS.INDENT_SUB     = 10;
CS.INDENT_ROW     = 20;
CS.ITEM_TEXT_X    = 58;   -- x of slot/name/description text in equipment rows

-- icon window
CS.ICON_SIZE      = 36;
CS.DRAG_THRESHOLD = 3;    -- px before a left press becomes a drag

-- chat
CS.MAXLEN_DEFAULT = 200;  CS.MAXLEN_MIN = 80;  CS.MAXLEN_MAX = 400;  CS.MAXLEN_STEP = 20;
CS.SHARE_NAME_MAX = 32;   -- bytes of the character name used in share pages

------------------------------------------------------------------------
-- COLOURS (Turbine.UI.Color(r, g, b) or (a, r, g, b) - ALPHA FIRST)
------------------------------------------------------------------------

CS.COL_GOLD          = Turbine.UI.Color(1, 0.82, 0.30);
CS.COL_SUB           = Turbine.UI.Color(0.90, 0.78, 0.50);
CS.COL_LABEL         = Turbine.UI.Color(0.80, 0.80, 0.80);
CS.COL_VALUE         = Turbine.UI.Color(1, 1, 1);
CS.COL_DIM           = Turbine.UI.Color(0.50, 0.50, 0.50);
CS.COL_DESC          = Turbine.UI.Color(0.75, 0.72, 0.62);
CS.COL_GROUP_BG      = Turbine.UI.Color(0.85, 0.20, 0.16, 0.08);
CS.COL_SUB_BG        = Turbine.UI.Color(0.70, 0.12, 0.10, 0.06);
CS.COL_ROW_ALT       = Turbine.UI.Color(0.25, 0.30, 0.30, 0.30);
CS.COL_HOVER         = Turbine.UI.Color(0.35, 0.50, 0.42, 0.20);
CS.COL_ICON_BG       = Turbine.UI.Color(0.85, 0.08, 0.07, 0.05);
CS.COL_ICON_BG_HOVER = Turbine.UI.Color(0.95, 0.20, 0.16, 0.08);
CS.COL_TRANSPARENT   = Turbine.UI.Color(0, 0, 0, 0);
CS.COL_SLOT_EMPTY    = Turbine.UI.Color(0.6, 0.1, 0.1, 0.1);
CS.COL_PANEL_BG      = Turbine.UI.Color(0.96, 0.08, 0.07, 0.05);   -- share panel: near-opaque
CS.COL_PREVIEW_BG    = Turbine.UI.Color(1, 0.03, 0.03, 0.02);      -- share preview: opaque inset
CS.COL_BLACK         = Turbine.UI.Color(0, 0, 0);

-- item name colour by quality, keyed by the enum VALUE (built from names)
CS.QUALITY_COLOR = { };
do
    local q = Turbine.Gameplay.ItemQuality;
    local byName = {
        Common       = Turbine.UI.Color(1, 1, 1),
        Uncommon     = Turbine.UI.Color(1, 0.93, 0.35),
        Rare         = Turbine.UI.Color(0.78, 0.45, 1),
        Incomparable = Turbine.UI.Color(0.30, 0.90, 0.85),
        Legendary    = Turbine.UI.Color(1, 0.60, 0.15),
    };
    if (q ~= nil) then
        for name, colour in pairs(byName) do
            local value = q[name];
            if (type(value) == "number") then CS.QUALITY_COLOR[value] = colour; end
        end
    end
end

------------------------------------------------------------------------
-- FONTS (only names from the U49 font list)
------------------------------------------------------------------------

CS.FONT_GROUP   = Turbine.UI.Lotro.Font.TrajanPro15;
CS.FONT_SUB     = Turbine.UI.Lotro.Font.TrajanPro13;
CS.FONT_ROW     = Turbine.UI.Lotro.Font.Verdana12;
CS.FONT_DESC    = Turbine.UI.Lotro.Font.Verdana12;
CS.FONT_SMALL   = Turbine.UI.Lotro.Font.Verdana10;
CS.FONT_ICON    = Turbine.UI.Lotro.Font.TrajanProBold16;
CS.FONT_SUMMARY = Turbine.UI.Lotro.Font.TrajanPro14;
CS.FONT_TITLE   = Turbine.UI.Lotro.Font.TrajanPro16;
CS.FONT_OPTION  = Turbine.UI.Lotro.Font.Verdana14;

------------------------------------------------------------------------
-- EQUIPMENT SLOTS
--
-- Slot numbers are resolved at boot from Turbine.Gameplay.Equipment.<key>
-- (CS.Util.ResolveSlots). Dump values in comments - never hard-coded.
------------------------------------------------------------------------

CS.EQUIP_GROUPS = {
    { id = "equip.armour", title = "Armour", slots = {
        { key = "Head",     label = "Head" },          -- 1
        { key = "Shoulder", label = "Shoulders" },     -- 6
        { key = "Back",     label = "Back" },          -- 7
        { key = "Chest",    label = "Chest" },         -- 2
        { key = "Gloves",   label = "Hands" },         -- 4
        { key = "Legs",     label = "Legs" },          -- 3
        { key = "Boots",    label = "Feet" },          -- 5
    }},
    { id = "equip.jewellery", title = "Jewellery", slots = {
        { key = "Necklace",  label = "Neck" },         -- 10
        { key = "Earring1",  label = "Ear 1" },        -- 13
        { key = "Earring2",  label = "Ear 2" },        -- 14
        { key = "Bracelet1", label = "Wrist 1" },      -- 8
        { key = "Bracelet2", label = "Wrist 2" },      -- 9
        { key = "Ring1",     label = "Ring 1" },       -- 11
        { key = "Ring2",     label = "Ring 2" },       -- 12
        { key = "Pocket",    label = "Pocket" },       -- 15
    }},
    { id = "equip.weapons", title = "Weapons & Tools", slots = {
        { key = "PrimaryWeapon",   label = "Main hand" },                            -- 16
        { key = "SecondaryWeapon", alt = "Shield",     label = "Off-hand / Shield" },   -- 17 (shared)
        { key = "RangedWeapon",    alt = "Instrument", label = "Ranged / Instrument" }, -- 18 (shared)
        { key = "Class",           label = "Class item" },                           -- 20
        { key = "CraftTool",       label = "Craft tool" },                           -- 19
        { key = "Bridle",          label = "Bridle" },                               -- 21
    }},
};

------------------------------------------------------------------------
-- STAT DEFINITIONS
--
-- src  : "player" (LocalPlayer methods) or "attrs" (GetAttributes())
-- get  : getter method name; rows whose getter is missing are omitted
-- base : optional "base value" getter, shown as "(base N)"
-- can  : optional boolean getter; false -> "n/a"
-- max  : for fmt "curmax", the maximum getter ("cur / max")
-- fmt  : int | dec1 | text | class | race | alignment | vocation | money | curmax
-- ifMax: curmax row only shown when the maximum is > 0
------------------------------------------------------------------------

CS.STAT_GROUPS = {
    { id = "char.general", title = "General", rows = {
        { key = "name",      label = "Name",           src = "player", get = "GetName",      fmt = "text" },
        { key = "level",     label = "Level",          src = "player", get = "GetLevel",     fmt = "int" },
        { key = "class",     label = "Class",          src = "player", get = "GetClass",     fmt = "class" },
        { key = "race",      label = "Race",           src = "player", get = "GetRace",      fmt = "race" },
        { key = "alignment", label = "Alignment",      src = "player", get = "GetAlignment", fmt = "alignment" },
        { key = "vocation",  label = "Vocation",       src = "attrs",  get = "GetVocation",  fmt = "vocation" },
        { key = "destiny",   label = "Destiny points", src = "attrs",  get = "GetDestinyPoints", fmt = "int" },
        { key = "money",     label = "Money",          src = "attrs",  get = "GetMoney",     fmt = "money" },
    }},
    { id = "char.vitals", title = "Vitals", rows = {
        { key = "morale",     label = "Morale",            src = "player", get = "GetMorale", max = "GetMaxMorale", fmt = "curmax" },
        { key = "baseMorale", label = "Base max morale",   src = "player", get = "GetBaseMaxMorale", fmt = "int" },
        { key = "tempMorale", label = "Temporary morale",  src = "player", get = "GetTemporaryMorale", max = "GetMaxTemporaryMorale", fmt = "curmax", ifMax = true },
        { key = "power",      label = "Power",             src = "player", get = "GetPower", max = "GetMaxPower", fmt = "curmax" },
        { key = "basePower",  label = "Base max power",    src = "player", get = "GetBaseMaxPower", fmt = "int" },
        { key = "tempPower",  label = "Temporary power",   src = "player", get = "GetTemporaryPower", max = "GetMaxTemporaryPower", fmt = "curmax", ifMax = true },
        { key = "icmr",       label = "In-combat morale regen",     src = "attrs", get = "GetInCombatMoraleRegeneration",    fmt = "dec1" },
        { key = "ocmr",       label = "Out-of-combat morale regen", src = "attrs", get = "GetOutOfCombatMoraleRegeneration", fmt = "dec1" },
        { key = "icpr",       label = "In-combat power regen",      src = "attrs", get = "GetInCombatPowerRegeneration",     fmt = "dec1" },
        { key = "ocpr",       label = "Out-of-combat power regen",  src = "attrs", get = "GetOutOfCombatPowerRegeneration",  fmt = "dec1" },
    }},
    { id = "char.primary", title = "Main stats", rows = {
        { key = "might",    label = "Might",    src = "attrs", get = "GetMight",    base = "GetBaseMight",    fmt = "int" },
        { key = "agility",  label = "Agility",  src = "attrs", get = "GetAgility",  base = "GetBaseAgility",  fmt = "int" },
        { key = "vitality", label = "Vitality", src = "attrs", get = "GetVitality", base = "GetBaseVitality", fmt = "int" },
        { key = "will",     label = "Will",     src = "attrs", get = "GetWill",     base = "GetBaseWill",     fmt = "int" },
        { key = "fate",     label = "Fate",     src = "attrs", get = "GetFate",     base = "GetBaseFate",     fmt = "int" },
    }},
    { id = "char.offence", title = "Offence", rows = {
        { key = "meleeDmg",     label = "Melee damage",      src = "attrs", get = "GetMeleeDamage",               fmt = "int" },
        { key = "rangedDmg",    label = "Ranged damage",     src = "attrs", get = "GetRangeDamage",               fmt = "int" },
        { key = "tacticalDmg",  label = "Tactical damage",   src = "attrs", get = "GetTacticalDamage",            fmt = "int" },
        { key = "meleeCrit",    label = "Melee critical",    src = "attrs", get = "GetMeleeCriticalHitChance",    fmt = "int" },
        { key = "rangedCrit",   label = "Ranged critical",   src = "attrs", get = "GetRangeCriticalHitChance",    fmt = "int" },
        { key = "tacticalCrit", label = "Tactical critical", src = "attrs", get = "GetTacticalCriticalHitChance", fmt = "int" },
        { key = "baseCrit",     label = "Critical (base)",   src = "attrs", get = "GetBaseCriticalHitChance",     fmt = "int" },
        { key = "finesse",      label = "Finesse",           src = "attrs", get = "GetFinesse",                   fmt = "int" },
        { key = "outHeal",      label = "Outgoing healing",  src = "attrs", get = "GetOutgoingHealing",           fmt = "int" },
    }},
    { id = "char.defence", title = "Defence", rows = {
        { key = "armour",         label = "Armour",                  src = "attrs", get = "GetArmor", base = "GetBaseArmor", fmt = "int" },
        { key = "block",          label = "Block",                   src = "attrs", get = "GetBlock", can = "CanBlock",      fmt = "int" },
        { key = "parry",          label = "Parry",                   src = "attrs", get = "GetParry", can = "CanParry",      fmt = "int" },
        { key = "evade",          label = "Evade",                   src = "attrs", get = "GetEvade", can = "CanEvade",      fmt = "int" },
        { key = "meleeDef",       label = "Melee defence",           src = "attrs", get = "GetMeleeDefence",                 fmt = "int" },
        { key = "rangedDef",      label = "Ranged defence",          src = "attrs", get = "GetRangeDefence",                 fmt = "int" },
        { key = "tacticalDef",    label = "Tactical defence",        src = "attrs", get = "GetTacticalDefence",              fmt = "int" },
        { key = "meleeCritAv",    label = "Melee crit. avoidance",   src = "attrs", get = "GetMeleeCriticalHitAvoidance",    fmt = "int" },
        { key = "rangedCritAv",   label = "Ranged crit. avoidance",  src = "attrs", get = "GetRangeCriticalHitAvoidance",    fmt = "int" },
        { key = "tacticalCritAv", label = "Tactical crit. avoidance", src = "attrs", get = "GetTacticalCriticalHitAvoidance", fmt = "int" },
        { key = "baseCritAv",     label = "Crit. avoidance (base)",  src = "attrs", get = "GetBaseCriticalHitAvoidance",     fmt = "int" },
        { key = "inHeal",         label = "Incoming healing",        src = "attrs", get = "GetIncomingHealing",              fmt = "int" },
    }},
    { id = "char.mitigation", title = "Mitigations", rows = {
        { key = "mitCommon",    label = "Common",    src = "attrs", get = "GetCommonMitigation",    fmt = "int" },
        { key = "mitPhysical",  label = "Physical",  src = "attrs", get = "GetPhysicalMitigation",  fmt = "int" },
        { key = "mitTactical",  label = "Tactical",  src = "attrs", get = "GetTacticalMitigation",  fmt = "int" },
        { key = "mitFire",      label = "Fire",      src = "attrs", get = "GetFireMitigation",      fmt = "int" },
        { key = "mitFrost",     label = "Frost",     src = "attrs", get = "GetFrostMitigation",     fmt = "int" },
        { key = "mitLightning", label = "Lightning", src = "attrs", get = "GetLightningMitigation", fmt = "int" },
        { key = "mitShadow",    label = "Shadow",    src = "attrs", get = "GetShadowMitigation",    fmt = "int" },
        { key = "mitAcid",      label = "Acid",      src = "attrs", get = "GetAcidMitigation",      fmt = "int" },
    }},
    { id = "char.resist", title = "Resistances", rows = {
        { key = "resist",       label = "Resistance (base)", src = "attrs", get = "GetBaseResistance",    fmt = "int" },
        { key = "resDisease",   label = "Disease",           src = "attrs", get = "GetDiseaseResistance", fmt = "int" },
        { key = "resFear",      label = "Fear",              src = "attrs", get = "GetFearResistance",    fmt = "int" },
        { key = "resPoison",    label = "Poison",            src = "attrs", get = "GetPoisonResistance",  fmt = "int" },
        { key = "resWound",     label = "Wound",             src = "attrs", get = "GetWoundResistance",   fmt = "int" },
    }},
};

-- class attribute getters, tried in this order (only if present on the object)
CS.CLASS_ROWS = {
    { key = "clsStance",     label = "Stance",     get = "GetStance",     fmt = "stance" },
    { key = "clsFervor",     label = "Fervor",     get = "GetFervor",     fmt = "int" },
    { key = "clsFocus",      label = "Focus",      get = "GetFocus",      fmt = "int" },
    { key = "clsWrath",      label = "Wrath",      get = "GetWrath",      fmt = "int" },
    { key = "clsBearForm",   label = "Bear form",  get = "IsInBearForm",  fmt = "bool" },
    { key = "clsRampage",    label = "Rampage",    get = "GetRampage",    fmt = "int" },
    { key = "clsBalance",    label = "Balance",    get = "GetBalance",    fmt = "int" },
    { key = "clsAttunement", label = "Attunement", get = "GetAttunement", fmt = "int" },
    { key = "clsCharged",    label = "Charged",    get = "IsCharged",     fmt = "bool" },
    { key = "clsGambits",    label = "Gambits",    get = "GetGambitCount", max = "GetMaxGambitCount", fmt = "curmax" },
};

-- default collapse state; everything else (incl. "item.<slot>") is expanded
CS.DEFAULT_COLLAPSED = { ["char.class"] = false, ["char.craft"] = true };

-- pretty names for enum values (everything else -> SplitCamel)
CS.CLASS_PRETTY = { LoreMaster = "Lore-master", RuneKeeper = "Rune-keeper", WarLeader = "Warleader", BlackArrow = "Black Arrow" };
CS.RACE_PRETTY  = { StoutAxe = "Stout-axe", RiverHobbit = "River Hobbit", HighElf = "High Elf" };

------------------------------------------------------------------------
-- SHARE CHANNELS (commands from PimpYourText's English list)
------------------------------------------------------------------------

CS.CHANNELS = {
    { id = "say",     label = "Say",        cmd = "/say" },
    { id = "fellow",  label = "Fellowship", cmd = "/f" },
    { id = "raid",    label = "Raid",       cmd = "/ra" },
    { id = "kin",     label = "Kinship",    cmd = "/k" },
    { id = "officer", label = "Officer",    cmd = "/officer" },
    { id = "lff",     label = "LFF",        cmd = "/lff" },
    { id = "world",   label = "World",      cmd = "/world" },
    { id = "user1",   label = "User 1",     cmd = "/1" },
    { id = "user2",   label = "User 2",     cmd = "/2" },
    { id = "user3",   label = "User 3",     cmd = "/3" },
    { id = "user4",   label = "User 4",     cmd = "/4" },
};

-- French client commands (PimpYourText's French list); German keeps English
CS.CHANNELS_FR = { say = "/parler", world = "/monde", officer = "/off", lff = "/rdc" };
