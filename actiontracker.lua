require('common');

local bit = bit or require('bit');

local actionTracker = T{
    actions = T{},
    textures = T{}  -- Cache for loaded textures
};

-- Duration (seconds) of special abilities for target name swapping.
local specialAbilityDurations = {
	['Mighty Strikes'] = 45, ['Brazen Rush'] = 30,
	['Hundred Fists'] = 45, ['Inner Strength'] = 30,
	['Manafont'] = 60, ['Subtle Sorcery'] = 60,
	['Chainspell'] = 60,
	['Perfect Dodge'] = 30,
	['Invincible'] = 30,
	['Blood Weapon'] = 30, ['Soul Enslavement'] = 30,
	['Unleash'] = 60,
	['Soul Voice'] = 180, ['Clarion Call'] = 180,
	['Overkill'] = 60,
	['Meikyo Shisui'] = 30, ['Yaegasumi'] = 45,
	['Mikage'] = 45,
	['Spirit Surge'] = 60, ['Fly High'] = 30,
	['Astral Flow'] = 180, ['Astral Conduit'] = 30,
	['Azure Lore'] = 30, ['Unbridled Wisdom'] = 60,
	['Overdrive'] = 60,
	['Trance'] = 60, ['Grand Pas'] = 30,
	['Tabula Rasa'] = 180,
	['Bolster'] = 180, ['Widened Compass'] = 60,
	['Elemental Sforzo'] = 30,
	['Ignis'] = 30,
};

-- Active SPs keyed by actorId / serverId (same ID Bars uses).
actionTracker.specials = T{};


-- Icon texture filenames (will be loaded like the arrow texture)
local STATUS_ICON = {
    casting     = 'casting',
    completed   = 'completed',
    interrupted = 'interrupted',
};

local MAX_CAST_DURATION = 20.0; -- safety cap so we don't get stuck forever

-- Local cached ability tables (mirrors SimpleLog's PopulateSkills layout).
local weaponSkills      = nil;  -- indexed by weaponskill index (1..255)
local jobAbilities      = nil;  -- indexed by job-ability index
local monsterAbilities  = nil;  -- indexed by monster TP / ability id (0x101+)

-- Precomputed escape chars for stripping FFXI color codes.
local ESC_1 = string.char(0x1E);
local ESC_2 = string.char(0x1F);

local function ensure_ability_tables()
    if (weaponSkills ~= nil and jobAbilities ~= nil and monsterAbilities ~= nil) then
        return;
    end

    weaponSkills     = {};
    jobAbilities     = {};
    monsterAbilities = {};

    local resMgr = AshitaCore and AshitaCore:GetResourceManager() or nil;
    if (resMgr == nil) then
        return;
    end

    -- OPTIMIZED: Weapon skills (1 to 0x200 = 512 max)
    local index = 1;
    for i = 1, 0x200 do
        local abil = resMgr:GetAbilityById(i);
        if (abil ~= nil) then
            weaponSkills[index] = abil;
            index = index + 1;
        end
    end

    -- OPTIMIZED: Job abilities (0x201 to 0x600 = 1024 range)
    index = 1;
    for i = 0x201, 0x600 do
        local abil = resMgr:GetAbilityById(i);
        if (abil ~= nil) then
            jobAbilities[index] = abil;
            index = index + 1;
        end
    end

    -- OPTIMIZED: Monster abilities (limited range)
    local monIndex = 0x101;
    for i = 1, 1000 do  -- Reduced from 4116 to reasonable estimate
        local en = resMgr:GetString('monsters.abilities', i, 2);
        if (en == nil or en == '') then
            break;  -- Stop at first empty entry
        end
        local jp = resMgr:GetString('monsters.abilities', i, 1);
        monsterAbilities[monIndex] = {
            Name = {
                [1] = en;
                [2] = jp;
            }
        };
        monIndex = monIndex + 1;
    end
end

actionTracker.PreloadAbilityTables = function()
    ensure_ability_tables();
end
----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function GetIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();

    if (bit.band(id, 0x1000000) ~= 0) then
        local index = bit.band(id, 0xFFF);
        if (index >= 0x900) then
            index = bit.band(index, 0xFF);
        end
        if (index < 0x900) then
            return index;
        end
    else
        for i = 0, 0x8FF do
            if (entMgr:GetServerId(i) == id) then
                return i;
            end
        end
    end
    return nil;
end

local function GetNameFromId(serverId)
    if (serverId == nil or serverId == 0) then
        return nil;
    end

    local index = GetIndexFromId(serverId);
    if (index == nil) then
        return nil;
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    local name   = entMgr:GetName(index);
    if (name ~= nil and name ~= '') then
        return name;
    end

    return nil;
end

-- Find an entity serverId by its display name.
local function FindServerIdByName(targetName)
    if (targetName == nil or targetName == '') then
        return nil, nil;
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    if (entMgr == nil) then
        return nil, nil;
    end

    for i = 0, 0x8FF do
        local name = entMgr:GetName(i);
        if (name ~= nil and name == targetName) then
            return entMgr:GetServerId(i), entMgr:GetRenderFlags0(i);
        end
    end

    return nil, nil;
end

-- Load a texture (similar to how targetbar loads the arrow)
local function LoadStatusTexture(textureName)
    if (actionTracker.textures[textureName] ~= nil) then
        return actionTracker.textures[textureName];
    end

    -- Assuming LoadTexture is a global function like in targetbar.lua
    local texture = LoadTexture(textureName);
    if (texture ~= nil) then
        actionTracker.textures[textureName] = texture;
    end
    return texture;
end

-- Returns icon texture and action name separately
local function build_left_parts(entry)
    if (entry == nil) then
        return nil, nil;
    end

    local iconName = STATUS_ICON[entry.status] or nil;
    local iconTexture = nil;
    
    if (iconName ~= nil) then
        iconTexture = LoadStatusTexture(iconName);
    end

    local name = entry.actionName;

    return iconTexture, name;
end

----------------------------------------------------------------------
-- Lifecycle helpers
----------------------------------------------------------------------

local function mark_casting(actorId, actionName, targetName)
    actionTracker.actions[actorId] = {
        status     = 'casting',
        startedAt  = os.clock(),
        expiresAt  = nil,
        actionName = actionName,          -- can be nil
        targetName = targetName,          -- can be nil
        abilityId  = nil,
        resultText = nil,                 -- NEW: for displaying damage/healing
        resultColor = nil,                -- NEW: 'damage', 'heal', or 'status'
    };
end

local function mark_completed(actorId)
    local entry = actionTracker.actions[actorId];
    if (entry ~= nil) then
        entry.status    = 'completed';
        entry.startedAt = nil;
        entry.expiresAt = os.clock() + 3.0;
    end
end

local function mark_interrupted(actorId)
    local entry = actionTracker.actions[actorId];
    if (entry ~= nil) then
        entry.status    = 'interrupted';
        entry.startedAt = nil;
        entry.expiresAt = os.clock() + 3.0;
        entry.resultText = nil; -- Clear result on interrupt
    end
end

----------------------------------------------------------------------
-- Result parsing helpers (NEW)
----------------------------------------------------------------------

-- Add commas to numbers
local function addCommas(number)
    if number == nil then return '' end
    local formatted = tostring(number)
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- Parse action results and generate result text
local function parseActionResult(actionPacket)
    if actionPacket == nil or actionPacket.Targets == nil or #actionPacket.Targets == 0 then
        return nil, nil
    end

    local targets = actionPacket.Targets
    local targetCount = #targets
    local mainTarget = targets[1]
    local mainAction = mainTarget.Actions[1]
    
    if mainAction == nil then
        return nil, nil
    end

    local msg = mainAction.Message or 0
    local param = mainAction.Param or 0
    local amount = addCommas(param)
    
    -- Damage messages
    local damageMessages = {
        [1] = true, [2] = true, [110] = true, [185] = true, [264] = true, 
        [265] = true, [274] = true, [352] = true, [353] = true, [354] = true
    }
    
    -- Healing/cure messages
    local healMessages = {
        [7] = true, [24] = true, [102] = true, [103] = true, [238] = true, 
        [263] = true, [306] = true, [318] = true
    }
    
    -- Miss/evade/resist messages
    local missMessages = {
        [15] = true, [63] = true, [85] = true, [158] = true, [188] = true, 
        [282] = true, [284] = true, [323] = true, [324] = true
    }
    
    -- No effect messages
    local noEffectMessages = {
        [75] = true, [156] = true, [189] = true, [248] = true, [283] = true, 
        [355] = true, [423] = true
    }

    local resultText = nil
    local resultColor = nil
    
    -- Calculate totals if multiple targets
    if targetCount > 1 then
        local totalDamage = 0
        local totalHeal = 0
        local landed = 0
        
        for i = 1, targetCount do
            local target = targets[i]
            if target and target.Actions and target.Actions[1] then
                local action = target.Actions[1]
                local actionMsg = action.Message or 0
                local actionParam = action.Param or 0
                
                if damageMessages[actionMsg] then
                    totalDamage = totalDamage + actionParam
                    landed = landed + 1
                elseif healMessages[actionMsg] then
                    totalHeal = totalHeal + actionParam
                    landed = landed + 1
                elseif not missMessages[actionMsg] and not noEffectMessages[actionMsg] then
                    landed = landed + 1
                end
            end
        end
        
        if totalDamage > 0 or (landed > 0 and totalHeal == 0) then
            resultText = string.format(' %s x%d', addCommas(totalDamage), landed)
            resultColor = 'damage'
        elseif totalHeal > 0 then
            resultText = string.format(' %s x%d', addCommas(totalHeal), landed)
            resultColor = 'heal'
        elseif landed > 0 and landed < targetCount then
            resultText = string.format(' %d/%d', landed, targetCount)
            resultColor = 'status'
        end
    else
        -- Single target
        if damageMessages[msg] then
            resultText = string.format(' %s', amount)
            resultColor = 'damage'
        elseif healMessages[msg] then
            resultText = string.format(' %s', amount)
            resultColor = 'heal'
        elseif missMessages[msg] then
            resultText = ' Miss'
            resultColor = 'status'
        elseif noEffectMessages[msg] then
            resultText = ' No Effect'
            resultColor = 'status'
        elseif msg == 78 then
            resultText = ' Too Far'
            resultColor = 'status'
        elseif param == 28787 then
            resultText = ' Interrupted'
            resultColor = 'status'
        end
    end
    
    return resultText, resultColor
end

----------------------------------------------------------------------
-- Zone packet handler
----------------------------------------------------------------------

function actionTracker.HandleZonePacket(e)
    actionTracker.actions  = T{};
    actionTracker.specials = T{};
end

----------------------------------------------------------------------
-- 0x28: handle action packet (HXUI already calls this)
----------------------------------------------------------------------

-- Helper to store SPs keyed by serverId (same key that GetSpecialForTargetIndex uses)
local function set_special_for_actor(actorId, abilityName)
    if (actorId == nil or actorId == 0) then
        return;
    end
    if (abilityName == nil or abilityName == '') then
        return;
    end

    -- CRITICAL FIX: Strip NULL bytes and control characters from ability name
    -- The game sends ability names with NULL terminators (0x00) which breaks Lua string comparison
    abilityName = abilityName:gsub('%z', '');  -- Remove NULL bytes (0x00)
    abilityName = abilityName:gsub('[\1-\31]', '');  -- Remove other control characters

    local spDuration = specialAbilityDurations[abilityName];
    if (spDuration == nil or spDuration <= 0) then
        return;
    end

    -- Simply use the actorId directly as the key.
    -- Don't do any conversion - just trust what we're given.
    local serverId = actorId;

    actionTracker.specials[serverId] = {
        name      = abilityName,
        expiresAt = os.clock() + spDuration,
    };
end


function actionTracker.HandleActionPacket(actionPacket)
    if (actionPacket == nil) then
        return;
    end

    local actorId = actionPacket.UserId;
    if (actorId == nil or actorId == 0) then
        return;
    end

    --  3 = weaponskill result
    --  4 = spell result
    --  5 = item result
    --  6 = job ability result
    --  7 = monster WS / TP move (readies, etc.)
    --  8 = begin spell cast
    --  9 = begin item use
    -- 11 = monster TP move / monster ability result
    local actionType = actionPacket.Type;
    if (actionType == nil) then
        return;
    end

    local targets = actionPacket.Targets;
    if (targets == nil or #targets == 0) then
        return;
    end

    local mainTarget = targets[1];
    if (mainTarget == nil or mainTarget.Actions == nil or #mainTarget.Actions == 0) then
        return;
    end

    local mainAction = mainTarget.Actions[1];
    local resMgr     = AshitaCore:GetResourceManager();

    ------------------------------------------------------------------
    -- Begin spell cast / begin item use (Types 8 and 9) -> [C]
    ------------------------------------------------------------------
    if (actionType == 8 or actionType == 9) then
        if (actionPacket.Param ~= 0x6163) then
            return;
        end

        local actionName = nil;

        if (actionType == 8 and resMgr ~= nil and resMgr.GetSpellById ~= nil) then
            local spellId = mainAction.Param or 0;
            if (spellId > 0) then
                local spell = resMgr:GetSpellById(spellId);
                if (spell ~= nil and spell.Name ~= nil and spell.Name[1] ~= nil and spell.Name[1] ~= '') then
                    actionName = spell.Name[1];
                end
            end

        elseif (actionType == 9 and resMgr ~= nil and resMgr.GetItemById ~= nil) then
            local itemId = mainAction.Param or 0;
            if (itemId > 0) then
                local item = resMgr:GetItemById(itemId);
                if (item ~= nil and item.Name ~= nil and item.Name[1] ~= nil and item.Name[1] ~= '') then
                    actionName = item.Name[1];
                end
            end
        end

        local targetName = nil;
        if (mainTarget.Id ~= nil and mainTarget.Id > 0) then
            targetName = GetNameFromId(mainTarget.Id);
        end

        mark_casting(actorId, actionName, targetName);

        local entry = actionTracker.actions[actorId];
        if (entry ~= nil) then
            entry.abilityId = mainAction.Param or 0;
        end

        return;
    end

    ------------------------------------------------------------------
    -- Monster abilities / TP moves "readies" (Type 7) -> [C]
    --
    -- We ALSO resolve the ability name here, using the same tables
    -- SimpleLog uses (weaponSkills / monsterAbilities), so [C] shows
    -- the name even if the text_in hook misses it.
    ------------------------------------------------------------------
    if (actionType == 7) then
        local msg = mainAction.Message or 0;
        local isAbilityReadyMsg = (msg == 43) or (msg == 326) or (msg == 675);
        if (isAbilityReadyMsg) then
            local targetName = nil;
            if (mainTarget.Id ~= nil and mainTarget.Id > 0) then
                targetName = GetNameFromId(mainTarget.Id);
            end

            local entry = actionTracker.actions[actorId];
            if (entry == nil) then
                -- Create a new casting entry; name will be filled via
                -- SimpleLog-style fallback below (and/or text_in handler).
                mark_casting(actorId, nil, targetName);
                entry = actionTracker.actions[actorId];
            else
                -- Keep any existing name (eg. from text_in) and just
                -- update target + status.
                if (targetName ~= nil and targetName ~= '') then
                    entry.targetName = targetName;
                end
                entry.status    = 'casting';
                entry.startedAt = entry.startedAt or os.clock();
                entry.expiresAt = nil;
            end

            -- Set ability id for this readying action if we don't have one yet.
            if (entry ~= nil and (entry.abilityId == nil or entry.abilityId == 0)) then
                -- SimpleLog: for category 7, abil_ID = targets[1].actions[1].param
                local rawId = mainAction.Param or 0;
                if (rawId == 0 and actionPacket.Param ~= nil) then
                    rawId = actionPacket.Param;
                end
                entry.abilityId = rawId or 0;
            end

            -- Try to resolve the name immediately for [C] using the same
            -- tables SimpleLog uses for WS / monster TP.
            if (entry ~= nil and (entry.actionName == nil or entry.actionName == '')) then
                local rawId = entry.abilityId or 0;
                if (rawId ~= 0) then
                    ensure_ability_tables();

                    if (rawId < 256 and weaponSkills ~= nil) then
                        -- Weapon skill
                        local ws = weaponSkills[rawId];
                        if (ws ~= nil and ws.Name ~= nil and ws.Name[1] ~= nil and ws.Name[1] ~= '') then
                            entry.actionName = ws.Name[1];
                        end
                    else
                        -- Monster TP / ability
                        if (monsterAbilities ~= nil) then
                            local mon = monsterAbilities[rawId];
                            if (mon ~= nil) then
                                local name = (mon.Name and mon.Name[1]) or nil;
                                if (name ~= nil and name ~= '') then
                                    entry.actionName = name;
                                end
                            end
                        end
                    end
                end
            end
------------------------------------------------------------------
-- Bars-style tracking of long-duration special abilities (SPs)
------------------------------------------------------------------
local entry = actionTracker.actions[actorId];
if (entry ~= nil and entry.actionName ~= nil and entry.actionName ~= '') then
    set_special_for_actor(actorId, entry.actionName);
end


            return;
        end
    end

    ------------------------------------------------------------------
    -- Result packets 3 / 4 / 5 / 6 / 11 -> [V] / [X]
    ------------------------------------------------------------------
    if (actionType ~= 3 and actionType ~= 4 and actionType ~= 5
        and actionType ~= 6 and actionType ~= 11) then
        return;
    end

    local entry = actionTracker.actions[actorId];

    -- Always resolve the main target name.
    local targetName = nil;
    if (mainTarget.Id ~= nil and mainTarget.Id > 0) then
        targetName = GetNameFromId(mainTarget.Id);
    end

    -- Instant JAs / WS / monster TP moves that never had a "begin"
    if (entry == nil) then
        mark_casting(actorId, nil, targetName);
        entry = actionTracker.actions[actorId];
        if (entry == nil) then
            return;
        end
    else
        if (targetName ~= nil and targetName ~= '') then
            entry.targetName = targetName;
        end
    end

    ------------------------------------------------------------------
    -- Record raw ability id
    ------------------------------------------------------------------
    if (entry.abilityId == nil or entry.abilityId == 0) then
        local rawId = 0;

        if (actionType == 4 or actionType == 5) then
            rawId = mainAction.Param or 0;
            if (rawId == 0 and actionPacket.Param ~= nil) then
                rawId = actionPacket.Param;
            end
        elseif (actionType == 3 or actionType == 6 or actionType == 11) then
            rawId = actionPacket.Param or 0;
        end

        entry.abilityId = rawId or 0;
    end

    ------------------------------------------------------------------
    -- Resolve ability name (SimpleLog-style fallback)
    ------------------------------------------------------------------
    if (entry.actionName == nil or entry.actionName == '') then
        local actionName = nil;
        local rawId      = entry.abilityId or 0;

        if (rawId ~= 0 and resMgr ~= nil) then
            -- Spells (result)
            if (actionType == 4 and resMgr.GetSpellById ~= nil) then
                local spell = resMgr:GetSpellById(rawId);
                if (spell ~= nil and spell.Name ~= nil and spell.Name[1] ~= nil and spell.Name[1] ~= '') then
                    actionName = spell.Name[1];
                end
            end

            -- Items (result)
            if (actionType == 5 and (actionName == nil or actionName == '')
                and resMgr.GetItemById ~= nil) then
                local item = resMgr:GetItemById(rawId);
                if (item ~= nil and item.Name ~= nil and item.Name[1] ~= nil and item.Name[1] ~= '') then
                    actionName = item.Name[1];
                end
            end

            -- JA / WS / monster TP – mirror SimpleLog's PopulateSkills layout.
            if ((actionType == 3 or actionType == 6 or actionType == 11)
                and (actionName == nil or actionName == '')) then

                ensure_ability_tables();

                -- Weapon skills and monster abilities use the same abil_ID field.
                if (actionType == 3 or actionType == 11) then
                    if (rawId < 256 and weaponSkills ~= nil) then
                        local ws = weaponSkills[rawId];
                        if (ws ~= nil and ws.Name ~= nil and ws.Name[1] ~= nil and ws.Name[1] ~= '') then
                            actionName = ws.Name[1];
                        end
                    else
                        if (monsterAbilities ~= nil) then
                            local mon = monsterAbilities[rawId];
                            if (mon ~= nil) then
                                local name = (mon.Name and mon.Name[1]) or nil;
                                if (name ~= nil and name ~= '') then
                                    actionName = name;
                                end
                            end
                        end
                    end
                end

                -- Job abilities.
                if ((actionName == nil or actionName == '') and actionType == 6 and jobAbilities ~= nil) then
                    local ja = jobAbilities[rawId];
                    if (ja ~= nil and ja.Name ~= nil and ja.Name[1] ~= nil and ja.Name[1] ~= '') then
                        actionName = ja.Name[1];
                    end
                end

                -- Final fallback: raw ability table – if offsets ever change.
                if ((actionName == nil or actionName == '') and resMgr.GetAbilityById ~= nil) then
                    local abil = resMgr:GetAbilityById(rawId);
                    if (abil ~= nil and abil.Name ~= nil and abil.Name[1] ~= nil and abil.Name[1] ~= '') then
                        actionName = abil.Name[1];
                    end
                end
            end
        end

        if (actionName ~= nil and actionName ~= '') then
            entry.actionName = actionName;
        end
    end

    ------------------------------------------------------------------
-- Bars-style tracking of long-duration special abilities (SPs)
-- This now runs for results too (Types 3 / 6 / 11 / etc.),
-- so things like your own Chainspell get tracked.
------------------------------------------------------------------
if (entry ~= nil and entry.actionName ~= nil and entry.actionName ~= '') then
    set_special_for_actor(actorId, entry.actionName);
end


    ------------------------------------------------------------------
    -- Completed vs interrupted
    ------------------------------------------------------------------
    local msg   = mainAction.Message or 0;
    local param = mainAction.Param   or 0;

    local interrupted = (msg == 78) or (param == 28787) or (msg == 16);

    -- NEW: Parse and store result text
    if not interrupted then
        entry.resultText, entry.resultColor = parseActionResult(actionPacket);
    end

    if (interrupted) then
        mark_interrupted(actorId);
    else
        mark_completed(actorId);
    end
end

----------------------------------------------------------------------
-- HXUI wrapper for message packets: we only care about interrupts (16)
----------------------------------------------------------------------

function actionTracker.HandleMessagePacket(messagePacket)
    if (messagePacket == nil) then
        return;
    end

    local msgId   = messagePacket.message or 0;
    local actorId = messagePacket.sender or 0;

    if (msgId == 16 and actorId ~= nil and actorId ~= 0) then
        mark_interrupted(actorId);
    end
end

----------------------------------------------------------------------
-- text_in hook: watch for "X readies Y." lines (monster abilities)
----------------------------------------------------------------------

local function handle_text_in_readies(e)
    if (e == nil or e.message == nil) then
        return;
    end

    local msg = e.message;
    if (msg == '') then
        return;
    end

    -- Strip FFXI color codes (0x1E?? / 0x1F??).
    msg = msg:gsub(ESC_1 .. '.', ''):gsub(ESC_2 .. '.', '');

    ------------------------------------------------------------------
    -- English log templates we care about:
    --   "${actor} readies ${weapon_skill}."
    --   "${actor} readies ${ability}."
    --   "${actor} uses ${weaponskill_or_ability}."
    --   "${actor} starts casting ${spell}."
    --   "${actor} casts ${spell}."
    ------------------------------------------------------------------
    local actorName, abilityName;

    -- 1) "readies" (mob TP / some WS / abilities)
    actorName, abilityName = msg:match('^(.-) readies (.-)%.$');

    -- 2) "uses" (player WS / JA, some mob moves)
    if (actorName == nil or actorName == '' or abilityName == nil or abilityName == '') then
        actorName, abilityName = msg:match('^(.-) uses (.-)%.$');
    end

    -- 3) "starts casting" (spell begin)
    if (actorName == nil or actorName == '' or abilityName == nil or abilityName == '') then
        actorName, abilityName = msg:match('^(.-) starts casting (.-)%.$');
    end

    -- 4) "casts" (spell resolution – useful as a fallback)
    if (actorName == nil or actorName == '' or abilityName == nil or abilityName == '') then
        actorName, abilityName = msg:match('^(.-) casts (.-)%.$');
    end

    if (actorName == nil or actorName == '' or abilityName == nil or abilityName == '') then
        return;
    end

    -- Monsters in the log are often "The <Name>", but the actual entity
    -- name is just "<Name>". Strip the "The " prefix so we can match.
    actorName = actorName:gsub('^The%s+', '');

local actorId, actorType = FindServerIdByName(actorName);

------------------------------------------------------------------
-- If this log line is an SP (e.g. "Perfect Dodge", "Mighty Strikes"),
-- always track it if we found the actor.
------------------------------------------------------------------
if specialAbilityDurations[abilityName] ~= nil and actorId ~= nil and actorId ~= 0 then
    set_special_for_actor(actorId, abilityName);
end

if (actorId == nil or actorId == 0) then
    return;
end

------------------------------------------------------------------
-- If we already have a packet-based entry (from Type 7/8/3/6/11),
-- just update the actionName from text (in case packet had none).
------------------------------------------------------------------
local entry = actionTracker.actions[actorId];
if (entry ~= nil) then
    if (entry.actionName == nil or entry.actionName == '') then
        entry.actionName = abilityName;
    end

    -- Update status if it's a "readies" line (Type 7 scenario).
    if (entry.status ~= 'casting' and msg:match('readies') ~= nil) then
        entry.status    = 'casting';
        entry.startedAt = os.clock();
        entry.expiresAt = nil;
    end
    return;
end


    ------------------------------------------------------------------
    -- Otherwise, if no packet-based entry yet, create one.
    -- This can happen in a few edge cases (or if the action packet
    -- was dropped).
    ------------------------------------------------------------------
if (msg:match('readies') ~= nil or msg:match('starts casting') ~= nil) then
    -- Text-only fallback: name but unknown target until the packet arrives.
    mark_casting(actorId, abilityName, nil);
end


end

----------------------------------------------------------------------
-- Bars-style SP lookup for a given target index
----------------------------------------------------------------------

function actionTracker.GetSpecialForTargetIndex(targetIndex)
    if (targetIndex == nil or targetIndex == 0) then
        return nil, nil;
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    if (entMgr == nil) then
        return nil, nil;
    end

    local serverId = entMgr:GetServerId(targetIndex);
    if (serverId == nil or serverId == 0) then
        return nil, nil;
    end

    local entry = actionTracker.specials[serverId];
    if (entry == nil) then
        return nil, nil;
    end

    local now       = os.clock();
    local remaining = (entry.expiresAt or 0) - now;

    if (remaining <= 0) then
        actionTracker.specials[serverId] = nil;
        return nil, nil;
    end

    return entry.name, remaining;
end

----------------------------------------------------------------------
-- Bars-style SP lookup by serverId (for party members, etc.)
----------------------------------------------------------------------

function actionTracker.GetSpecialForServerId(serverId)
    if (serverId == nil or serverId == 0) then
        return nil, nil;
    end

    local entry = actionTracker.specials[serverId];
    if (entry == nil) then
        return nil, nil;
    end

    local now       = os.clock();
    local remaining = (entry.expiresAt or 0) - now;

    if (remaining <= 0) then
        actionTracker.specials[serverId] = nil;
        return nil, nil;
    end

    return entry.name, remaining;
end

----------------------------------------------------------------------
-- Target bar hook
----------------------------------------------------------------------

function actionTracker.GetActionPartsForTargetIndex(targetIndex)
    if (targetIndex == nil or targetIndex == 0) then
        return nil, nil, nil, nil, nil;
    end

    local entMgr   = AshitaCore:GetMemoryManager():GetEntity();
    local serverId = entMgr:GetServerId(targetIndex);
    if (serverId == nil or serverId == 0) then
        return nil, nil, nil, nil, nil;
    end

    local entry = actionTracker.actions[serverId];
    if (entry == nil) then
        return nil, nil, nil, nil, nil;
    end

    local now = os.clock();

    if (entry.status == 'casting') then
        -- No normal expiresAt for casting: just bail out if something is very wrong.
        local started = entry.startedAt or now;
        if (now - started > MAX_CAST_DURATION) then
            actionTracker.actions[serverId] = nil;
            return nil, nil, nil, nil, nil;
        end
    else
        -- For completed / interrupted we still honor expiresAt.
        if (entry.expiresAt ~= nil and now > entry.expiresAt) then
            actionTracker.actions[serverId] = nil;
            return nil, nil, nil, nil, nil;
        end
    end

    local iconTexture, actionName = build_left_parts(entry);
    local rightText = entry.targetName;
    
    -- Return result text and color separately
    local resultText = entry.resultText;
    local resultColor = entry.resultColor; -- 'damage', 'heal', or 'status'

    return iconTexture, actionName, rightText, resultText, resultColor;
end

----------------------------------------------------------------------
-- Register text_in hook so we see "readies" lines
----------------------------------------------------------------------

if (ashita ~= nil and ashita.events ~= nil) then
    ashita.events.register('text_in', 'hxui_actiontracker_text', function(e)
        handle_text_in_readies(e);
    end);
end

return actionTracker;
