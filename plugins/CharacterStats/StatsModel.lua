--[[=========================================================================

    CharacterStats -- StatsModel.lua
    Reads the player into a "snapshot" (groups / sub-groups / rows /
    equipped items), dirty flags and the game event wiring.

    Every API getter goes through CS.Util.Call: many stat getters are
    undocumented (present in the client only), and rows whose getter is
    missing or fails are simply left out.

=========================================================================]]

CS.Model = { };

------------------------------------------------------------------------
-- DIRTY FLAGS
------------------------------------------------------------------------

CS.dirty = { full = false, values = false, layout = false };

-- full = true: the row structure may have changed (rebuild the list);
-- otherwise only values changed. (layout: rows need a new width.)
function CS.MarkDirty(full)
    if (full) then CS.dirty.full = true; else CS.dirty.values = true; end
end

------------------------------------------------------------------------
-- STAT ROWS
------------------------------------------------------------------------

-- Builds one display row from a CS.STAT_GROUPS definition; also stores
-- the raw value(s) in "values" for the share text. nil = omit the row.
local function BuildStatRow(def, player, attrs, values)
    local U = CS.Util;
    local obj = (def.src == "player") and player or attrs;
    if (not U.Has(obj, def.get)) then return nil; end
    local v = U.Call(obj, def.get);
    local fmt = def.fmt;
    local text, colour;

    if (fmt == "text") then
        text = U.CleanGameText(v);
        if (text == "") then return nil; end
        values[def.key] = text;
    elseif (fmt == "int" or fmt == "dec1") then
        if (type(v) ~= "number") then return nil; end
        text = U.FormatNumber(v, fmt);
        values[def.key] = v;
        if (def.base ~= nil) then
            local b = U.Call(obj, def.base);
            if (type(b) == "number") then
                text = text .. "  (base " .. U.FormatInt(b) .. ")";
            end
        end
        if (def.can ~= nil and U.Has(obj, def.can)) then
            local can = U.Call(obj, def.can);
            values[def.key .. "Can"] = (can ~= false);
            if (can == false) then
                text = "n/a";
                colour = CS.COL_DIM;
            end
        end
    elseif (fmt == "class") then
        if (v == nil) then return nil; end
        text = U.EnumName(Turbine.Gameplay.Class, v, CS.CLASS_PRETTY);
        values[def.key] = text;
        values.classValue = v;
    elseif (fmt == "race") then
        if (v == nil) then return nil; end
        text = U.EnumName(Turbine.Gameplay.Race, v, CS.RACE_PRETTY);
        values[def.key] = text;
    elseif (fmt == "alignment") then
        -- only interesting for Monster Players
        if (v == nil or v == U.Field(Turbine.Gameplay.Alignment, "FreePeople")) then return nil; end
        text = U.EnumName(Turbine.Gameplay.Alignment, v);
        values[def.key] = text;
    elseif (fmt == "vocation") then
        if (v == nil) then return nil; end
        text = U.EnumName(U.Field(Turbine.Gameplay, "Vocation"), v);
        values[def.key] = text;
    elseif (fmt == "money") then
        if (type(v) ~= "number") then return nil; end
        text = U.FormatMoney(v);
        values[def.key] = v;
    elseif (fmt == "curmax") then
        if (type(v) ~= "number") then return nil; end
        local m = U.Call(obj, def.max);
        if (def.ifMax and not (type(m) == "number" and m > 0)) then return nil; end
        text = U.FormatInt(v);
        if (type(m) == "number") then text = text .. " / " .. U.FormatInt(m); end
        values[def.key] = v;
        values[def.key .. "Max"] = m;
    else
        return nil;
    end

    return { key = def.key, label = def.label, value = text, color = colour };
end

-- Class sub-group from player:GetClassAttributes().
local function BuildClassRows(player, values)
    local U = CS.Util;
    local rows = { };
    local cattrs = U.Call(player, "GetClassAttributes");
    if (cattrs == nil) then return rows; end

    -- stance enum: Turbine.Gameplay.Attributes.<ClassName>Stance (client only)
    local stanceEnum;
    local className = U.ReverseEnum(Turbine.Gameplay.Class)[values.classValue or -1];
    if (className ~= nil) then
        stanceEnum = U.Field(U.Field(Turbine.Gameplay, "Attributes"), className .. "Stance");
    end

    for _, def in ipairs(CS.CLASS_ROWS) do
        if (U.Has(cattrs, def.get)) then
            local v = U.Call(cattrs, def.get);
            local text;
            if (def.fmt == "stance") then
                if (type(v) == "number") then
                    if (type(stanceEnum) == "table") then
                        text = U.EnumName(stanceEnum, v);
                        if (text == "?") then text = tostring(v); end
                    else
                        text = tostring(v);
                    end
                end
            elseif (def.fmt == "bool") then
                if (type(v) == "boolean") then text = v and "Yes" or "No"; end
            elseif (def.fmt == "curmax") then
                if (type(v) == "number") then
                    text = U.FormatInt(v);
                    local m = U.Call(cattrs, def.max);
                    if (type(m) == "number") then text = text .. " / " .. U.FormatInt(m); end
                end
            elseif (type(v) == "number") then
                text = U.FormatInt(v);
            end
            if (text ~= nil) then
                values[def.key] = text;
                table.insert(rows, { key = def.key, label = def.label, value = text });
            end
        end
    end
    return rows;
end

--[[
    Crafting sub-group: one row per known profession, value
    "Prof 9 / Mast 8 - Westemnet Farmer". The client prefixes the title
    with the character name ("Ebcey, Westemnet Farmer"), which is removed.
    GetMasteryTitle (also in the dump) is left out to keep the row short.
]]
local function BuildCraftRows(attrs, playerName)
    local U = CS.Util;
    local rows = { };
    if (not U.Has(attrs, "GetProfessionInfo")) then return rows; end
    local professions = U.Field(Turbine.Gameplay, "Profession");
    if (professions == nil) then return rows; end

    local list = { };
    for value, name in pairs(U.ReverseEnum(professions)) do
        if (name ~= "Undefined") then table.insert(list, { value = value, name = name }); end
    end
    table.sort(list, function(a, b) return a.name < b.name; end);

    for _, p in ipairs(list) do
        local info = U.Call(attrs, "GetProfessionInfo", p.value);
        if (info ~= nil) then
            local prof  = U.Call(info, "GetProficiencyLevel");
            local title = U.CleanGameText(U.Call(info, "GetProficiencyTitle"));
            title = U.CleanGameText(U.StripNamePrefix(title, playerName));
            local mast  = U.Call(info, "GetMasteryLevel");
            local text = "Prof " .. tostring(prof or "?") .. " / Mast " .. tostring(mast or "?");
            if (title ~= "") then text = text .. " - " .. title; end
            local label = U.CleanGameText(U.Call(info, "GetName"));
            if (label == "") then label = U.SplitCamel(p.name); end
            table.insert(rows, { key = "craft" .. p.name, label = label, value = text });
        end
    end
    return rows;
end

------------------------------------------------------------------------
-- EQUIPMENT
------------------------------------------------------------------------

local function BuildItemEntry(eq, entry)
    local U = CS.Util;
    local item = U.Call(eq, "GetItem", entry.slot);
    local e = { slot = entry.slot, slotLabel = entry.label, item = item };
    if (item == nil) then return e; end

    local info = U.Call(item, "GetItemInfo");
    local name = U.CleanGameText(U.Call(info, "GetName"));
    if (name == "") then name = U.CleanGameText(U.Call(item, "GetName")); end
    if (name == "") then name = "(unnamed item)"; end
    e.name = name;

    -- "" also for the client's "string table error" placeholder
    e.desc = U.CleanGameText(U.Call(info, "GetDescription"));

    e.quality = U.Call(info, "GetQuality") or U.Call(item, "GetQuality");

    -- image ids for the static (non-interactive) icon, bottom layer first
    e.images = { };
    for _, getter in ipairs({ "GetBackgroundImageID", "GetUnderlayImageID", "GetShadowImageID", "GetIconImageID" }) do
        local id = U.Call(info, getter);
        table.insert(e.images, (type(id) == "number" and id ~= 0) and id or false);
    end

    local parts = { };
    local category = U.Call(info, "GetCategory");
    if (category ~= nil) then
        local s = U.EnumName(U.Field(Turbine.Gameplay, "ItemCategory"), category);
        if (s ~= "?" and s ~= "Undefined") then table.insert(parts, s); end
    end
    local durability = U.Call(info, "GetDurability");
    if (durability ~= nil) then
        local s = U.EnumName(U.Field(Turbine.Gameplay, "ItemDurability"), durability);
        if (s ~= "?" and s ~= "Undefined") then table.insert(parts, "Durability: " .. s); end
    end
    local wear = U.Call(item, "GetWearState");
    if (wear ~= nil) then
        local s = U.EnumName(U.Field(Turbine.Gameplay, "ItemWearState"), wear);
        if (s ~= "?" and s ~= "Undefined") then table.insert(parts, "Condition: " .. s); end
    end
    e.extra = table.concat(parts, ", ");
    return e;
end

local function BuildEquipmentGroup(player, snap)
    local U = CS.Util;
    local group = { id = "equip", title = "Equipment", subs = { }, filled = 0, total = 0 };
    local eq = U.Call(player, "GetEquipment");
    if (eq == nil) then
        group.unavailable = true;
        table.insert(group.subs, { id = "equip.none", title = "Equipment", rows = {
            { key = "equipNA", label = "Equipment not available", value = "", color = CS.COL_DIM },
        }});
        return group;
    end

    for _, def in ipairs(CS.EQUIP_GROUPS) do
        local sub = { id = def.id, title = def.title, items = { }, filled = 0, total = 0 };
        for _, entry in ipairs(def.slots) do
            local e = BuildItemEntry(eq, entry);
            sub.total = sub.total + 1;
            if (e.item ~= nil) then
                sub.filled = sub.filled + 1;
                table.insert(snap.gear, {
                    slotLabel = entry.label,
                    name = CS.Util.SanitizeChat(e.name),
                });
            end
            if (e.item ~= nil or not CS.settings.hideEmpty) then
                table.insert(sub.items, e);
            end
        end
        group.filled = group.filled + sub.filled;
        group.total  = group.total + sub.total;
        if (#sub.items > 0) then table.insert(group.subs, sub); end
    end
    return group;
end

------------------------------------------------------------------------
-- SNAPSHOT
------------------------------------------------------------------------

function CS.Model.Collect()
    local U = CS.Util;
    local player = CS.player;
    local attrs = U.Call(player, "GetAttributes");
    local snap = { groups = { }, values = { }, gear = { } };

    local alignment = U.Call(player, "GetAlignment");
    local monster = U.Field(Turbine.Gameplay.Alignment, "MonsterPlayer");
    snap.isFreePeople = (alignment == nil or alignment ~= monster);

    -- characteristics
    local charGroup = { id = "char", title = "Characteristics", subs = { } };
    for _, def in ipairs(CS.STAT_GROUPS) do
        local sub = { id = def.id, title = def.title, rows = { } };
        for _, rowDef in ipairs(def.rows) do
            local row = BuildStatRow(rowDef, player, attrs, snap.values);
            if (row ~= nil) then table.insert(sub.rows, row); end
        end
        if (def.id == "char.general" and not snap.isFreePeople) then
            table.insert(sub.rows, { key = "mpNote", label = "Note",
                value = "Limited stats for Monster Players", color = CS.COL_DIM });
        end
        if (#sub.rows > 0) then table.insert(charGroup.subs, sub); end
    end
    local classRows = BuildClassRows(player, snap.values);
    if (#classRows > 0) then
        table.insert(charGroup.subs, { id = "char.class", title = "Class", rows = classRows });
    end
    local craftRows = BuildCraftRows(attrs, U.CleanGameText(U.Call(player, "GetName")));
    if (#craftRows > 0) then
        table.insert(charGroup.subs, { id = "char.craft", title = "Crafting", rows = craftRows });
    end
    table.insert(snap.groups, charGroup);

    -- equipment
    table.insert(snap.groups, BuildEquipmentGroup(player, snap));

    -- one-line summary under the title
    local v = snap.values;
    local summary = tostring(v.name or "?");
    if (v.level ~= nil) then summary = summary .. " - Level " .. U.FormatPlain(v.level); end
    if (v.class ~= nil) then summary = summary .. " " .. v.class; end
    if (v.race ~= nil and v.race ~= "Undefined" and v.race ~= "?") then
        summary = summary .. " (" .. v.race .. ")";
    end
    snap.summary = summary;
    return snap;
end

-- Structure signature: row keys + item names / descriptions per slot. A
-- change means the list must be rebuilt; otherwise only values are updated.
function CS.Model.Signature(snap)
    local parts = { };
    for _, group in ipairs(snap.groups) do
        table.insert(parts, group.id);
        for _, sub in ipairs(group.subs) do
            table.insert(parts, sub.id);
            if (sub.rows ~= nil) then
                for _, row in ipairs(sub.rows) do table.insert(parts, row.key); end
            end
            if (sub.items ~= nil) then
                for _, e in ipairs(sub.items) do
                    table.insert(parts, tostring(e.slot) .. "=" .. tostring(e.name)
                        .. "/" .. tostring(e.desc) .. "/" .. tostring(e.extra));
                end
            end
        end
    end
    return table.concat(parts, "|");
end

------------------------------------------------------------------------
-- GAME EVENTS (handlers only set flags)
------------------------------------------------------------------------

function CS.WireGameEvents()
    local hub = CS.EventHub;
    local player = CS.player;
    if (player == nil) then return; end

    local function Full() CS.MarkDirty(true); end
    local function Values() CS.MarkDirty(false); end

    hub.Add(player, "LevelChanged", Full);
    for _, name in ipairs({ "MaxMoraleChanged", "BaseMaxMoraleChanged", "MaxPowerChanged",
            "BaseMaxPowerChanged", "MaxTemporaryMoraleChanged", "MaxTemporaryPowerChanged",
            "NameChanged" }) do
        hub.Add(player, name, Values);
    end

    CS.equipment = CS.Util.Call(player, "GetEquipment");
    if (CS.equipment ~= nil) then
        hub.Add(CS.equipment, "ItemEquipped", Full);
        hub.Add(CS.equipment, "ItemUnequipped", Full);
    end
    -- buffs / effects are not hooked: the 1 s poll picks up their stat
    -- changes, and effect events would only add refreshes in combat
end
