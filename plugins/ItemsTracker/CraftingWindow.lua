--[[=========================================================================

    ItemsTracker -- CraftingWindow.lua
    The craft calculator window: profession / mode / recipe selectors,
    the ingredient preview, "Apply to tracker" (a pick mode in the main
    window: empty slots are highlighted there and assigned by click,
    Main.lua AUTO TARGETS), live updates on XP changes, and the
    calculator's per-character data. Only defines ITR.Craft when it is
    imported; Main.lua runs ITR.Craft.Init (in pcall) after its BOOT.

    "THE BEER-WARE LICENSE" (Revision 42):
    https://github.com/EBCEYS wrote this file. As long as you retain this
    notice you can do whatever you want with it. If we meet some day, and
    you think this stuff is worth it, you can buy me a beer in return.

=========================================================================]]

ITR.Craft = { ready = false };

local C = ITR.Craft;
local D = ITR.CraftData;

C.SAVE_KEY = "ItemsTrackerCraft";        -- per character

C.WIN_W, C.WIN_H = 360, 494;
C.PAD_X          = 20;
C.INNER_W        = 320;
C.LIST_W         = 310;                  -- list width, the scroll bar is right of it
C.ROW_H          = 18;
C.RECIPE_ROWS    = 8;
C.INGR_ROWS      = 6;

C.CHECK_INTERVAL       = 0.25;           -- s between ticker checks
C.POLL_INTERVAL        = 3;              -- s: progress poll (events are unverified)
C.RECIPE_POLL_INTERVAL = 30;             -- s: recipe count poll
C.SAVE_DELAY           = 2;              -- s after a window move

-- the ListBox scrolls with the mouse wheel by itself (CharacterStats);
-- set to true if it does not in game: then the rows scroll it through
-- EnsureVisible (the bound scroll bar is never read or set)
C.WHEEL_FALLBACK = false;
C.WHEEL_STEPS    = 2;

C.MODES     = { "prof", "mast", "full" };
C.MODE_TEXT = { prof = "Proficiency", mast = "Mastery", full = "Full tier" };
C.MODE_DONE = { prof = "proficiency", mast = "mastery", full = "proficiency and mastery" };
C.NO_DATA   = { noplayer = true, noattrs = true, monster = true };

-- row backgrounds (4 arguments = ARGB)
C.COL_NONE      = Turbine.UI.Color(0, 0, 0, 0);
C.COL_ROW_HOVER = Turbine.UI.Color(0.55, 0.30, 0.27, 0.18);

------------------------------------------------------------------------
-- PERSISTENCE (Character scope; names stored with ITR.EncodeText)
------------------------------------------------------------------------

function C.ReadBool(v, default)
    if (v == true or v == "true") then return true; end
    if (v == false or v == "false") then return false; end
    return default;
end

function C.ReadApplied(a)
    if (type(a) ~= "table") then return nil; end
    local W = ITR.WholeNumber;
    local r = { prof = W(a.prof), mode = a.mode, tier = W(a.tier), xp = W(a.xp), crafts = W(a.crafts),
        done = C.ReadBool(a.done, false) };
    if (not D.IsProfessionValue(r.prof) or type(r.mode) ~= "string" or C.MODE_TEXT[r.mode] == nil
        or r.tier == nil or r.xp == nil or r.xp < 1 or r.crafts == nil or r.crafts < 0
        or type(a.name) ~= "string") then
        return nil;
    end
    r.name = ITR.DecodeText(a.name);
    if (r.name == "") then return nil; end
    return r;
end

function C.LoadData()
    local ok, saved = pcall(Turbine.PluginData.Load, Turbine.DataScope.Character, C.SAVE_KEY);
    if (not ok or type(saved) ~= "table") then saved = { }; end
    local W = ITR.WholeNumber;
    local d = { };
    d.winX, d.winY = W(saved.winX), W(saved.winY);
    if (d.winX == nil or d.winY == nil) then d.winX, d.winY = nil, nil; end
    d.visible = C.ReadBool(saved.visible, false);
    d.prof = W(saved.prof);
    if (not D.IsProfessionValue(d.prof)) then d.prof = nil; end
    d.mode = (type(saved.mode) == "string" and C.MODE_TEXT[saved.mode] ~= nil) and saved.mode or "prof";
    d.sort = (saved.sort == "name") and "name" or "xp";
    local selXp = W(saved.selXp);
    if (type(saved.selName) == "string" and selXp ~= nil) then
        d.selName, d.selXp = ITR.DecodeText(saved.selName), selXp;
    end
    d.applied = C.ReadApplied(saved.applied);
    return d;
end

function C.Save()
    local st = ITR.craft;
    if (st == nil or st.data == nil) then return; end
    pcall(function()
        local d = st.data;
        local w = ITR.craftWin;
        if (w ~= nil and st.placed) then
            d.winX, d.winY = math.floor(w:GetLeft()), math.floor(w:GetTop());
        end
        local out = { winX = d.winX, winY = d.winY, visible = d.visible, prof = d.prof, mode = d.mode,
            sort = d.sort };
        if (d.selName ~= nil) then out.selName, out.selXp = ITR.EncodeText(d.selName), d.selXp; end
        local a = d.applied;
        if (a ~= nil) then
            out.applied = { prof = a.prof, mode = a.mode, tier = a.tier, name = ITR.EncodeText(a.name),
                xp = a.xp, crafts = a.crafts, done = a.done };
        end
        Turbine.PluginData.Save(Turbine.DataScope.Character, C.SAVE_KEY, out, nil);
    end);
end

------------------------------------------------------------------------
-- PROFESSION DATA (cached recipes, hooks, dirty flags)
------------------------------------------------------------------------

-- ProfessionInfo of a profession value: the hooked one, else a fresh one.
function C.Info(value)
    local st = ITR.craft;
    if (value == nil) then return nil; end
    return st.infos[value] or D.GetProfessionInfo(value);
end

-- Cached recipe list { list, diag } of a profession (read once per change).
function C.Recipes(value)
    local st = ITR.craft;
    if (value == nil) then return nil; end
    local c = st.cache[value];
    if (c == nil) then
        local info = C.Info(value);
        if (info == nil) then return nil; end
        local list, diag = D.ReadRecipes(info);
        c = { list = list, diag = diag };
        st.cache[value] = c;
    end
    return c;
end

-- Ingredients of a recipe entry { list, skipped, diag } (read once per entry).
function C.Ingredients(entry)
    if (entry.ingr == nil) then
        local list, skipped, diag = D.ReadIngredients(entry.recipe);
        entry.ingr = { list = list, skipped = skipped, diag = diag };
    end
    return entry.ingr;
end

-- The cached entry with this tier, name and XP, or nil.
function C.FindEntry(list, tier, name, xp)
    if (type(list) ~= "table") then return nil; end
    for _, e in ipairs(list) do
        if (e.tier == tier and e.name == name and e.xp == xp) then return e; end
    end
    return nil;
end

function C.MarkProgressDirty(value)
    local st = ITR.craft;
    if (st == nil) then return; end
    if (value == st.data.prof) then st.viewDirty = true; end
    local a = st.data.applied;
    if (a ~= nil and value == a.prof) then st.liveDirty = true; end
end

function C.MarkRecipesDirty(value)
    local st = ITR.craft;
    if (st == nil) then return; end
    st.cache[value] = nil;   -- read again when it is needed
    C.MarkProgressDirty(value);
end

--[[
    Hooks the events of the selected profession and of the applied one
    (live targets keep running while another profession is browsed). A
    fresh ProfessionInfo is taken each time and kept in st.infos (its
    events only fire while it is referenced). Called on Init, profession
    switch, apply, clear, applied -> done, and on every show.
]]
function C.RehookProfessions()
    local st = ITR.craft;
    D.UnhookAll();
    st.infos = { };
    if (st.unloaded) then return; end
    local d = st.data;
    local set = { };
    if (d.prof ~= nil) then set[d.prof] = true; end
    if (d.applied ~= nil and not d.applied.done) then set[d.applied.prof] = true; end
    local attrs = D.GetAttributes();
    if (attrs == nil) then return; end
    for value in pairs(set) do
        local info = D.GetProfessionInfo(value, attrs);
        if (info ~= nil) then
            st.infos[value] = info;
            local onProgress = function() C.MarkProgressDirty(value); end
            local onRecipes = function() C.MarkRecipesDirty(value); end
            for _, name in ipairs(D.PROGRESS_EVENTS) do D.Hook(info, name, onProgress); end
            for _, name in ipairs(D.RECIPE_EVENTS) do D.Hook(info, name, onRecipes); end
        end
    end
end

-- Poll fallback: progress of the hooked professions changed without an
-- event (and, with "recipes", the recipe count) -> dirty.
function C.Poll(recipes)
    local st = ITR.craft;
    for value, info in pairs(st.infos) do
        local p = D.ReadProgress(info);
        local snap = tostring(p.pl) .. "," .. tostring(p.px) .. "," .. tostring(p.pt) .. ","
            .. tostring(p.ml) .. "," .. tostring(p.mx) .. "," .. tostring(p.mt);
        if (st.snap[value] ~= snap) then
            st.snap[value] = snap;
            C.MarkProgressDirty(value);
        end
        if (recipes) then
            local c = st.cache[value];
            local n = ITR.Clamp(ITR.WholeNumber(ITR.Call(info, "GetRecipeCount")) or 0, 0, D.MAX_RECIPES);
            if (c ~= nil and c.diag.count ~= n) then C.MarkRecipesDirty(value); end
        end
    end
end

------------------------------------------------------------------------
-- VIEW (what the window shows; computed by Refresh)
------------------------------------------------------------------------

function C.ReloadProfessions()
    local st = ITR.craft;
    local profs, reason = D.ListProfessions();
    st.profs, st.profReason = profs, reason;
    local d = st.data;
    if (profs ~= nil and #profs > 0) then
        local found = false;
        for _, p in ipairs(profs) do
            if (p.value == d.prof) then found = true; end
        end
        if (not found) then
            d.prof = profs[1].value;
            C.Save();
        end
    end
    C.RehookProfessions();
end

function C.ComputeView()
    local st = ITR.craft;
    local d = st.data;
    local v = { list = { }, need = 0, crafts = 0 };
    st.view = v;
    if (st.profs == nil) then v.reason = st.profReason or "noattrs"; return v; end
    if (#st.profs == 0) then v.reason = "noprof"; return v; end
    v.progress = D.ReadProgress(C.Info(d.prof));
    v.tier, v.need, v.phase, v.ok = D.ComputeTarget(v.progress, d.mode);
    if (not v.ok) then v.reason = "noprogress"; v.need = 0; return v; end
    if (v.need <= 0) then v.reason = "complete"; return v; end
    local cache = C.Recipes(d.prof);
    v.list = D.FilterRecipes(cache and cache.list, v.tier, d.sort);
    if (d.selName ~= nil) then
        for _, e in ipairs(v.list) do
            if (e.name == d.selName and e.xp == d.selXp) then v.selected = e; break; end
        end
    end
    if (v.selected ~= nil) then
        v.crafts = D.CraftsNeeded(v.need, v.selected.xp);
        v.ingr = C.Ingredients(v.selected);
    end
    return v;
end

function C.CanApply()
    local v = ITR.craft.view;
    return (v ~= nil and v.selected ~= nil and v.ok == true and v.crafts > 0
        and v.ingr ~= nil and #v.ingr.list > 0);
end

-- "Farmer (P9 / M8)"
function C.ProfText(p)
    local function n(x) return (x ~= nil) and tostring(x) or "?"; end
    return p.name .. " (P" .. n(p.profLevel) .. " / M" .. n(p.mastLevel) .. ")";
end

function C.Plural(n, word)
    if (n == 1) then return n .. " " .. word; end
    return n .. " " .. word .. "s";
end

-- "Name (+42 | x12 crafts)" in maxBytes.
function C.RecipeText(e, crafts, maxBytes)
    local suffix;
    if (crafts > 0) then
        suffix = "(+" .. e.xp .. " | x" .. C.Plural(crafts, "craft") .. ")";
    else
        suffix = "(+" .. e.xp .. ")";
    end
    local name = ITR.Shorten(e.name, maxBytes - string.len(suffix) - 1);
    if (name == "") then return suffix; end
    return name .. " " .. suffix;
end

function C.InfoTexts(v, mode)
    if (v.reason ~= nil and (C.NO_DATA[v.reason] or v.reason == "noprof")) then return "", ""; end
    if (not v.ok) then return "Profession data not available", ""; end
    local what;
    if (mode == "prof") then what = "proficiency";
    elseif (mode == "mast") then what = "mastery";
    elseif (v.phase == "prof") then what = "(proficiency, then mastery)";
    else what = "(mastery)"; end
    local line = "Tier " .. v.tier .. " " .. what;
    if (v.need <= 0) then line = line .. ": complete"; else line = line .. ": " .. v.need .. " XP left"; end
    local p = v.progress;
    local function n(x) return (x ~= nil) and tostring(x) or "?"; end
    return line, "Proficiency " .. n(p.px) .. " / " .. n(p.pt) .. " - Mastery " .. n(p.mx) .. " / " .. n(p.mt);
end

function C.EmptyText(v)
    if (v.reason ~= nil and C.NO_DATA[v.reason]) then return "Crafting data is not available for this character."; end
    if (v.reason == "noprof") then return "This character has no crafting profession."; end
    if (v.reason == "noprogress") then return "Profession data is not available."; end
    if (v.reason == "complete") then return "Nothing left to earn in this mode (tier or profession complete)."; end
    return "No learned recipe of tier " .. tostring(v.tier)
        .. " gives XP. Learn recipes at a trainer. (/itr craft debug lists the tiers)";
end

-- Preview lines { text, colour } of the selected recipe.
function C.PreviewLines(v)
    local lines = { };
    local e = v.selected;
    local maxBytes = math.floor(C.LIST_W / ITR.NAME_CHAR_W);
    if (e == nil) then
        if (#v.list > 0) then
            table.insert(lines, { text = "Select a recipe to see its ingredients.", colour = ITR.COLOR_HINT });
        end
        return lines;
    end
    local ingr = v.ingr;
    for _, i in ipairs(ingr.list) do
        -- the state text is short (" - manual (999999)"): the name must
        -- stay visible in the row (a name budget is reserved below)
        local state, _, target = ITR.Tracker.GetNameState(i.name);
        local statetext = "";
        if (state == "manual") then statetext = " - manual (" .. tostring(target) .. ")";
        elseif (state == "auto") then statetext = " - auto";
        elseif (state == "tracked") then statetext = " - tracked";
        elseif (ITR.Tracker.IsPicking() and v.crafts > 0) then
            -- during the pick mode a not yet placed ingredient is
            -- shown just as clearly as an already tracked one
            statetext = " - not assigned";
        end
        local suffix;
        local maxNote = " (max " .. ITR.MAX_TARGET .. ")";
        if (v.crafts > 0) then
            local qty = i.perCraft * v.crafts;
            suffix = " x" .. qty;
            -- the "(max N)" note is dropped when qty plus the state text
            -- would eat the row: the name must stay visible
            if (qty > ITR.MAX_TARGET
                and string.len(suffix) + string.len(statetext) + string.len(maxNote) <= maxBytes - 8) then
                suffix = suffix .. maxNote;
            end
        else
            suffix = " x" .. i.perCraft .. " per craft";
        end
        suffix = suffix .. statetext;
        -- at least 8 bytes of the name (Shorten returns "" below that)
        local name = ITR.Shorten(i.name, math.max(8, maxBytes - string.len(suffix)));
        if (name == "") then name = "..."; end
        table.insert(lines, { text = name .. suffix,
            colour = ITR.QUALITY_COLOR[i.quality or -1] or ITR.COLOR_TEXT });
    end
    local hint = ITR.COLOR_HINT;
    if (#ingr.list == 0 and ingr.skipped == 0) then table.insert(lines, { text = "Recipe has no ingredients", colour = hint }); end
    if (ingr.skipped > 0) then
        table.insert(lines, { text = ingr.skipped .. " ingredient(s) without a readable name skipped", colour = hint });
    end
    if (e.singleUse) then table.insert(lines, { text = "Single-use recipe", colour = hint }); end
    if (e.cooldown ~= nil and e.cooldown > 0) then table.insert(lines, { text = "Recipe has a cooldown", colour = hint }); end
    return lines;
end

-- The pick-mode confirm report (ITR.Tracker.FinishPick): "Assigned 4 of
-- 6 ingredients: slots 2, 3, 5, 7". The picked slots are the interesting
-- part; a very long slot list is dropped so the 3-line status fits.
function C.ReportText(r)
    local text = "Assigned " .. r.assigned .. " of " .. r.total .. " ingredient";
    if (r.total ~= 1) then text = text .. "s"; end
    local slots = { };
    for _, e in ipairs(r.entries) do table.insert(slots, tostring(e.slot)); end
    if (#slots > 0 and #slots <= 8) then
        text = text .. ": slot" .. ((#slots == 1) and " " or "s ") .. table.concat(slots, ", ");
    end
    return text;
end

------------------------------------------------------------------------
-- WINDOW
------------------------------------------------------------------------

function C.NewLabel(x, y, w, h, font, colour)
    local l = Turbine.UI.Label();
    l:SetParent(ITR.craftWin);
    l:SetPosition(x, y);
    l:SetSize(w, h);
    l:SetFont(font or Turbine.UI.Lotro.Font.Verdana12);
    l:SetForeColor(colour or ITR.COLOR_TEXT);
    l:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    l:SetMultiline(false);
    ITR.Call(l, "SetMarkupEnabled", false);
    l:SetMouseVisible(false);
    l:SetText("");
    return l;
end

function C.NewButton(x, y, w, h, text, onClick)
    local b = Turbine.UI.Lotro.Button();
    b:SetParent(ITR.craftWin);
    b:SetPosition(x, y);
    b:SetSize(w, h);
    ITR.Call(b, "SetMarkupEnabled", false);
    b:SetText(text);
    b.Click = function()
        local ok, err = pcall(onClick);
        if (not ok) then C.SetStatus("Error: " .. tostring(err)); end
    end
    return b;
end

-- ListBox + bound scroll bar (never read or set: it is bound).
function C.NewList(y, rows)
    local lb = Turbine.UI.ListBox();
    lb:SetParent(ITR.craftWin);
    lb:SetPosition(C.PAD_X, y);
    lb:SetSize(C.LIST_W, rows * C.ROW_H);
    ITR.Call(lb, "SetOrientation", Turbine.UI.Orientation.Vertical);
    local bar = Turbine.UI.Lotro.ScrollBar();
    bar:SetOrientation(Turbine.UI.Orientation.Vertical);
    bar:SetParent(ITR.craftWin);
    bar:SetPosition(C.PAD_X + C.LIST_W, y);
    bar:SetSize(10, rows * C.ROW_H);
    lb:SetVerticalScrollBar(bar);
    if (C.WHEEL_FALLBACK) then lb.MouseWheel = function(sender, args) C.OnWheel(lb, args); end end
    return lb, bar;
end

-- Wheel fallback (CharacterStats OnWheel): rows found with GetItemAt,
-- scrolled with EnsureVisible.
function C.OnWheel(lb, args)
    if (type(args) ~= "table" or type(args.Direction) ~= "number" or args.Direction == 0) then return; end
    local count = lb:GetItemCount();
    if (count < 1) then return; end
    local function IndexAt(y)
        local item = ITR.Call(lb, "GetItemAt", 2, y);
        for i = 1, count do
            if (item ~= nil and lb:GetItem(i) == item) then return i; end
        end
        return nil;
    end
    local index;
    if (args.Direction > 0) then
        index = IndexAt(1);
        if (index ~= nil) then index = index - C.WHEEL_STEPS; end
    else
        index = IndexAt(math.max(1, lb:GetHeight() - 2));
        if (index ~= nil) then index = index + C.WHEEL_STEPS; end
    end
    if (index ~= nil) then ITR.Call(lb, "EnsureVisible", ITR.Clamp(index, 1, count)); end
end

-- A list row of the ListBox "listKey" (ITR.cw.recipes / ITR.cw.ingr).
function C.NewRow(clickable, listKey)
    local row = Turbine.UI.Label();
    row:SetSize(C.LIST_W, C.ROW_H);
    row:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    row:SetForeColor(ITR.COLOR_TEXT);
    row:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    row:SetMultiline(false);
    ITR.Call(row, "SetMarkupEnabled", false);
    row:SetBackColor(C.COL_NONE);
    row:SetMouseVisible(clickable or C.WHEEL_FALLBACK);
    if (C.WHEEL_FALLBACK) then
        row.MouseWheel = function(sender, args) C.OnWheel(ITR.cw[listKey], args); end
    end
    return row;
end

function C.NewRecipeRow()
    local row = C.NewRow(true, "recipes");
    row.MouseEnter = function(sender) sender.hover = true; C.PaintRow(sender); end
    row.MouseLeave = function(sender) sender.hover = false; C.PaintRow(sender); end
    row.MouseClick = function(sender, args)
        if (args ~= nil and args.Button ~= nil and args.Button ~= Turbine.UI.MouseButton.Left) then return; end
        if (sender.entry == nil) then return; end
        local ok, err = pcall(C.SelectRecipe, sender.entry);
        if (not ok) then C.SetStatus("Error: " .. tostring(err)); end
    end
    return row;
end

function C.PaintRow(row)
    local v = ITR.craft.view;
    if (v ~= nil and row.entry ~= nil and row.entry == v.selected) then
        row:SetBackColor(ITR.COL_SLOT_HOVER);
    elseif (row.hover) then
        row:SetBackColor(C.COL_ROW_HOVER);
    else
        row:SetBackColor(C.COL_NONE);
    end
end

function C.BuildWindow()
    local st = ITR.craft;
    local cw = { recipeRows = { }, ingrRows = { } };
    ITR.cw = cw;
    local w = Turbine.UI.Lotro.Window();
    ITR.craftWin = w;
    w:SetVisible(false);
    w:SetSize(C.WIN_W, C.WIN_H);
    -- short title: the LOTRO title bar clips long text
    w:SetText("Craft Calculator");
    ITR.Call(w, "SetResizable", false);

    local x, y = C.PAD_X, ITR.CONTENT_TOP;   -- y = 34: below the title bar
    local caption = Turbine.UI.Lotro.Font.Verdana14;

    C.NewLabel(x, y, 80, 20, caption):SetText("Profession:");
    cw.profBtn = C.NewButton(x + 80, y, 240, 20, "", C.ShowProfessionMenu);
    y = y + 24;
    C.NewLabel(x, y, 80, 20, caption):SetText("Mode:");
    cw.modeBtn = C.NewButton(x + 80, y, 240, 20, "", C.ShowModeMenu);
    y = y + 26;
    cw.info = C.NewLabel(x, y, C.INNER_W, 16);
    y = y + 16;
    cw.info2 = C.NewLabel(x, y, C.INNER_W, 16, nil, ITR.COLOR_HINT);
    y = y + 20;

    cw.recipesHeader = C.NewLabel(x, y, 240, 20, Turbine.UI.Lotro.Font.TrajanPro14, ITR.COLOR_HEADER);
    cw.sortBtn = C.NewButton(x + C.INNER_W - 70, y, 70, 20, "", C.ToggleSort);
    y = y + 20;
    cw.recipes, cw.recipeBar = C.NewList(y, C.RECIPE_ROWS);
    cw.recipesEmpty = C.NewLabel(x, y, C.LIST_W, 40, nil, ITR.COLOR_HINT);
    cw.recipesEmpty:SetMultiline(true);
    cw.recipesEmpty:SetTextAlignment(Turbine.UI.ContentAlignment.TopLeft);
    y = y + C.RECIPE_ROWS * C.ROW_H + 6;

    cw.ingrHeader = C.NewLabel(x, y, C.INNER_W, 20, Turbine.UI.Lotro.Font.TrajanPro14, ITR.COLOR_HEADER);
    y = y + 20;
    cw.ingr, cw.ingrBar = C.NewList(y, C.INGR_ROWS);
    y = y + C.INGR_ROWS * C.ROW_H + 4;

    cw.applyBtn = C.NewButton(x, y, 155, 20, "Apply to tracker", function() C.Apply(); end);
    cw.clearBtn = C.NewButton(x + 165, y, 155, 20, "Clear auto targets", function()
        if (ITR.Tracker.IsPicking()) then C.CancelPick(); else C.ClearAuto(); end
    end);
    y = y + 22;
    -- three lines: the pick mode's long status ("Pick slots: N to assign
    -- (A of T); M more empty slots needed ...") must not clip
    cw.status = C.NewLabel(x, y, C.INNER_W, 46, nil, ITR.COLOR_HINT);
    cw.status:SetMultiline(true);
    cw.status:SetTextAlignment(Turbine.UI.ContentAlignment.TopLeft);

    C.Place();
    w.PositionChanged = function()
        if (not st.applying and not st.unloaded) then
            st.saveAt = Turbine.Engine.GetGameTime() + C.SAVE_DELAY;
        end
    end
    w.VisibleChanged = function() pcall(C.OnVisibleChanged); end
    w.Closed = function() pcall(C.OnVisibleChanged); end
end

-- Saved / default position (first time), always kept on the screen.
function C.Place()
    local st, w = ITR.craft, ITR.craftWin;
    local x, y = w:GetLeft(), w:GetTop();
    if (not st.placed) then
        x, y = st.data.winX, st.data.winY;
        if (x == nil or y == nil) then
            local mw = ITR.GetMainWindow();
            x, y = mw:GetLeft() + mw:GetWidth() + 8, mw:GetTop();
        end
        st.placed = true;
    end
    x, y = ITR.ClampToDisplay(x, y, C.WIN_W, C.WIN_H);
    if (x ~= w:GetLeft() or y ~= w:GetTop()) then w:SetPosition(x, y); end
end

function C.OnVisibleChanged()
    local st, w = ITR.craft, ITR.craftWin;
    if (st == nil or st.unloaded) then return; end
    local visible = w:IsVisible();
    if (not visible) then C.CloseMenu(); end
    -- HUD toggle and unload never store "hidden" (like SyncWinVisible)
    if (not st.applying and st.data.visible ~= visible) then
        st.data.visible = visible;
        C.Save();
    end
    if (visible) then
        C.Place();
        C.Refresh(true);
    end
end

function C.SetStatus(text)
    local st = ITR.craft;
    if (st == nil) then return; end
    st.status = text;
    if (ITR.cw ~= nil) then ITR.cw.status:SetText(text or ""); end
end

------------------------------------------------------------------------
-- PAINT
------------------------------------------------------------------------

-- Sets the rows of a ListBox: rebuilt when the count changes, else the
-- rows are updated in place. Returns the rows and whether it rebuilt.
function C.SetRowCount(lb, rows, count, newRow)
    if (#rows == count) then return rows, false; end
    lb:ClearItems();
    rows = { };
    for i = 1, count do
        rows[i] = newRow();
        lb:AddItem(rows[i]);
    end
    return rows, true;
end

function C.SetText(label, text)
    if (label:GetText() ~= text) then label:SetText(text); end
end

function C.PaintRecipes(v)
    local cw = ITR.cw;
    local list = v.list;
    local maxBytes = math.floor(C.LIST_W / ITR.NAME_CHAR_W);
    local rebuilt;
    cw.recipeRows, rebuilt = C.SetRowCount(cw.recipes, cw.recipeRows, #list, C.NewRecipeRow);
    local sameOrder = (not rebuilt and cw.shownList ~= nil and #cw.shownList == #list);
    local selIndex;
    for i, e in ipairs(list) do
        local row = cw.recipeRows[i];
        if (sameOrder and cw.shownList[i] ~= e) then sameOrder = false; end
        row.entry = e;
        C.SetText(row, C.RecipeText(e, D.CraftsNeeded(v.need, e.xp), maxBytes));
        C.PaintRow(row);
        if (e == v.selected) then selIndex = i; end
    end
    cw.shownList = list;
    if (not sameOrder and selIndex ~= nil) then ITR.Call(cw.recipes, "EnsureVisible", selIndex); end
    C.SetText(cw.recipesEmpty, (#list == 0) and C.EmptyText(v) or "");
    cw.recipesEmpty:SetVisible(#list == 0);
end

function C.PaintIngredients(v)
    local cw = ITR.cw;
    local lines = C.PreviewLines(v);
    cw.ingrRows = C.SetRowCount(cw.ingr, cw.ingrRows, #lines, function() return C.NewRow(false, "ingr"); end);
    for i, line in ipairs(lines) do
        local row = cw.ingrRows[i];
        C.SetText(row, line.text);
        row:SetForeColor(line.colour);
    end
    local header = "Ingredients";
    if (v.selected ~= nil and v.crafts > 0) then header = header .. " - " .. C.Plural(v.crafts, "craft"); end
    C.SetText(cw.ingrHeader, header);
end

function C.PaintButtons()
    local st, cw = ITR.craft, ITR.cw;
    -- during the pick mode the two buttons ARE the pick controls
    local pick = ITR.Tracker.PickInfo();
    if (pick ~= nil) then
        C.SetText(cw.applyBtn, "Done: " .. pick.assigned .. " of " .. pick.total);
        cw.applyBtn:SetEnabled(true);   -- confirm (a partial one) or stop
        C.SetText(cw.clearBtn, "Stop picking");
        cw.clearBtn:SetEnabled(true);
    else
        C.SetText(cw.applyBtn, "Apply to tracker");
        cw.applyBtn:SetEnabled(C.CanApply());
        C.SetText(cw.clearBtn, "Clear auto targets");
        cw.clearBtn:SetEnabled(ITR.Tracker.HasAutoTargets());
    end
    st.buttonsDirty = false;
end

-- Recomputes and repaints everything ("full": the professions are
-- listed again and re-hooked - on show and when the menu opens).
function C.Refresh(full)
    local st, cw = ITR.craft, ITR.cw;
    if (st == nil or cw == nil or st.unloaded) then return; end
    st.viewDirty = false;
    if (full or st.profs == nil) then C.ReloadProfessions(); end
    local v = C.ComputeView();
    local d = st.data;

    local profText = "(not available)";
    if (st.profs ~= nil and #st.profs == 0) then profText = "(none)"; end
    if (st.profs ~= nil) then
        for _, p in ipairs(st.profs) do
            if (p.value == d.prof) then profText = C.ProfText(p); end
        end
    end
    C.SetText(cw.profBtn, ITR.Shorten(profText, 34));
    cw.profBtn:SetEnabled(st.profs ~= nil and #st.profs > 0);
    C.SetText(cw.modeBtn, C.MODE_TEXT[d.mode]);
    cw.modeBtn:SetEnabled(st.profs ~= nil and #st.profs > 0);
    C.SetText(cw.sortBtn, (d.sort == "name") and "By name" or "By XP");

    local info, info2 = C.InfoTexts(v, d.mode);
    C.SetText(cw.info, info);
    C.SetText(cw.info2, info2);
    C.SetText(cw.recipesHeader, (v.ok and v.tier ~= nil) and ("Recipes - tier " .. v.tier) or "Recipes");

    C.PaintRecipes(v);
    C.PaintIngredients(v);
    C.PaintButtons();
    C.SetText(cw.status, st.status or "");
end

------------------------------------------------------------------------
-- MENUS AND ACTIONS
------------------------------------------------------------------------

function C.CloseMenu()
    if (ITR.craftMenu ~= nil) then ITR.Call(ITR.craftMenu, "Close"); end
end

-- A new ContextMenu (kept in ITR.craftMenu) with { text, checked,
-- enabled, onClick } items, shown at the mouse.
function C.ShowMenu(entries)
    C.CloseMenu();
    local menu = Turbine.UI.ContextMenu();
    ITR.craftMenu = menu;
    local items = menu:GetItems();
    for _, e in ipairs(entries) do
        local mi = Turbine.UI.MenuItem(e.text);
        if (e.checked) then ITR.Call(mi, "SetChecked", true); end
        if (e.enabled == false) then ITR.Call(mi, "SetEnabled", false); end
        local onClick = e.onClick;
        mi.Click = function()
            if (onClick == nil) then return; end
            local ok, err = pcall(onClick);
            if (not ok) then C.SetStatus("Error: " .. tostring(err)); end
        end
        items:Add(mi);
    end
    menu:ShowMenu();
end

function C.ShowProfessionMenu()
    C.Refresh(true);
    local st = ITR.craft;
    local entries = { };
    if (st.profs == nil or #st.profs == 0) then
        table.insert(entries, { text = "No crafting professions", enabled = false });
    else
        for _, p in ipairs(st.profs) do
            local value = p.value;
            table.insert(entries, { text = C.ProfText(p), checked = (value == st.data.prof),
                onClick = function() C.SelectProfession(value); end });
        end
    end
    C.ShowMenu(entries);
end

function C.ShowModeMenu()
    local st = ITR.craft;
    local entries = { };
    for _, m in ipairs(C.MODES) do
        local mode = m;
        table.insert(entries, { text = C.MODE_TEXT[mode], checked = (mode == st.data.mode),
            onClick = function() C.SelectMode(mode); end });
    end
    C.ShowMenu(entries);
end

-- A recipe / profession / mode change while the pick mode is on: the
-- pending ingredients belong to the recipe that started it - stop the
-- picking (nothing is finalized) before switching.
function C.CancelPickIfRecipeChanged()
    if (ITR.Tracker.IsPicking()) then C.CancelPick(); end
end

function C.SelectProfession(value)
    local st = ITR.craft;
    if (value == st.data.prof) then return; end
    C.CancelPickIfRecipeChanged();
    st.data.prof = value;
    C.Save();
    C.RehookProfessions();
    C.Refresh(false);
end

function C.SelectMode(mode)
    local st = ITR.craft;
    if (mode == st.data.mode or C.MODE_TEXT[mode] == nil) then return; end
    C.CancelPickIfRecipeChanged();
    st.data.mode = mode;
    C.Save();
    C.Refresh(false);
end

function C.ToggleSort()
    local d = ITR.craft.data;
    d.sort = (d.sort == "name") and "xp" or "name";
    C.Save();
    C.Refresh(false);
end

function C.SelectRecipe(entry)
    local st = ITR.craft;
    if (st.data.selName == entry.name and st.data.selXp == entry.xp) then return; end
    C.CancelPickIfRecipeChanged();
    st.data.selName, st.data.selXp = entry.name, entry.xp;
    C.Save();
    C.Refresh(false);
end

-- The status line of the running pick mode ("cleared": mention that the
-- old auto targets are gone, right after Apply entered the pick mode;
-- "skipped": the ingredients that became tracked while picking, see
-- PickInfo - the total no longer counts them).
function C.PickStatusText(cleared)
    local pick = ITR.Tracker.PickInfo();
    if (pick == nil) then return nil; end
    local text;
    if (pick.pending == 0) then
        text = "All " .. pick.total .. " assigned - click Done to confirm";
        if (pick.total == 0) then
            text = (pick.skipped > 0 and pick.pending == 0)
                and ("Nothing to assign (" .. pick.skipped .. " tracked already)") or "Nothing to assign";
        end
    else
        text = "Pick slots: " .. pick.pending .. " to assign (" .. pick.assigned
            .. " of " .. pick.total .. ")";
        if (pick.skipped > 0) then text = text .. ", " .. pick.skipped .. " skipped"; end
    end
    if (pick.moreSlots > 0) then
        text = text .. "; " .. pick.moreSlots .. " more empty slot"
            .. ((pick.moreSlots == 1) and "" or "s") .. " needed: the + button adds slots";
    end
    -- the old auto targets only vanish once: reporting it fits while
    -- the line still has room (the status has 3 lines of ~45 chars)
    if (cleared ~= nil and cleared > 0 and string.len(text) + 27 <= 132) then
        text = text .. " - old auto targets cleared";
    end
    return text;
end

-- "Apply to tracker": the first click enters the pick mode (the old auto
-- targets are cleared at once), the next click reads "Done: N of M" and
-- confirms what was picked.
function C.Apply()
    local st = ITR.craft;
    if (ITR.Tracker.IsPicking()) then
        C.ConfirmPick();
        return true;
    end
    if (not C.CanApply()) then
        C.SetStatus("Select a recipe that still gives XP first.");
        return false;
    end
    local v, d = st.view, st.data;
    -- m-check before anything is destroyed: when every ingredient is
    -- tracked by hand (manual / foreign) nothing can be picked, and the
    -- previous auto targets must not be cleared for nothing. The
    -- calculator's own auto targets do not block: BeginPick clears them
    -- first, so the ingredients are pickable again (BeginPick's
    -- "tracked already" filter then only sees what the clearing missed).
    local targets = D.BuildTargets(v.ingr.list, v.crafts);
    local eligible = 0;
    if (type(targets) == "table") then
        for _, e in ipairs(targets) do
            local state = "manual";
            if (type(e) == "table" and type(e.name) == "string") then
                state = ITR.Tracker.GetNameState(e.name);
            end
            if (state == nil or state == "auto") then eligible = eligible + 1; end
        end
    end
    if (eligible == 0) then
        C.SetStatus("All ingredients are tracked already - nothing to assign.");
        return false;
    end
    -- the recipe the pick belongs to, captured NOW (m-check at confirm):
    -- a profession/selection reload while picking must not make the
    -- confirm record the wrong recipe
    local snap = { prof = d.prof, mode = d.mode, tier = v.tier, name = v.selected.name,
        xp = v.selected.xp, crafts = v.crafts };
    local cleared = ITR.Tracker.BeginPick(targets);
    if (not ITR.Tracker.IsPicking()) then return false; end   -- refused (picking already on)
    st.pickRecipe = snap;
    -- the old auto targets are gone: the applied session is over
    d.applied = nil;
    st.liveDirty = false;
    C.Save();
    C.RehookProfessions();
    ITR.ShowMainWindow(true);   -- the slots are picked there
    local text = C.PickStatusText(cleared);
    if (text ~= nil) then st.status = text; end
    if (C.IsShown()) then C.Refresh(false); end
    return true;
end

-- The pick mode's "Done: N of M": only the assigned slots are finalized
-- (they become normal auto targets); stopping finalizes nothing. The
-- applied session is built from the recipe snapshot taken at Apply time,
-- not from what is selected now.
function C.ConfirmPick()
    local st = ITR.craft;
    local v, d = st.view, st.data;
    local snap = st.pickRecipe;
    if (snap ~= nil and (v == nil or v.ok ~= true or v.selected == nil
        or d.prof ~= snap.prof or d.mode ~= snap.mode or v.tier ~= snap.tier
        or v.selected.name ~= snap.name or v.selected.xp ~= snap.xp)) then
        -- the recipe the pick started with is not selected any more
        -- (a silent profession / recipe reload): finalize nothing
        return C.CancelPick();
    end
    local report = ITR.Tracker.FinishPick();
    if (report.assigned == 0) then
        st.status = "Nothing assigned - no targets set.";
    else
        if (snap ~= nil) then
            d.applied = { prof = snap.prof, mode = snap.mode, tier = snap.tier, name = snap.name,
                xp = snap.xp, crafts = snap.crafts, done = false };
        elseif (v ~= nil and v.ok and v.crafts > 0 and v.selected ~= nil) then
            -- a pick started without the calculator (the raw API): the
            -- current selection is all we know
            d.applied = { prof = d.prof, mode = d.mode, tier = v.tier, name = v.selected.name,
                xp = v.selected.xp, crafts = v.crafts, done = false };
        end
        st.liveDirty = false;
        st.status = C.ReportText(report);
    end
    st.pickRecipe = nil;
    C.Save();
    C.RehookProfessions();
    if (C.IsShown()) then C.Refresh(false); end
    return report;
end

-- "Stop picking" (or Escape in the main window): the picked slots are
-- emptied again, and the auto targets cleared at the start stay cleared.
function C.CancelPick()
    local st = ITR.craft;
    ITR.Tracker.CancelPick();
    st.data.applied = nil;
    st.pickRecipe = nil;
    st.liveDirty = false;
    C.Save();
    C.RehookProfessions();
    st.status = "Picking stopped - nothing assigned.";
    if (C.IsShown()) then C.Refresh(false); end
    return true;
end

function C.ClearAuto()
    local st = ITR.craft;
    ITR.Tracker.ClearAutoTargets();
    st.data.applied = nil;
    st.pickRecipe = nil;
    st.liveDirty = false;
    C.Save();
    C.RehookProfessions();
    st.status = "Auto targets cleared";
    if (C.IsShown()) then C.Refresh(false); end
    return true;
end

------------------------------------------------------------------------
-- LIVE AUTO TARGETS
------------------------------------------------------------------------

-- The applied session is over (tier done, recipe or profession gone):
-- the targets are kept until the user clears them.
function C.FinishApplied(reason)
    local st = ITR.craft;
    local a = st.data.applied;
    a.done = true;
    local what = reason or ("tier " .. a.tier .. " " .. C.MODE_DONE[a.mode] .. " done");
    ITR.Hint(what .. " - craft targets kept. Pick the next recipe or clear them.");
    st.status = string.upper(string.sub(what, 1, 1)) .. string.sub(what, 2) .. " - targets kept. Pick the next recipe or clear them.";
    C.Save();
    C.RehookProfessions();
    st.viewDirty = true;
end

function C.LiveCheck()
    local st = ITR.craft;
    local a = st.data.applied;
    if (a == nil) then return; end
    if (not ITR.Tracker.HasAutoTargets()) then
        -- cleared or re-targeted by hand in the main window
        st.data.applied = nil;
        st.liveDirty = false;
        C.Save();
        C.RehookProfessions();
        st.viewDirty = true;
        return;
    end
    if (a.done or not st.liveDirty) then return; end
    st.liveDirty = false;
    local attrs = D.GetAttributes();
    if (attrs == nil) then return; end
    local info = st.infos[a.prof] or D.GetProfessionInfo(a.prof, attrs);
    if (info == nil) then C.FinishApplied("the profession is not learned any more"); return; end
    local tier, need, _, ok = D.ComputeTarget(D.ReadProgress(info), a.mode);
    if (not ok) then return; end
    if (tier ~= a.tier or need <= 0) then C.FinishApplied(nil); return; end
    local cache = C.Recipes(a.prof);
    local entry = C.FindEntry(cache and cache.list, a.tier, a.name, a.xp);
    if (entry == nil) then C.FinishApplied("the applied recipe is not available any more"); return; end
    local crafts = D.CraftsNeeded(need, entry.xp);
    if (crafts ~= a.crafts) then
        ITR.Tracker.UpdateAutoTargets(D.BuildTargets(C.Ingredients(entry).list, crafts));
        a.crafts = crafts;
        C.Save();
        st.viewDirty = true;
    end
end

-- ITR.craftTicker: every CHECK_INTERVAL seconds - poll, live targets,
-- window refresh while shown, delayed position save.
function C.Tick()
    local st = ITR.craft;
    if (st == nil or st.unloaded or not C.ready) then return; end
    local now = Turbine.Engine.GetGameTime();
    if (now < st.nextCheck) then return; end
    st.nextCheck = now + C.CHECK_INTERVAL;

    local shown = C.IsShown();
    local a = st.data.applied;
    local active = (a ~= nil and not a.done);
    if ((shown or active) and now >= st.nextPoll) then
        st.nextPoll = now + C.POLL_INTERVAL;
        local recipes = (now >= st.nextRecipePoll);
        if (recipes) then st.nextRecipePoll = now + C.RECIPE_POLL_INTERVAL; end
        C.Poll(recipes);
        -- buttons follow the tracker at the poll at the latest (clearBtn
        -- after a manual clear), no per-tick sync while nothing happened
        st.buttonsDirty = true;
        if (shown) then st.viewDirty = true; end   -- preview states follow the tracker
    end
    if (a ~= nil) then C.LiveCheck(); end
    if (shown) then
        if (st.viewDirty) then C.Refresh(false); elseif (st.buttonsDirty) then C.PaintButtons(); end
    end
    if (st.saveAt ~= nil and now >= st.saveAt) then
        st.saveAt = nil;
        C.Save();
    end
end

------------------------------------------------------------------------
-- PUBLIC (called by Main.lua, always in pcall)
------------------------------------------------------------------------

function C.IsShown()
    return (ITR.craftWin ~= nil and ITR.craftWin:IsVisible());
end

-- Explicit show / hide (menu, command, options): stored, also while the
-- HUD is hidden.
function C.Show(show)
    local st, w = ITR.craft, ITR.craftWin;
    st.data.visible = (show == true);
    C.Save();
    if (show) then
        if (w:IsVisible()) then C.Refresh(true); else w:SetVisible(true); end
        ITR.Call(w, "Activate");
    else
        w:SetVisible(false);
    end
end

function C.Toggle()
    C.Show(not C.IsShown());
end

function C.OnHud(hidden)
    local st, w = ITR.craft, ITR.craftWin;
    if (st == nil or st.unloaded or w == nil) then return; end
    st.applying = true;
    pcall(function()
        if (hidden) then
            C.CloseMenu();
            w:SetVisible(false);
        else
            w:SetVisible(st.data.visible == true);
        end
    end);
    st.applying = false;
end

function C.Debug()
    local function P(text) Turbine.Shell.WriteLine(ITR.PLUGIN_NAME .. " craft: " .. ITR.ChatSafe(text)); end
    local function n(x) return (x ~= nil) and tostring(x) or "?"; end
    local attrs, reason = D.GetAttributes();
    if (attrs == nil) then
        local why = { noplayer = "no player", noattrs = "attributes not available",
            monster = "monster play (no professions)" };
        P("attributes: " .. (why[reason] or tostring(reason)));
        return;
    end
    P("attributes: free people");
    local profs = D.ListProfessions() or { };
    if (#profs == 0) then P("no crafting profession"); return; end
    for _, p in ipairs(profs) do
        local q = D.ReadProgress(p.info);
        P(p.name .. ": P " .. n(q.pl) .. " (" .. n(q.px) .. "/" .. n(q.pt) .. ") M " .. n(q.ml)
            .. " (" .. n(q.mx) .. "/" .. n(q.mt) .. ")");
    end
    local st = ITR.craft;
    local value = st.data.prof;
    local info = (value ~= nil) and D.GetProfessionInfo(value, attrs) or nil;
    if (info == nil) then P("no profession selected"); return; end
    local list, diag = D.ReadRecipes(info);
    st.cache[value] = { list = list, diag = diag };
    local name = "?";
    for _, p in ipairs(profs) do if (p.value == value) then name = p.name; end end
    P(name .. ": " .. diag.count .. " recipes, index base " .. diag.base .. ", " .. diag.nilCount .. " nil, "
        .. diag.unnamed .. " unnamed");
    local tiers = { };
    for tier in pairs(diag.tiers) do table.insert(tiers, tier); end
    table.sort(tiers);
    local parts = { };
    for _, tier in ipairs(tiers) do table.insert(parts, tier .. ":" .. diag.tiers[tier]); end
    P("tiers with XP: " .. ((#parts > 0) and table.concat(parts, " ") or "none"));
    local progress = D.ReadProgress(info);
    for _, mode in ipairs(C.MODES) do
        local tier, need, _, ok = D.ComputeTarget(progress, mode);
        if (ok) then P(C.MODE_TEXT[mode] .. ": tier " .. tier .. ", " .. need .. " XP left");
        else P(C.MODE_TEXT[mode] .. ": progress not available"); end
    end
    st.viewDirty = true;
end

function C.Command(rest)
    local word = string.match(rest or "", "^%s*(%S*)") or "";
    if (word == "" or word == "toggle") then
        C.Toggle();
    elseif (word == "show") then
        C.Show(true);
    elseif (word == "hide") then
        C.Show(false);
    elseif (word == "clear") then
        -- a running pick mode stops first (its assignments are undone),
        -- then everything the calculator had set is cleared
        C.CancelPickIfRecipeChanged();
        C.ClearAuto();
        Turbine.Shell.WriteLine(ITR.PLUGIN_NAME .. ": auto targets cleared.");
    elseif (word == "debug") then
        C.Debug();
    else
        Turbine.Shell.WriteLine("Usage: /itr craft [show|hide|toggle|clear|debug]");
    end
end

-- Plugin unload: saves, unhooks, stops the ticker, hides the window; the
-- targets are left alone. Idempotent.
function C.Unload()
    local st = ITR.craft;
    C.ready = false;
    if (st == nil or st.unloaded) then return; end
    st.applying = true;
    C.Save();
    st.unloaded = true;
    ITR.Tracker.OnPickChange = nil;   -- no calculator left to tell
    D.UnhookAll();
    if (ITR.craftTicker ~= nil) then pcall(ITR.craftTicker.SetWantsUpdates, ITR.craftTicker, false); end
    C.CloseMenu();
    if (ITR.craftWin ~= nil) then pcall(ITR.craftWin.SetVisible, ITR.craftWin, false); end
end

function C.Setup()
    local st = { infos = { }, cache = { }, snap = { }, nextCheck = 0, nextPoll = 0, nextRecipePoll = 0,
        viewDirty = true, liveDirty = false, buttonsDirty = false, applying = true };
    ITR.craft = st;
    st.data = C.LoadData();
    -- a saved session without auto targets left (slots cleared) is over
    if (st.data.applied ~= nil and not ITR.Tracker.HasAutoTargets()) then st.data.applied = nil; end
    if (st.data.applied ~= nil) then st.liveDirty = true; end   -- resume the live updates
    C.BuildWindow();
    -- the pick mode runs in the main window (Main.lua AUTO TARGETS):
    -- every assignment / take-back / stop tells the calculator, which
    -- refreshes its status and buttons
    ITR.Tracker.OnPickChange = function()
        if (st == nil or st.unloaded) then return; end
        if (ITR.Tracker.IsPicking()) then
            local text = C.PickStatusText();
            if (text ~= nil) then st.status = text; end
        else
            -- the pick just ended (Escape / Stop picking): nothing was
            -- finalized unless a Done followed right after this
            st.status = "Picking stopped - nothing assigned.";
            st.pickRecipe = nil;
        end
        st.viewDirty = true;
        st.buttonsDirty = true;
    end
    ITR.craftTicker = Turbine.UI.Control();
    ITR.craftTicker.Update = function()
        local ok, err = pcall(C.Tick);
        if (not ok and not st.tickError) then
            st.tickError = true;   -- reported once
            ITR.Hint("craft calculator error: " .. tostring(err));
        end
    end
    C.RehookProfessions();
    st.applying = false;
    C.ready = true;
    ITR.craftTicker:SetWantsUpdates(true);
    if (st.data.visible) then
        st.applying = true;
        ITR.craftWin:SetVisible(true);
        st.applying = false;
    end
end

-- Main.lua calls this once (in pcall) after its BOOT. On an error the
-- partial setup is undone and the error goes to Main.lua.
function C.Init()
    local ok, err = pcall(C.Setup);
    if (not ok) then
        pcall(C.Unload);
        C.ready = false;
        error(err, 0);
    end
end
