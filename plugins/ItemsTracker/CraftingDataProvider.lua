--[[=========================================================================

    ItemsTracker -- CraftingDataProvider.lua
    Crafting data for the craft calculator: learned professions, the XP
    left to the current or to a selected earlier tier (the tier selector:
    the next level is reached, but the mastery of the previous one is
    still to be earned), the recipes of that tier and their direct
    ingredients. Pure functions (no UI); only defines ITR.CraftData when
    it is imported - everything runs later, from ITR.Craft.Init.

    "THE BEER-WARE LICENSE" (Revision 42):
    https://github.com/EBCEYS wrote this file. As long as you retain this
    notice you can do whatever you want with it. If we meet some day, and
    you think this stuff is worth it, you can buy me a beer in return.

=========================================================================]]

ITR.CraftData = { };

local D = ITR.CraftData;

D.MAX_RECIPES     = 5000;   -- GetRecipeCount is clamped to this
D.MAX_INGREDIENTS = 50;     -- GetIngredientCount is clamped to this

-- status of a selectable tier (D.TierStatus)
D.TIER_DONE         = "done";         -- the whole tier is completed
D.TIER_MASTERY_LEFT = "masteryleft";  -- proficiency done, mastery still open
D.TIER_CURRENT      = "current";      -- the tier the XP currently goes to

-- ProfessionInfo events (documented, unverified in game: the args are
-- not documented and never read)
D.PROGRESS_EVENTS = {
    "ProficiencyExperienceChanged", "MasteryExperienceChanged",
    "ProficiencyLevelChanged", "MasteryLevelChanged",
    "ProficiencyExperienceTargetChanged", "MasteryExperienceTargetChanged",
};
D.RECIPE_EVENTS = { "RecipeAdded", "RecipeRemoved" };

D.hooks = { };

------------------------------------------------------------------------
-- ATTRIBUTES / PROFESSIONS
------------------------------------------------------------------------

-- The player's attributes if they can tell professions: attrs, nil -
-- else nil, reason ("noplayer", "noattrs", "monster").
function D.GetAttributes()
    local ok, player = pcall(Turbine.Gameplay.LocalPlayer.GetInstance);
    if (not ok or player == nil) then return nil, "noplayer"; end
    local attrs = ITR.Call(player, "GetAttributes");
    if (attrs == nil) then return nil, "noattrs"; end
    -- MonsterPlayerAttributes has no GetProfessionInfo
    if (type(ITR.Field(attrs, "GetProfessionInfo")) ~= "function") then return nil, "monster"; end
    return attrs, nil;
end

-- ProfessionInfo of a Turbine.Gameplay.Profession value, or nil.
function D.GetProfessionInfo(value, attrs)
    if (type(value) ~= "number") then return nil; end
    if (attrs == nil) then attrs = D.GetAttributes(); end
    return (ITR.Call(attrs, "GetProfessionInfo", value));
end

-- { [enumName] = value } of Turbine.Gameplay.Profession without
-- Undefined (0) and IsA.
function D.ProfessionValues()
    local out = { };
    local enum = ITR.Field(Turbine.Gameplay, "Profession");
    if (enum == nil) then return out; end
    pcall(function()
        for name, value in pairs(enum) do
            if (type(name) == "string" and type(value) == "number" and value ~= 0) then out[name] = value; end
        end
    end);
    return out;
end

-- true if value is a learned-or-not profession value of the enum.
function D.IsProfessionValue(value)
    if (type(value) ~= "number" or value == 0) then return false; end
    for _, v in pairs(D.ProfessionValues()) do
        if (v == value) then return true; end
    end
    return false;
end

-- Used when a profession reports no name: real Turbine.Gameplay.Profession
-- names have no inner camel case ("Jeweller", "Weaponsmith"), so the split
-- is only a fallback for an unexpected enum name and usually a no-op.
function D.SplitName(enumName)
    return (string.gsub(enumName, "(%l)(%u)", "%1 %2"));
end

-- Learned professions sorted by name: { value, enumName, name, info,
-- profLevel, mastLevel } each; nil, reason if the attributes are missing.
function D.ListProfessions()
    local attrs, reason = D.GetAttributes();
    if (attrs == nil) then return nil, reason; end
    local list = { };
    for enumName, value in pairs(D.ProfessionValues()) do
        local info = D.GetProfessionInfo(value, attrs);
        if (info ~= nil) then
            local name = ITR.CleanGameText(ITR.Call(info, "GetName"));
            if (name == "") then name = D.SplitName(enumName); end
            table.insert(list, { value = value, enumName = enumName, name = name, info = info,
                profLevel = ITR.WholeNumber(ITR.Call(info, "GetProficiencyLevel")),
                mastLevel = ITR.WholeNumber(ITR.Call(info, "GetMasteryLevel")) });
        end
    end
    table.sort(list, function(a, b)
        local la, lb = string.lower(a.name), string.lower(b.name);
        if (la ~= lb) then return la < lb; end
        return a.value < b.value;
    end);
    return list, nil;
end

------------------------------------------------------------------------
-- PROGRESS / TARGET TIER
------------------------------------------------------------------------

-- { pl, px, pt, ml, mx, mt }: proficiency / mastery level, experience
-- and experience target (whole numbers or nil).
function D.ReadProgress(info)
    local W, C = ITR.WholeNumber, ITR.Call;
    return {
        pl = W(C(info, "GetProficiencyLevel")),
        px = W(C(info, "GetProficiencyExperience")),
        pt = W(C(info, "GetProficiencyExperienceTarget")),
        ml = W(C(info, "GetMasteryLevel")),
        mx = W(C(info, "GetMasteryExperience")),
        mt = W(C(info, "GetMasteryExperienceTarget")),
    };
end

-- XP left in one bar; a target of 0 (maxed out) leaves nothing.
local function Left(x, target)
    if (target <= 0) then return 0; end
    return math.max(0, target - x);
end

--[[
    targetTier, expNeeded, phase, ok for mode "prof", "mast" or "full".
    The levels are the completed tiers, so the tier worked on is
    level + 1. "full": the rest of the proficiency of that tier plus its
    whole mastery, or (proficiency done) the rest of the mastery. phase =
    the bar the XP currently goes to. ok = false if a value is missing.
]]
function D.ComputeTarget(p, mode)
    if (type(p) ~= "table") then return nil, 0, nil, false; end
    if (mode == "prof") then
        if (p.pl == nil or p.px == nil or p.pt == nil) then return nil, 0, "prof", false; end
        return p.pl + 1, Left(p.px, p.pt), "prof", true;
    elseif (mode == "mast") then
        if (p.ml == nil or p.mx == nil or p.mt == nil) then return nil, 0, "mast", false; end
        return p.ml + 1, Left(p.mx, p.mt), "mast", true;
    elseif (mode == "full") then
        if (p.pl == nil or p.px == nil or p.pt == nil or p.ml == nil or p.mx == nil or p.mt == nil) then
            return nil, 0, nil, false;
        end
        local tier = p.ml + 1;
        if (p.pl < tier) then
            if (p.pt <= 0) then return tier, 0, "prof", true; end
            return tier, math.max(0, p.pt - p.px) + math.max(0, p.mt), "prof", true;
        end
        return tier, Left(p.mx, p.mt), "mast", true;
    end
    return nil, 0, nil, false;
end

-- Crafts needed for expNeeded XP at xp per craft (0 if nothing is needed).
function D.CraftsNeeded(expNeeded, xp)
    if (type(expNeeded) ~= "number" or type(xp) ~= "number" or expNeeded <= 0 or xp <= 0) then return 0; end
    return math.ceil(expNeeded / xp);
end

-- The highest tier the character can currently craft in: max(pl + 1,
-- ml + 1) (ml > pl is not expected, the max is defensive). nil if no
-- level is readable. A maxed profession keeps going one tier past its
-- levels - with targets of 0 that tier shows "complete", like today.
function D.ComputeActiveTier(p)
    if (type(p) ~= "table") then return nil; end
    if (p.pl == nil and p.ml == nil) then return nil; end
    return math.max((p.pl or 0) + 1, (p.ml or 0) + 1);
end

-- Status of a selectable tier: done (both phases completed),
-- "masteryleft" (proficiency done, its mastery still open - the tier the
-- tier selector exists for) or "current" (the active tier). nil when
-- the tier is not selectable (p unreadable, tier < 1 or > active tier).
-- A maxed profession (both targets 0) has nothing left in its active
-- tier either: that tier is "done" too, not "current".
function D.TierStatus(p, tier)
    if (type(p) ~= "table" or type(tier) ~= "number" or tier < 1) then return nil; end
    local active = D.ComputeActiveTier(p);
    if (active == nil or tier > active) then return nil; end
    if (p.pl ~= nil and p.ml ~= nil and tier <= math.min(p.pl, p.ml)) then return D.TIER_DONE; end
    if (p.pl ~= nil and tier <= p.pl) then return D.TIER_MASTERY_LEFT; end
    if ((p.pt or 1) <= 0 and (p.mt or 1) <= 0) then return D.TIER_DONE; end
    return D.TIER_CURRENT;
end

--[[
    targetTier, expNeeded, phase, ok, live for mode "prof", "mast" or
    "full" and a SELECTED tier; tier nil = the auto tier of the mode (the
    ComputeTarget result). The API exposes one live bar per phase, tied
    to the tier currently being advanced, so a selectable tier is in one
    of three states: live - the tier is that bar, need > 0 (the auto tier
    behaves exactly like ComputeTarget); complete - the phase of that
    tier is already done, need 0; unknown - a skipped mastery the API
    cannot report (only in "mast" / "full", tier > ml + 1): need = nil,
    the recipes are still readable but no crafts number can be computed.
    ok = false if a needed value is missing. A "prof" tier beyond
    pl + 1 (only selectable when ml > pl) counts as complete.

    Nil-tier contract: only C.ComputeView passes nil (and it derives
    live from need itself, like for the auto tier); C.LiveCheck always
    passes the numeric applied tier. For a nil tier in "full" with a
    finished proficiency target (pt <= 0 < mt) this returns the whole
    mastery target where ComputeTarget returns 0 - no shipped call path
    hits that, and ComputeTarget stays authoritative for the auto tier.
]]
function D.ComputeSelectedTarget(p, mode, tier)
    if (type(p) ~= "table") then return nil, nil, nil, false, false; end
    if (mode == "prof") then
        if (p.pl == nil or p.px == nil or p.pt == nil) then return nil, nil, "prof", false, false; end
        local t = (tier ~= nil) and tier or (p.pl + 1);
        if (t ~= p.pl + 1) then return t, 0, "prof", true, false; end
        local need = Left(p.px, p.pt);
        return t, need, "prof", true, need > 0;
    elseif (mode == "mast") then
        if (p.ml == nil or p.mx == nil or p.mt == nil) then return nil, nil, "mast", false, false; end
        local t = (tier ~= nil) and tier or (p.ml + 1);
        if (t <= p.ml) then return t, 0, "mast", true, false; end
        if (t == p.ml + 1) then
            local need = Left(p.mx, p.mt);
            return t, need, "mast", true, need > 0;
        end
        return t, nil, "mast", true, false;   -- skipped mastery: not readable
    elseif (mode == "full") then
        if (p.pl == nil or p.px == nil or p.pt == nil or p.ml == nil or p.mx == nil or p.mt == nil) then
            return nil, nil, nil, false, false;
        end
        local t = (tier ~= nil) and tier or (p.ml + 1);
        if (t <= p.ml and t <= p.pl) then return t, 0, "mast", true, false; end
        local profPart, phase = 0, "mast";
        if (t > p.pl) then
            profPart = math.max(0, p.pt - p.px);
            phase = "prof";
        end
        -- the mastery bar only covers the tier in progress: while the
        -- proficiency of the tier still runs its mastery has not begun
        -- (whole target), once it is done the bar is this tier's (rest)
        local mastPart = nil;
        if (t <= p.ml) then mastPart = 0;
        elseif (t == p.ml + 1) then
            mastPart = (t > p.pl) and math.max(0, p.mt) or Left(p.mx, p.mt);
        end
        if (mastPart == nil) then return t, nil, phase, true, false; end
        local need = profPart + mastPart;
        return t, need, phase, true, need > 0;
    end
    return nil, nil, nil, false, false;
end

------------------------------------------------------------------------
-- RECIPES
------------------------------------------------------------------------

--[[
    Index base of a getter (GetRecipe / GetIngredient) with "count"
    entries: not documented. 1-based is assumed; 0-based if the last
    1-based index gives nothing but index 0 does. Only these probes may
    throw (Call returns nil then).
]]
function D.ProbeBase(obj, getter, count)
    if (count <= 0) then return 1; end
    if (ITR.Call(obj, getter, count) == nil and ITR.Call(obj, getter, 0) ~= nil) then return 0; end
    return 1;
end

-- All recipes of a profession: list of { recipe, name, lname, tier, xp,
-- singleUse, cooldown, index }, and diag = { count, base, nilCount,
-- unnamed, tiers = { [tier] = recipes with XP } }.
function D.ReadRecipes(info)
    local W, C = ITR.WholeNumber, ITR.Call;
    local list = { };
    local diag = { count = 0, base = 1, nilCount = 0, unnamed = 0, tiers = { } };
    diag.count = ITR.Clamp(W(C(info, "GetRecipeCount")) or 0, 0, D.MAX_RECIPES);
    diag.base = D.ProbeBase(info, "GetRecipe", diag.count);
    for i = diag.base, diag.base + diag.count - 1 do
        local r = C(info, "GetRecipe", i);
        if (r == nil) then
            diag.nilCount = diag.nilCount + 1;
        else
            local name = ITR.CleanGameText(C(r, "GetName"));
            if (name == "") then
                diag.unnamed = diag.unnamed + 1;
                name = "(unnamed recipe)";
            end
            local e = { recipe = r, name = name, lname = string.lower(name), index = #list + 1,
                tier = W(C(r, "GetTier")), xp = W(C(r, "GetExperienceReward")),
                singleUse = (C(r, "IsSingleUse") == true), cooldown = W(C(r, "GetCooldown")) };
            table.insert(list, e);
            if (e.tier ~= nil and e.xp ~= nil and e.xp > 0) then
                diag.tiers[e.tier] = (diag.tiers[e.tier] or 0) + 1;
            end
        end
    end
    return list, diag;
end

-- Recipes of "tier" that give XP, sorted by "xp" (descending, then name)
-- or "name" (then XP descending). The index tie-break keeps the order
-- strict ("invalid order function" never happens).
function D.FilterRecipes(list, tier, sortKey)
    local out = { };
    if (type(list) ~= "table" or type(tier) ~= "number") then return out; end
    for _, e in ipairs(list) do
        if (e.tier == tier and e.xp ~= nil and e.xp > 0) then table.insert(out, e); end
    end
    if (sortKey == "name") then
        table.sort(out, function(a, b)
            if (a.lname ~= b.lname) then return a.lname < b.lname; end
            if (a.xp ~= b.xp) then return a.xp > b.xp; end
            return a.index < b.index;
        end);
    else
        table.sort(out, function(a, b)
            if (a.xp ~= b.xp) then return a.xp > b.xp; end
            if (a.lname ~= b.lname) then return a.lname < b.lname; end
            return a.index < b.index;
        end);
    end
    return out;
end

------------------------------------------------------------------------
-- INGREDIENTS
------------------------------------------------------------------------

--[[
    The required (direct) ingredients of a recipe, grouped by name in
    first-seen order: list of { name, perCraft, info, quality }, the
    number skipped for an unreadable name, and diag = { count, base,
    nilCount, skipped, qtyDefaulted }. RecipeIngredient has no
    IsOptional(): only GetIngredient(1..GetIngredientCount()) is read,
    never the optional ingredients or the ingredient pack.
]]
function D.ReadIngredients(recipe)
    local W, C = ITR.WholeNumber, ITR.Call;
    local list, byName = { }, { };
    local diag = { count = 0, base = 1, nilCount = 0, skipped = 0, qtyDefaulted = 0 };
    diag.count = ITR.Clamp(W(C(recipe, "GetIngredientCount")) or 0, 0, D.MAX_INGREDIENTS);
    diag.base = D.ProbeBase(recipe, "GetIngredient", diag.count);
    for i = diag.base, diag.base + diag.count - 1 do
        local ing = C(recipe, "GetIngredient", i);
        if (ing == nil) then
            diag.nilCount = diag.nilCount + 1;
        else
            local info = C(ing, "GetItemInfo");
            local name = ITR.CleanGameText(C(info, "GetName"));
            if (name == "") then
                diag.skipped = diag.skipped + 1;
            else
                local q = W(C(ing, "GetRequiredQuantity"));
                if (q == nil or q < 1) then
                    q = 1;
                    diag.qtyDefaulted = diag.qtyDefaulted + 1;
                end
                local e = byName[name];
                if (e ~= nil) then
                    e.perCraft = e.perCraft + q;
                else
                    e = { name = name, perCraft = q, info = info, quality = W(C(info, "GetQuality")) };
                    byName[name] = e;
                    table.insert(list, e);
                end
            end
        end
    end
    return list, diag.skipped, diag;
end

-- Targets for the tracker: { { name, qty, info } ... } (qty not clamped).
function D.BuildTargets(ingredients, crafts)
    local out = { };
    if (type(ingredients) ~= "table" or type(crafts) ~= "number" or crafts <= 0) then return out; end
    for _, e in ipairs(ingredients) do
        table.insert(out, { name = e.name, qty = e.perCraft * crafts, info = e.info });
    end
    return out;
end

------------------------------------------------------------------------
-- EVENT HOOKS (own list; same pattern as Main.lua's backpack hooks)
--
-- ProfessionInfo objects may be shared with other plugins: the previous
-- handler keeps being called, and on unhook ours is removed (or, if
-- another plugin chained on top of it, turned into a pass-through).
------------------------------------------------------------------------

function D.Hook(object, eventName, fn)
    if (object == nil) then return; end
    local h = { object = object, name = eventName, active = true };
    local okPrev, prev = pcall(function() return object[eventName]; end);
    h.prev = okPrev and prev or nil;
    h.wrapper = function(sender, args)
        if (type(h.prev) == "function") then pcall(h.prev, sender, args); end
        if (h.active) then pcall(fn, sender, args); end
    end;
    pcall(function() object[eventName] = h.wrapper; end);
    table.insert(D.hooks, h);
end

function D.UnhookAll()
    local hooks = D.hooks;
    D.hooks = { };
    for i = #hooks, 1, -1 do
        local h = hooks[i];
        h.active = false;
        pcall(function()
            if (h.object[h.name] == h.wrapper) then h.object[h.name] = h.prev; end
        end);
    end
end
