--[[=========================================================================

    CharacterStats -- Util.lua
    Safe-call helpers, enum reverse maps, formatting, chat sanitising.

=========================================================================]]

CS.Util = { };

------------------------------------------------------------------------
-- SAFE CALLS
------------------------------------------------------------------------

-- Calls obj:name(...) if that method exists; returns nil on any error.
-- Used for every attribute / item getter (many are undocumented).
function CS.Util.Call(obj, name, ...)
    if (obj == nil) then return nil; end
    local okF, f = pcall(function() return obj[name]; end);
    if (not okF or type(f) ~= "function") then return nil; end
    local ok, a, b, c = pcall(f, obj, ...);
    if (ok) then return a, b, c; end
    return nil;
end

function CS.Util.Has(obj, name)
    if (obj == nil) then return false; end
    local okF, f = pcall(function() return obj[name]; end);
    return (okF and type(f) == "function");
end

-- Safe field lookup on a table / API object (nil on error).
function CS.Util.Field(obj, name)
    if (obj == nil) then return nil; end
    local ok, v = pcall(function() return obj[name]; end);
    if (ok) then return v; end
    return nil;
end

-- Prints each distinct error message only once.
CS.reportedErrors = { };
function CS.ReportError(err)
    local msg = tostring(err);
    if (CS.reportedErrors[msg]) then return; end
    CS.reportedErrors[msg] = true;
    Turbine.Shell.WriteLine("<rgb=#FF6060>CharacterStats error: " .. msg .. "</rgb>");
end

------------------------------------------------------------------------
-- ENUMS
------------------------------------------------------------------------

local reverseCache = { };

-- { [number] = name } from an enum table (skips IsA and other functions).
function CS.Util.ReverseEnum(enumTable)
    if (enumTable == nil) then return { }; end
    local cached = reverseCache[enumTable];
    if (cached ~= nil) then return cached; end
    local map = { };
    pcall(function()
        for name, value in pairs(enumTable) do
            if (type(value) == "number" and type(name) == "string") then
                map[value] = name;
            end
        end
    end);
    reverseCache[enumTable] = map;
    return map;
end

function CS.Util.SplitCamel(s)
    if (type(s) ~= "string") then return "?"; end
    return (string.gsub(s, "(%l)(%u)", "%1 %2"));
end

-- Enum value -> display name ("?" if unknown).
function CS.Util.EnumName(enumTable, value, pretty)
    if (value == nil) then return "?"; end
    local name = CS.Util.ReverseEnum(enumTable)[value];
    if (name == nil) then return "?"; end
    if (pretty ~= nil and pretty[name] ~= nil) then return pretty[name]; end
    return CS.Util.SplitCamel(name);
end

------------------------------------------------------------------------
-- EQUIPMENT SLOTS
------------------------------------------------------------------------

-- Resolves CS.EQUIP_GROUPS slot keys to numbers (entry.slot), removes
-- duplicates (Shield = SecondaryWeapon, Instrument = RangedWeapon) and
-- appends unknown future slots to the last group.
function CS.Util.ResolveSlots()
    local eq = Turbine.Gameplay.Equipment;
    local seen = { };
    for _, group in ipairs(CS.EQUIP_GROUPS) do
        local kept = { };
        for _, entry in ipairs(group.slots) do
            local n = CS.Util.Field(eq, entry.key);
            if (type(n) ~= "number" and entry.alt ~= nil) then
                n = CS.Util.Field(eq, entry.alt);
            end
            if (type(n) == "number" and not seen[n]) then
                seen[n] = true;
                entry.slot = n;
                table.insert(kept, entry);
            end
        end
        group.slots = kept;
    end

    local extra = { };
    pcall(function()
        for key, n in pairs(eq) do
            if (type(key) == "string" and type(n) == "number" and n > 0 and not seen[n]) then
                seen[n] = true;
                table.insert(extra, { key = key, label = CS.Util.SplitCamel(key), slot = n });
            end
        end
    end);
    table.sort(extra, function(a, b) return a.slot < b.slot; end);
    local last = CS.EQUIP_GROUPS[#CS.EQUIP_GROUPS];
    for _, entry in ipairs(extra) do
        table.insert(last.slots, entry);
    end
end

------------------------------------------------------------------------
-- FORMATTING
------------------------------------------------------------------------

function CS.Util.Clamp(v, lo, hi)
    if (v < lo) then return lo; end
    if (v > hi) then return hi; end
    return v;
end

-- Rounded integer without separators (used for chat).
function CS.Util.FormatPlain(v)
    if (type(v) ~= "number") then return "?"; end
    return string.format("%.0f", math.floor(v + 0.5));
end

-- Rounded integer with "," thousands separators.
function CS.Util.FormatInt(v)
    if (type(v) ~= "number") then return "?"; end
    local n = math.floor(v + 0.5);
    local digits = string.format("%.0f", math.abs(n));
    local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")));
    if (string.sub(out, 1, 1) == ",") then out = string.sub(out, 2); end
    if (n < 0) then out = "-" .. out; end
    return out;
end

function CS.Util.FormatNumber(v, fmt)
    if (type(v) ~= "number") then return "?"; end
    if (fmt == "dec1") then return string.format("%.1f", v); end
    return CS.Util.FormatInt(v);
end

-- Copper -> "12g 345s 67c" (GetMoneyComponents is avoided: its order is uncertain).
function CS.Util.FormatMoney(copper)
    if (type(copper) ~= "number") then return "?"; end
    copper = math.floor(copper);
    local g = math.floor(copper / 100000);
    local s = math.floor((copper % 100000) / 100);
    local c = copper % 100;
    if (g > 0) then
        return CS.Util.FormatInt(g) .. "g " .. s .. "s " .. c .. "c";
    elseif (s > 0) then
        return s .. "s " .. c .. "c";
    end
    return c .. "c";
end

-- Strips markup and characters that would break an alias / chat line.
function CS.Util.SanitizeChat(s)
    if (s == nil) then return ""; end
    s = tostring(s);
    s = string.gsub(s, "<[^>]*>", "");
    s = string.gsub(s, "[\r\n\t]", " ");
    s = string.gsub(s, ";", ",");
    s = string.gsub(s, "%s+", " ");
    s = string.gsub(s, "^%s+", "");
    s = string.gsub(s, "%s+$", "");
    return s;
end

--[[
    Text from a game getter (GetName, GetDescription, ...), ready to show.
    For a missing localised string the client returns a placeholder like
    "<string table error: tableDID [0x..] token [0x..]>" (seen in game on
    ItemInfo:GetDescription). Such segments are removed (up to ">" or the
    end of the line, the ">" may be missing); "" if s is not a string or
    nothing meaningful remains.
]]
local STRING_TABLE_ERROR = "string table error";

function CS.Util.CleanGameText(s)
    if (type(s) ~= "string") then return ""; end
    while (true) do
        local a, b = string.find(string.lower(s), STRING_TABLE_ERROR, 1, true);
        if (a == nil) then break; end
        if (a > 1 and string.sub(s, a - 1, a - 1) == "<") then a = a - 1; end
        local e = string.find(s, ">", b + 1, true);
        local nl = string.find(s, "\n", b + 1, true);
        if (nl ~= nil and (e == nil or nl < e)) then e = nl - 1; end
        if (e == nil) then e = string.len(s); end
        s = string.sub(s, 1, a - 1) .. string.sub(s, e + 1);
    end
    s = string.gsub(s, "^%s+", "");
    s = string.gsub(s, "%s+$", "");
    -- letters / digits (any UTF-8 multibyte character counts as a letter)
    if (not string.find(s, "[%w\128-\255]")) then return ""; end
    return s;
end

-- First bytes of s, at most maxBytes long, never ending inside a UTF-8
-- multibyte sequence (continuation bytes are 0x80..0xBF).
function CS.Util.Utf8Truncate(s, maxBytes)
    if (string.len(s) <= maxBytes) then return s; end
    local n = math.max(0, maxBytes);
    while (n > 0) do
        local b = string.byte(s, n + 1);
        if (b == nil or b < 0x80 or b >= 0xC0) then break; end
        n = n - 1;
    end
    return string.sub(s, 1, n);
end

-- Number of characters (not bytes) in a UTF-8 string.
function CS.Util.Utf8Len(s)
    local _, count = string.gsub(s, "[^\128-\191]", "");
    return count;
end

-- First nChars characters (not bytes) of a UTF-8 string.
function CS.Util.Utf8Prefix(s, nChars)
    if (nChars <= 0) then return ""; end
    local count = 0;
    for i = 1, string.len(s) do
        local b = string.byte(s, i);
        if (b < 0x80 or b >= 0xC0) then
            count = count + 1;
            if (count > nChars) then return string.sub(s, 1, i - 1); end
        end
    end
    return s;
end

-- Text for a single-line label of the given width: cut at a character
-- boundary with "..." when the estimated width (charW per character)
-- does not fit.
function CS.Util.FitText(text, width, charW)
    if (text == nil) then return ""; end
    local maxChars = math.floor(width / charW);
    if (CS.Util.Utf8Len(text) <= maxChars) then return text; end
    if (maxChars <= 3) then return CS.Util.Utf8Prefix(text, math.max(0, maxChars)); end
    local cut = string.gsub(CS.Util.Utf8Prefix(text, maxChars - 3), "[%s,;:/%-]+$", "");
    return cut .. "...";
end

-- Profession titles come back as "<player name>, Westemnet Farmer"
-- (seen in game): drops a leading "<name>," or "<name>:" (case-insensitive;
-- "" if nothing follows).
function CS.Util.StripNamePrefix(text, name)
    if (type(text) ~= "string" or type(name) ~= "string" or name == "") then return text; end
    local n = string.len(name);
    if (string.lower(string.sub(text, 1, n)) ~= string.lower(name)) then return text; end
    local rest = string.match(string.sub(text, n + 1), "^%s*[,:]%s*(.*)$");
    if (rest == nil) then return text; end
    return rest;
end

-- Rough number of wrapped lines for a multiline label.
function CS.Util.EstimateLines(text, width, charW)
    if (text == nil or text == "") then return 1; end
    local perLine = math.max(1, math.floor(width / charW));
    local total = 0;
    for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
        total = total + math.max(1, math.ceil(CS.Util.Utf8Len(paragraph) / perLine));
    end
    return math.max(1, total);
end

-- label:SetText only when the text changed (avoids redundant API calls).
function CS.Util.SetText(label, text)
    if (label.csText == text) then return false; end
    label.csText = text;
    label:SetText(text);
    return true;
end

------------------------------------------------------------------------
-- CHANNELS
------------------------------------------------------------------------

function CS.Util.FindChannel(id)
    for _, ch in ipairs(CS.CHANNELS) do
        if (ch.id == id) then return ch; end
    end
    return nil;
end

-- Chat command of a channel in the client language.
function CS.Util.ChannelCommand(id)
    local ch = CS.Util.FindChannel(id) or CS.CHANNELS[1];
    local french = CS.Util.Field(Turbine.Language, "French");
    local ok, lang = pcall(Turbine.Engine.GetLanguage);
    if (ok and french ~= nil and lang == french and CS.CHANNELS_FR[ch.id] ~= nil) then
        return CS.CHANNELS_FR[ch.id];
    end
    return ch.cmd;
end
