--[[=========================================================================

    CharacterStats -- EventHub.lua
    Chained subscription to events of SHARED game objects (LocalPlayer,
    Equipment, EffectList are singletons used by every plugin): the
    previous handler keeps being called, and everything is unhooked on
    unload. Our own UI controls use plain assignment instead.

=========================================================================]]

CS.EventHub = { entries = { } };

function CS.EventHub.Add(object, eventName, fn)
    if (object == nil) then return; end
    local entry = { object = object, name = eventName, active = true };
    local okPrev, prev = pcall(function() return object[eventName]; end);
    entry.prev = okPrev and prev or nil;
    entry.wrapper = function(sender, args)
        if (type(entry.prev) == "function") then pcall(entry.prev, sender, args); end
        if (entry.active) then pcall(fn, sender, args); end
    end;
    pcall(function() object[eventName] = entry.wrapper; end);
    table.insert(CS.EventHub.entries, entry);
end

function CS.EventHub.RemoveAll()
    for i = #CS.EventHub.entries, 1, -1 do
        local e = CS.EventHub.entries[i];
        -- if another plugin chained on top of us, our wrapper stays in its
        -- chain but becomes a pass-through
        e.active = false;
        pcall(function()
            if (e.object[e.name] == e.wrapper) then e.object[e.name] = e.prev; end
        end);
    end
    CS.EventHub.entries = { };
end
