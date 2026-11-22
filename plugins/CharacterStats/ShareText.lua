--[[=========================================================================

    CharacterStats -- ShareText.lua
    Builds the chat pages ({ title, text }) from a snapshot. Each page is
    one chat line no longer than maxLen including the channel command.

=========================================================================]]

CS.ShareText = { };

-- "Label value" segment, or nil if the value is missing.
local function Seg(label, value)
    if (type(value) ~= "number") then return nil; end
    return label .. " " .. CS.Util.FormatPlain(value);
end

-- Adds segments (skipping nils) to "items"; the first one of a section
-- is separated by " | ", the others by ", ".
local function AddSection(items, segments)
    local first = true;
    for i = 1, table.maxn(segments) do
        local s = segments[i];
        if (s ~= nil) then
            table.insert(items, { text = CS.Util.SanitizeChat(s), sep = first and " | " or ", " });
            first = false;
        end
    end
end

-- "a/b/c" from three values, or nil if all are missing.
local function Triple(label, a, b, c)
    if (type(a) ~= "number" and type(b) ~= "number" and type(c) ~= "number") then return nil; end
    local function P(v) return (type(v) == "number") and CS.Util.FormatPlain(v) or "-"; end
    return label .. " " .. P(a) .. "/" .. P(b) .. "/" .. P(c);
end

--[[
    Greedy packer: returns a list of line bodies (without prefix). Every
    line has room for "budget - prefixLen" characters. A single segment
    that is too long is truncated with "..." (lengths are bytes, the cut
    is made at a UTF-8 character boundary).
]]
local function Pack(prefixLen, items, budget)
    local room = math.max(10, budget - prefixLen);
    local lines = { };
    local line;
    for _, item in ipairs(items) do
        local piece = item.text;
        if (string.len(piece) > room) then
            piece = CS.Util.Utf8Truncate(piece, room - 3) .. "...";
        end
        if (line == nil) then
            line = piece;
        else
            local candidate = line .. item.sep .. piece;
            if (string.len(candidate) > room) then
                table.insert(lines, line);
                line = piece;
            else
                line = candidate;
            end
        end
    end
    if (line ~= nil) then table.insert(lines, line); end
    return lines;
end

-- Packs one stat page; several lines become "Title 1/n" pages.
local function AddPages(pages, title, prefix, items, budget)
    if (#items == 0) then return; end
    local lines = Pack(string.len(prefix), items, budget);
    for i, body in ipairs(lines) do
        local t = title;
        if (#lines > 1) then t = title .. " " .. i .. "/" .. #lines; end
        table.insert(pages, { title = t, text = prefix .. body });
    end
end

function CS.ShareText.Build(snap, maxLen, cmdLen)
    local pages = { };
    if (snap == nil) then return pages; end
    local v = snap.values;
    local budget = maxLen - (cmdLen or 0) - 1;   -- command + space count against the limit
    -- the name is also a page prefix: cap it so the prefix always fits
    local name = CS.Util.Utf8Truncate(CS.Util.SanitizeChat(v.name or "?"), CS.SHARE_NAME_MAX);

    -- Core
    local head = name;
    if (type(v.level) == "number") then head = head .. " L" .. CS.Util.FormatPlain(v.level); end
    if (v.race ~= nil and v.race ~= "Undefined" and v.race ~= "?") then head = head .. " " .. v.race; end
    if (v.class ~= nil) then head = head .. " " .. v.class; end
    if (not snap.isFreePeople) then head = head .. " (Monster Play)"; end

    local items = { };
    AddSection(items, { head });
    AddSection(items, { Seg("Morale", v.moraleMax), Seg("Power", v.powerMax) });
    if (snap.isFreePeople) then
        AddSection(items, { Seg("Might", v.might), Seg("Agi", v.agility), Seg("Vit", v.vitality),
            Seg("Will", v.will), Seg("Fate", v.fate) });
    end
    AddPages(pages, "Core", "", items, budget);
    if (not snap.isFreePeople) then return pages; end

    -- Offence
    items = { };
    AddSection(items, { Seg("Melee", v.meleeDmg), Seg("Ranged", v.rangedDmg), Seg("Tactical", v.tacticalDmg) });
    AddSection(items, { Triple("Crit M/R/T", v.meleeCrit, v.rangedCrit, v.tacticalCrit) });
    AddSection(items, { Seg("Finesse", v.finesse) });
    AddSection(items, { Seg("Out.heal", v.outHeal) });
    AddPages(pages, "Offence", name .. " offence: ", items, budget);

    -- Defence (Block / Parry / Evade only if the character can use them)
    local function CanSeg(label, key)
        if (v[key .. "Can"] == false) then return nil; end
        return Seg(label, v[key]);
    end
    items = { };
    AddSection(items, { Seg("Armour", v.armour) });
    AddSection(items, { CanSeg("Block", "block"), CanSeg("Parry", "parry"), CanSeg("Evade", "evade") });
    AddSection(items, { Triple("Def M/R/T", v.meleeDef, v.rangedDef, v.tacticalDef) });
    AddSection(items, { Seg("Crit.av", v.baseCritAv) });
    AddSection(items, { Seg("In.heal", v.inHeal) });
    AddPages(pages, "Defence", name .. " defence: ", items, budget);

    -- Mitigations
    items = { };
    AddSection(items, { Seg("Common", v.mitCommon), Seg("Physical", v.mitPhysical),
        Seg("Tactical", v.mitTactical), Seg("Fire", v.mitFire), Seg("Frost", v.mitFrost),
        Seg("Lightning", v.mitLightning), Seg("Shadow", v.mitShadow), Seg("Acid", v.mitAcid) });
    AddSection(items, { Seg("Resist", v.resist) });
    AddPages(pages, "Mitigation", name .. " mitigations: ", items, budget);

    -- Gear: pack with the longest possible prefix, then insert "(i/n)"
    items = { };
    for _, g in ipairs(snap.gear) do
        table.insert(items, { text = g.slotLabel .. ": " .. g.name, sep = ", " });
    end
    if (#items > 0) then
        local longest = name .. " gear (99/99): ";
        local lines = Pack(string.len(longest), items, budget);
        for i, body in ipairs(lines) do
            local count = (#lines > 1) and (" (" .. i .. "/" .. #lines .. ")") or "";
            table.insert(pages, {
                title = (#lines > 1) and ("Gear " .. i .. "/" .. #lines) or "Gear",
                text = name .. " gear" .. count .. ": " .. body,
            });
        end
    end
    return pages;
end
