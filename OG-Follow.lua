-- =========================================================
-- OG-Follow (Turtle WoW 1.12)
-- Author: Zanthor
-- Base: FollowMe Enhanced (Lyriane EU-Alleria) / FollowMe (Kingen)
-- =========================================================

---------------------------
-- Constants & State
---------------------------
local MOD_NAME = "OG-Follow"
local FMVer    = "0.1"

-- Runtime state
local OGFEnabled        = false
local ogfFollowTarget   = "Gnuzmas"
local ogfCombat         = false
local following         = nil
local combat            = false
local drinkPause        = 10
local lastCall          = 0
local lastTick          = GetTime()

-- Scrambled Brain cooldown (10m 5s)
local lastScrambledBrain       = 0
local SCRAMBLED_BRAIN_COOLDOWN = 605

-- Saved variables declared in TOC
OGF_Options = OGF_Options or { Version = 1.0 }
OGF_CharOptions = OGF_CharOptions or {
    Target = "Gnuzmas",
    Combat = false,
    SpecSets = {},
}

---------------------------
-- Frame
---------------------------
local OGFFrame = CreateFrame("Frame")

-- XML OnUpdate calls this every frame.
function ogf_onesecondtick()
    local now = GetTime()
    if now - lastTick >= 1 then
        lastTick = now
        OGF_OneSecondTick()
    end
end

-- Called once per second by the wrapper above
function OGF_OneSecondTick()
    OGFollow_Strobe()
end

---------------------------
-- UI Helpers
---------------------------
local function OGF_Print(msg)
    if OGFollow_LocalMsg then
        OGFollow_LocalMsg(msg)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffOGF|r: "..tostring(msg))
    end
end

local function OGF_Trim(s)
    s = tostring(s or "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

function OGFollow_LocalMsg(txt)
    DEFAULT_CHAT_FRAME:AddMessage(txt)
end

-- Split by spaces, 1.12-safe
local function splitBySpace(input)
    local result, pattern, index = {}, "([^%s]+)", 1
    while true do
        local startPos, endPos, word = string.find(input or "", pattern, index)
        if not word then break end
        table.insert(result, word)
        index = endPos + 1
    end
    return result
end

---------------------------
-- Addon Init & Events
---------------------------
function OGFollow_OnLoad()
    local FM_LOAD = MOD_NAME.." ["..FMVer.."] loaded"
    SLASH_OGFOLLOW1 = "/ogf"
    SLASH_OGFOLLOW2 = "/ogfollow"
    SlashCmdList["OGFOLLOW"] = ogFollow_CmdParser

    OGFollow_LocalMsg(FM_LOAD)
    OGFollow_LocalMsg("/ogfollow or /ogf for usage instructions.")
    UIErrorsFrame:AddMessage(FM_LOAD, 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)

    OGFollow_InitOptions()

    -- Turtle-era events (use XML <OnLoad> context where 'this' exists)
    this:RegisterEvent("VARIABLES_LOADED")
    this:RegisterEvent("PLAYER_REGEN_ENABLED")
    this:RegisterEvent("PLAYER_REGEN_DISABLED")
    this:RegisterEvent("AUTOFOLLOW_BEGIN")
    this:RegisterEvent("AUTOFOLLOW_END")
    this:RegisterEvent("SPELLCAST_FAILED")
    this:RegisterEvent("SPELLCAST_STOP")
    this:RegisterEvent("SPELLCAST_INTERRUPTED")
    this:RegisterEvent("SPELLCAST_CHANNEL_STOP")
    this:RegisterEvent("CHAT_MSG_SYSTEM")
    this:RegisterEvent("PLAYER_AURAS_CHANGED")
	this:RegisterEvent("PARTY_INVITE_REQUEST")
end

function OGFollow_OnEvent(event)
    if event == "VARIABLES_LOADED" then
        OGFollow_InitOptions()
        OGF_OnVariablesLoaded_CS() -- ensure CastSequences table exists
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        combat = false
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        combat = true
        return
    end

    if event == "AUTOFOLLOW_BEGIN" then
        following = true
        return
    elseif event == "AUTOFOLLOW_END" then
        following = nil
        return
    end

    -- Spec switch announcements
    if event == "CHAT_MSG_SYSTEM" and (arg1 == "Secondary Specialization Activated." or arg1 == "Primary Specialization Activated.") then
        OGF_Print("Spec change detected. Equipping appropriate ItemRack set...")
        OGFollow_RunSpecEquip()
        return
    end

    -- Scrambled Brain (debuff icon path check)
    if event == "PLAYER_AURAS_CHANGED" then
        local i = 1
        while true do
            local debuff = UnitDebuff("player", i)
            if not debuff then break end
            if debuff == "Interface\\Icons\\Spell_Shadow_MindRot" then
                local now = GetTime()
                if now - lastScrambledBrain >= SCRAMBLED_BRAIN_COOLDOWN then
                    lastScrambledBrain = now
                    OGF_Print("Detected 'Scrambled Brain' — spec change detected.")
                    OGFollow_RunSpecEquip()
                end
                break
            end
            i = i + 1
        end
        return
    end

    -- Any cast ended/failed/chan stop: play cue (optional)
    if event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" or event == "SPELLCAST_CHANNEL_STOP" then
        PlaySoundFile("Interface\\AddOns\\OG-Follow\\knock.mp3")
        return
    end
	
	-- Auto-accept only from follow target; decline others
	if event == "PARTY_INVITE_REQUEST" then
		local inviter = arg1
		local target  = ogfFollowTarget or (OGF_CharOptions and OGF_CharOptions.Target) or ""

		if inviter and target and string.lower(inviter) == string.lower(target) then
			AcceptGroup()
			StaticPopup_Hide("PARTY_INVITE")
			OGF_Print("Auto-accepted party invite from "..inviter..".")
		elseif inviter == "Gnuzherbs" then
			AcceptGroup()
			StaticPopup_Hide("PARTY_INVITE")
			OGF_Print("Auto-accepted party invite from "..inviter..".")
		else
			--DeclineGroup()
			--StaticPopup_Hide("PARTY_INVITE")
			OGF_Print("Declined party invite from "..(inviter or "?").." (not follow target).")
		end
		return
	end
end

---------------------------
-- Options
---------------------------
function OGFollow_InitOptions()
    OGF_CharOptions = OGF_CharOptions or {}
    OGF_CharOptions.Target = OGF_CharOptions.Target or "Gnuzmas"
    OGF_CharOptions.Combat = (OGF_CharOptions.Combat ~= nil) and OGF_CharOptions.Combat or false
    OGF_CharOptions.SpecSets = OGF_CharOptions.SpecSets or {}

    ogfFollowTarget = OGF_CharOptions.Target
    ogfCombat = OGF_CharOptions.Combat
end

---------------------------
-- Follow / Strobe
---------------------------
-- Lua-side fallback: ensure we tick even if XML doesn't wire OnUpdate
if OGFFrame and not OGFFrame.__ogf_onupdate then
    OGFFrame.__ogf_onupdate = true
    OGFFrame:SetScript("OnUpdate", function()
        if type(ogf_onesecondtick) == "function" then
            ogf_onesecondtick()
        end
    end)
end

local function PlayerHasDrink()
    for i = 1, 16 do
        local buff = UnitBuff("player", i)
        if not buff then break end
        local texture = GetPlayerBuffTexture(i-1) -- 0-based for GetPlayerBuff*
        if texture and string.find(texture, "INV_Drink") then
            return true
        end
    end
    return false
end

-- Reinvite state and helpers
ogf_Reinvite = ogf_Reinvite or { active = false }

local function OGF_IsInParty(name)
    if not name or name == "" then return false end
    local want = string.lower(name)
    for i = 1, 4 do
        local n = UnitName("party"..i)
        if n and string.lower(n) == want then return true end
    end
    return false
end

function OGFollow_Strobe()
	if ogf_Reinvite and ogf_Reinvite.active and ogf_Reinvite.name and ogf_Reinvite.name ~= "" then
		-- If they already rejoined, stop
		--OGF_Print(ogf_Reinvite.name.." reinvite check.")
		if OGF_IsInParty(ogf_Reinvite.name) then
			OGF_Print(ogf_Reinvite.name.." rejoined. Stopping reinvites.")
			ogf_Reinvite.active = false
		else
			local now = GetTime()
			-- Give up after timeout window (prevents infinite spam)
			if ogf_Reinvite.timeoutAt and now >= ogf_Reinvite.timeoutAt then
				OGF_Print("Reinvite window expired for "..ogf_Reinvite.name..".")
				ogf_Reinvite.active = false
			-- Time to send (or resend) an invite?
			elseif ogf_Reinvite.nextInvite and now >= ogf_Reinvite.nextInvite then
				if IsPartyLeader() or GetNumPartyMembers() == 0 then
					OGF_Print("Attempting reinvite.")
					InviteByName(ogf_Reinvite.name)
					-- schedule next retry
					ogf_Reinvite.nextInvite = now + (ogf_Reinvite.interval or 5)
				else
					-- Not leader—try again later
					OGF_Print("Attempting reinvite but not leader.")
					ogf_Reinvite.nextInvite = now + (ogf_Reinvite.interval or 5)
				end
			end
		end
	else
		--OGF_Print("Reinvite check failed.")
	end
				
	-- brief pause after drinking detection
    if drinkPause < 15 then
        drinkPause = drinkPause + 1
        return
    end

    if PlayerFrame.inCombat then
        return
    end

    if OGFEnabled and not PlayerHasDrink() then
		-- avoid “cursor spell targeting” lingering
		SpellStopTargeting()
        if UnitIsPlayer("target") then ClearTarget() end

        local currentTarget = string.lower(UnitName("target") or "")
        local hadOtherTarget = UnitExists("target") and currentTarget ~= ogfFollowTarget

        if currentTarget ~= ogfFollowTarget then
            TargetByName(ogfFollowTarget, true)
            currentTarget = string.lower(UnitName("target") or "")
        end

        if currentTarget == ogfFollowTarget then
            FollowUnit("target")
        end

        if hadOtherTarget then
            TargetLastTarget()
        elseif currentTarget == ogfFollowTarget then
            ClearTarget()
        end
    end
end

---------------------------
-- Drink Helper
---------------------------
function OGFollow_Drink()
    if PlayerHasDrink() then return end

    local drinkPriorityList = {
        "Conjured Mana Orange",
        "Conjured Crystal Water",
        "Conjured Sparkling Water",
        "Morning Glory Dew",
    }

    for _, drinkName in ipairs(drinkPriorityList) do
        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do
                local itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    local startPos, endPos = string.find(itemLink, "%[.*%]")
                    if startPos and endPos then
                        local itemName = string.sub(itemLink, startPos + 1, endPos - 1)
                        if itemName == drinkName then
                            UseContainerItem(bag, slot)
                            DEFAULT_CHAT_FRAME:AddMessage("Drinking: " .. itemName)
                            drinkPause = 0
                            return
                        end
                    end
                end
            end
        end
    end

    DEFAULT_CHAT_FRAME:AddMessage("No listed drinks found.")
end

---------------------------
-- Assist
---------------------------
function OGFollow_Assist()
    local unitID = nil
    if UnitIsPlayer("target") or UnitIsDead("target") then
        ClearTarget()
    end

    -- party scan first (Turtle API)
    if GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party"..i)
            if name and string.lower(name) == string.lower(ogfFollowTarget) then
                unitID = "party"..i
                break
            end
        end
    end

    if unitID then
        AssistUnit(unitID)
        return
    end

    -- not in party: try by name
    TargetByName(ogfFollowTarget, true)
    if UnitExists("target") and string.lower(UnitName("target") or "") == string.lower(ogfFollowTarget) then
        AssistUnit("target")
    end
end

---------------------------
-- LazyScript Party Router
---------------------------
function OGFollow_RunLazyScriptForPartySize()
    SpellStopTargeting()
    local lsHandler = SlashCmdList["LAZYSCRIPT"]
    if type(lsHandler) ~= "function" then
        DEFAULT_CHAT_FRAME:AddMessage("LazyScript handler not found.")
        return
    end

    local partySize = GetNumPartyMembers() -- excludes player
    local num = math.max(1, math.min(5, partySize + 1))
    local command = "holy" .. tostring(num)
    lsHandler(command)
end

---------------------------
-- Priest Hybrid Helper
---------------------------
local recentCasts = { shield = {}, renew = {} }

local function MarkRecentlyCast(spellType, unit, now)
    local name = UnitName(unit)
    if name then recentCasts[spellType][name] = now end
end

local function recentlyCast(spellType, unit, now)
    local name = UnitName(unit)
    return name and recentCasts[spellType][name] and (now - recentCasts[spellType][name] < 2)
end

local function CleanupRecentCasts(now)
    for _, castTable in pairs(recentCasts) do
        for name, t in pairs(castTable) do
            if now - t >= 2 then castTable[name] = nil end
        end
    end
end

local function HasAura(unit, auraName)
    local i = 1
    while true do
        local buff = UnitBuff(unit, i)
        if not buff then break end
        if buff == auraName then return true end
        i = i + 1
    end
    return false
end

local function IsSpellOnCooldown(spellName)
    for i = 1, 120 do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if name == spellName then
            local start, duration, enabled = GetSpellCooldown(i, BOOKTYPE_SPELL)
            return (enabled == 1 and duration > 0 and (start + duration - GetTime()) > 0)
        end
    end
    -- if unknown, be conservative
    return true
end

local function IsSpellKnown(spellName)
    for i = 1, 120 do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if name == spellName then return true end
    end
    return false
end

function OGFollow_PriestHybrid()
    -- throttle
    local now = GetTime()
    if (now - lastCall) < 0.5 then return end
    lastCall = now

    SpellStopTargeting()

    local lsHandler = SlashCmdList["LAZYSCRIPT"]
    local qhHandler = SlashCmdList["QUICKHEAL"]
    if type(lsHandler) ~= "function" then DEFAULT_CHAT_FRAME:AddMessage("LazyScript handler not found."); return end
    if type(qhHandler) ~= "function" then DEFAULT_CHAT_FRAME:AddMessage("QuickHeal handler not found."); return end

    CleanupRecentCasts(now)

    local playerHealth = UnitHealth("player") / math.max(1, UnitHealthMax("player"))

    -- 1) Player emergency
    if playerHealth < 0.60 and not UnitIsDeadOrGhost("player") then
        qhHandler("party"); return
    end

    -- 1b) Party/pets emergencies
    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            local hp = UnitHealth(unit) / math.max(1, UnitHealthMax(unit))
            if hp < 0.60 and CheckInteractDistance(unit, 4) then
                qhHandler("party"); return
            end
        end
        local pet = "partypet"..i
        if UnitExists(pet) and not UnitIsDeadOrGhost(pet) then
            local hp = UnitHealth(pet) / math.max(1, UnitHealthMax(pet))
            if hp < 0.60 and CheckInteractDistance(pet, 4) then
                qhHandler("party"); return
            end
        end
    end

    -- 2) Maintenance (Shield/Renew) for < 90%
    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            local hp = UnitHealth(unit) / math.max(1, UnitHealthMax(unit))
            if hp < 0.90 and CheckInteractDistance(unit, 4) then
                if not HasAura(unit, "Weakened Soul")
                    and not IsSpellOnCooldown("Power Word: Shield")
                    and not recentlyCast("shield", unit, now) then

                    local hadTarget = UnitExists("target")
                    local isNPC    = hadTarget and not UnitIsPlayer("target")

                    TargetUnit(unit)
                    CastSpellByName("Power Word: Shield")
                    SpellTargetUnit(unit)
                    if isNPC then TargetLastTarget() else ClearTarget() end

                    MarkRecentlyCast("shield", unit, now)
                    return
                elseif not HasAura(unit, "Renew")
                    and IsSpellKnown("Renew")
                    and not recentlyCast("renew", unit, now) then

                    local hadTarget = UnitExists("target")
                    local isNPC    = hadTarget and not UnitIsPlayer("target")

                    TargetUnit(unit)
                    CastSpellByName("Renew")
                    SpellTargetUnit(unit)
                    if isNPC then TargetLastTarget() else ClearTarget() end

                    MarkRecentlyCast("renew", unit, now)
                    return
                end
            end
        end
    end

    -- 3) Default
    lsHandler("healdps")
end

---------------------------
-- ItemRack / Spec
---------------------------
local function OGFollow_ItemRack(setName)
    local irHandler = SlashCmdList["ItemRackCOMMAND"]
    if type(irHandler) ~= "function" then OGF_Print("ItemRack not available."); return end
    if not setName then OGF_Print("No ItemRack set provided."); return end
    irHandler("equip " .. setName)
    OGF_Print("ItemRack: Equipping set '" .. setName .. "'")
end

local function OGFollow_GetDominantSpec()
    local maxPoints, dominantSpec = 0, nil
    for tab = 1, GetNumTalentTabs() do
        local name, _, points = GetTalentTabInfo(tab)
        if points > maxPoints then maxPoints, dominantSpec = points, name end
    end
    return dominantSpec
end

function OGFollow_RunSpecEquip()
    local spec = OGFollow_GetDominantSpec()
    if not spec then OGF_Print("Unable to determine dominant spec."); return end
    local mappedSet = OGF_CharOptions.SpecSets and OGF_CharOptions.SpecSets[string.lower(spec)]
    if not mappedSet then OGF_Print("No ItemRack set mapped to spec: " .. spec); return end
    OGFollow_ItemRack(mappedSet)
end

---------------------------
-- Herb Tools (Bank)
---------------------------
local function OGF_Herb_EnsureList()
    OGF_CharOptions = OGF_CharOptions or {}
    OGF_CharOptions.HerbList = OGF_CharOptions.HerbList or {}  -- [itemID] = true
    return OGF_CharOptions.HerbList
end

local function ogf_msg(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff88ff88OGF|r "..tostring(msg)) end

-- item link -> itemID
local function OGF_ItemIDFromLink(link)
    if not link then return nil end
    local low = string.lower(link)
    local hPosLow = string.find(low, "|hitem:")
    if not hPosLow then return nil end
    local startIdx = hPosLow + 7
    local colon = string.find(link, ":", startIdx, true)
    if not colon then return nil end
    return tonumber(string.sub(link, startIdx, colon - 1))
end

local function OGF_IsBankOpen()
    return BankFrame and BankFrame:IsVisible()
end

local function OGF_ForEachBankSlot(doSlot)
    local mainSlots = GetContainerNumSlots(-1) or 0
    for slot = 1, mainSlots do
        if doSlot(-1, slot) == false then return end
    end
    local purchased = GetNumBankSlots() or 0
    for i = 1, purchased do
        local bag = 4 + i
        local bslots = GetContainerNumSlots(bag) or 0
        for slot = 1, bslots do
            if doSlot(bag, slot) == false then return end
        end
    end
end

local function OGF_PutItemInAnyBag()
    if not CursorHasItem() then return false end
    PutItemInBackpack()
    if not CursorHasItem() then return true end
    for bagIndex = 1, 4 do
        PutItemInBag(19 + bagIndex)  -- 20..23
        if not CursorHasItem() then return true end
    end
    return false
end

function OGF_Herb_ToggleByLink(link)
    local list = OGF_Herb_EnsureList()
    local id = OGF_ItemIDFromLink(link)
    if not id then ogf_msg("Could not read item link. Shift-click the herb link into chat."); return end
    if list[id] then list[id] = nil; ogf_msg("Removed herb ID "..id.." from selection.")
    else list[id] = true; ogf_msg("Added herb ID "..id.." to selection.") end
end

function OGF_Herb_Clear()
    OGF_CharOptions.HerbList = {}
    ogf_msg("Herb selection cleared.")
end

local function OGF_Herb_LinkForID(id)
    local name = GetItemInfo(id)
    local linkText = "[" .. (name or ("item " .. id)) .. "]"
    return "|Hitem:" .. id .. ":0:0:0|h" .. linkText .. "|h"
end

function OGF_Herb_List()
    local list, n = OGF_Herb_EnsureList(), 0
    for _ in pairs(list) do n = n + 1 end
    if n == 0 then ogf_msg("Herb selection is empty."); return end
    ogf_msg("Selected herbs ("..n.."):")
    for id in pairs(list) do OGFollow_LocalMsg(" - " .. OGF_Herb_LinkForID(id) .. " [" .. id .. "]") end
end

function OGF_Herb_PullSelected()
    if not OGF_IsBankOpen() then ogf_msg("Open the bank first."); return end
    local list = OGF_Herb_EnsureList()
    local moved, stoppedForSpace = 0, false

    OGF_ForEachBankSlot(function(bag, slot)
        if stoppedForSpace then return false end
        local link = GetContainerItemLink(bag, slot)
        if link then
            local id = OGF_ItemIDFromLink(link)
            if id and list[id] then
                local _, _, locked = GetContainerItemInfo(bag, slot)
                if not locked then
                    ClearCursor()
                    PickupContainerItem(bag, slot)
                    if CursorHasItem() then
                        if OGF_PutItemInAnyBag() then
                            moved = moved + 1
                        else
                            stoppedForSpace = true
                            ClearCursor()
                            return false
                        end
                    end
                end
            end
        end
        -- continue
    end)

    if stoppedForSpace then ogf_msg("Bags are full. Moved "..moved.." stack(s).")
    else ogf_msg("Moved "..moved.." stack(s) of selected herbs.") end
end

-- /ogf herb dispatcher
function OGF_HandleHerb(rest)
    local arg = OGF_Trim(rest or "")
    local lower = string.lower(arg)

    if lower == "list" then OGF_Herb_List(); return end
    if lower == "clear" then OGF_Herb_Clear(); return end

    -- toggle by link
    if arg ~= "" and string.find(lower, "|hitem:") then
        OGF_Herb_ToggleByLink(arg); return
    end

    -- pull
    if arg == "" then
        local list = OGF_Herb_EnsureList()
        local hasAny = next(list) ~= nil
        if not hasAny then ogf_msg("No herbs selected. Use /ogf herb [item link] to add, or /ogf herb list."); return end
        if not OGF_IsBankOpen() then ogf_msg("Open the bank first."); return end
        OGF_Herb_PullSelected()
        return
    end

    ogf_msg("Usage:")
    ogf_msg("/ogf herb — pull selected herbs (bank open)")
    ogf_msg("/ogf herb [item link] — add/remove herb")
    ogf_msg("/ogf herb list — show selected herbs")
    ogf_msg("/ogf herb clear — clear selection")
end

---------------------------
-- Cast Sequences (/ogf cs)
---------------------------
-- Stored at: OGF_CharOptions.CastSequences[name] = { spells={}, index=1, reset=number|nil, last=GetTime() }
local function OGF_CS_Init()
    OGF_CharOptions = OGF_CharOptions or {}
    OGF_CharOptions.CastSequences = OGF_CharOptions.CastSequences or {}
end

function OGF_OnVariablesLoaded_CS()
    OGF_CS_Init()
end

-- Accepts "0.1", "0,1", "10", "10s", "0.1s" etc.; returns number or nil
local function OGF_ParseSeconds(raw)
    raw = OGF_Trim(raw or "")
    if raw == "" then return nil end
    -- strip trailing 's' or 'S'
    raw = string.gsub(raw, "%s*[sS]%s*$", "")

    -- first try as-is
    local num = tonumber(raw)
    if num then return num + 0.0 end

    -- try swapping decimal separators (locale-friendly)
    if string.find(raw, ",", 1, true) then
        local swapped = string.gsub(raw, ",", ".")
        num = tonumber(swapped)
        if num then return num + 0.0 end
    elseif string.find(raw, "%.", 1) then
        local swapped = string.gsub(raw, "%.", ",")
        num = tonumber(swapped)
        if num then return num + 0.0 end
    end

    return nil
end

local function OGF_CS_SplitCSV(csv)
    local out, start = {}, 1
    csv = csv or ""
    while true do
        local cs, ce = string.find(csv, ",", start, true)
        local field
        if cs then field = string.sub(csv, start, cs - 1); start = ce + 1
        else field = string.sub(csv, start) end
        field = OGF_Trim(field)
        if field ~= "" then table.insert(out, field) end
        if not cs then break end
    end
    return out
end

local function OGF_CS_ExtractBraced(text)
    local results, i, n = {}, 1, string.len(text or "")
    while i <= n do
        local s = string.find(text, "{", i, true)
        if not s then break end
        local e = string.find(text, "}", s + 1, true)
        if not e then break end
        local inner = string.sub(text, s + 1, e - 1)
        table.insert(results, inner)
        i = e + 1
    end
    return results
end

local function OGF_CS_Add(sequenceName, spells, resetSeconds)
    OGF_CS_Init()
    local key = string.lower(OGF_Trim(sequenceName or ""))
    if key == "" then OGF_Print("cs add: missing sequence name."); return end
    if not spells or table.getn(spells) == 0 then OGF_Print("cs add: provide at least one spell in { }."); return end
    OGF_CharOptions.CastSequences[key] = { spells = spells, index = 1, reset = resetSeconds, last = 0 }
    local spellCount = table.getn(spells)
    OGF_Print("cs add: '"..key.."' ("..spellCount.." spell(s)) reset="..(resetSeconds and (tostring(resetSeconds).."s") or "none"))
end

local function OGF_CS_Del(sequenceName)
    OGF_CS_Init()
    local key = string.lower(OGF_Trim(sequenceName or ""))
    if key == "" then OGF_Print("cs del: missing sequence name."); return end
    if not OGF_CharOptions.CastSequences[key] then OGF_Print("cs del: '"..key.."' not found."); return end
    OGF_CharOptions.CastSequences[key] = nil
    OGF_Print("cs del: '"..key.."' removed.")
end

local function OGF_CS_List()
    OGF_CS_Init()
    OGF_Print("Cast Sequences:")
    local any = false
    for name, seq in pairs(OGF_CharOptions.CastSequences) do
        any = true
        local idx = seq.index or 1
        local total = (seq.spells and table.getn(seq.spells)) or 0
        local reset = seq.reset and (tostring(seq.reset).."s") or "none"
        OGF_Print(" - "..name.."  ["..idx.."/"..total.."]  reset="..reset)
    end
    if not any then OGF_Print(" (none)") end
end

local function OGF_CS_CastNext(sequenceName)
    OGF_CS_Init()
    local key = string.lower(OGF_Trim(sequenceName or ""))
    if key == "" then OGF_Print("cs: missing sequence name."); return end

    local seq = OGF_CharOptions.CastSequences[key]
    if not seq then OGF_Print("cs: '"..key.."' not found."); return end
    if not seq.spells or table.getn(seq.spells) == 0 then OGF_Print("cs '"..key.."': empty spell list."); return end

    local now = GetTime()
    if seq.reset and seq.reset > 0 and seq.last and seq.last > 0 then
        if (now - seq.last) > seq.reset then seq.index = 1 end
    end

    local idx = seq.index or 1
    local total = table.getn(seq.spells)
    if idx < 1 or idx > total then idx = 1 end

    local spellName = seq.spells[idx]
    if not spellName or spellName == "" then OGF_Print("cs '"..key.."': invalid spell at index "..idx.."."); return end

    CastSpellByName(spellName)
    seq.last = now
    idx = idx + 1; if idx > total then idx = 1 end
    seq.index = idx
    OGF_Print("cs '"..key.."': cast "..spellName.." -> next "..seq.spells[idx])
end

local function OGF_Cmd_CS(rest)
    rest = OGF_Trim(rest or "")

    if string.lower(rest) == "list" then OGF_CS_List(); return end

    if string.lower(string.sub(rest, 1, 4)) == "del " then
        local name = OGF_Trim(string.sub(rest, 5))
        OGF_CS_Del(name); return
    end

    if string.lower(string.sub(rest, 1, 4)) == "add " then
        local afterAdd = OGF_Trim(string.sub(rest, 5) or "")
        local firstBrace = string.find(afterAdd, "{", 1, true)
        local seqName = firstBrace and OGF_Trim(string.sub(afterAdd, 1, firstBrace - 1)) or OGF_Trim(afterAdd)
        if seqName == "" then OGF_Print("cs add: missing sequence name."); return end

        local blocks = OGF_CS_ExtractBraced(afterAdd)
        if not blocks[1] then OGF_Print("cs add: provide {spell1,spell2,...}"); return end

        local spells = OGF_CS_SplitCSV(blocks[1])
        local resetSeconds = nil
        if blocks[2] then
			resetSeconds = OGF_ParseSeconds(blocks[2])
			if not resetSeconds then
				OGF_Print("cs add: invalid reset '"..OGF_Trim(blocks[2]).."'. Using no reset.")
			end
		end


        OGF_CS_Add(seqName, spells, resetSeconds)
        return
    end

    if rest == "" then
        OGF_Print("Usage:")
        OGF_Print("/ogf cs list")
        OGF_Print("/ogf cs del <sequenceName>")
        OGF_Print("/ogf cs add <sequenceName> {spell1,spell2,...} {resetSeconds}")
        OGF_Print("/ogf cs <sequenceName>")
        return
    end

    OGF_CS_CastNext(rest)
end

---------------------------
-- Twink Tools
---------------------------
-- Return "party1".."party4" if the given name is in your party, else nil
local function OGF_GetPartyUnitIdByName(name)
    if not name or name == "" then return nil end
    local want = string.lower(name)
    for i = 1, 4 do
        local n = UnitName("party"..i)
        if n and string.lower(n) == want then
            return "party"..i
        end
    end
    return nil
end

-- /ogf healtwink
-- Invite ogfFollowTarget if player's HP < 80%.
-- Remove ogfFollowTarget from party once player's HP > 80%.
function OGFollow_HealthTwink()
    local followName = ogfFollowTarget
    if not followName or followName == "" then return end

    local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
    if not hpMax or hpMax <= 0 then return end

    local THRESH = 80

    -- Is follow target in party?
    local inParty = false
    local followLower = string.lower(followName)
    for i = 1, 4 do
        local n = UnitName("party"..i)
        if n and string.lower(n) == followLower then
            inParty = true
            break
        end
    end

    local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or false

    local function canInvite()
        return GetNumPartyMembers() == 0 or IsPartyLeader()
    end
    local function invite()
        if canInvite() then
            InviteByName(followName)
        else
            OGF_Print("Cannot invite "..followName..": not party leader.")
        end
    end

    -- Out of combat: never remove; ensure they're in the party
    if not inCombat then
        if not inParty then
            invite()
        end
        return
    end

    -- In combat:
    -- below 80% HP -> ensure invited
    if (hp * 100) < (hpMax * THRESH) then
        if not inParty then
            invite()
        end
        return
    end

    -- above 80% HP -> remove if present (only in combat)
    if (hp * 100) > (hpMax * THRESH) then
        if inParty then
            if not IsPartyLeader() then
                OGF_Print("Cannot remove "..followName..": not party leader.")
                return
            end
            if UninviteByName then
                UninviteByName(followName)
            elseif UninviteUnit then
                UninviteUnit(followName)
            else
                OGF_Print("Unable to uninvite on this client build.")
            end
        end
        return
    end
end


-- /ogf twinkheal <healsequence>
-- If ogfFollowTarget is in party: target them and trigger the cast sequence as if "/ogf cs <healsequence>"
function OGFollow_TwinkHeal(sequenceName)
    if not sequenceName or sequenceName == "" then return end
    local followName = ogfFollowTarget
    if not followName or followName == "" then return end

    local unitId = OGF_GetPartyUnitIdByName(followName)
    if not unitId then
        -- Not in party: do nothing
        return
    end

    local hadTarget = UnitExists("target")

    -- Target the follow target
    TargetUnit(unitId)

    -- Fire the cast-sequence exactly like "/ogf cs <sequenceName>"
    if type(OGF_Cmd_CS) == "function" then
        OGF_Cmd_CS(sequenceName)
    else
        OGF_Print("Cast sequence system not available.")
    end

    -- Restore previous target
    if hadTarget then
        TargetLastTarget()
    else
        ClearTarget()
    end
end


function OGFollow_TwinkTag(parms)
	local arg = parms[2]
		if not arg then
			OGF_Print("Usage: /ogf twink <percent>")
			return
		end
		
		

		local pct = tonumber(arg)
		if not pct then
			OGF_Print("Invalid percent: "..tostring(arg))
			return
		end
		
		if pct < 1 then pct = 1 elseif pct > 100 then pct = 100 end

		if (GetNumPartyMembers() > 0) and UnitExists("target") then
			local h, m = UnitHealth("target"), UnitHealthMax("target")
			if m > 0 and (h * 100) < (m * pct) then
			--if true then -- Debug.
				-- Kick ogfFollowTarget instead of leaving party
				local kick = ogfFollowTarget
				if not kick or kick == "" then
					OGF_Print("No ogfFollowTarget set to kick.")
					return
				end
				if not IsPartyLeader() then
					OGF_Print("You must be party leader to remove "..kick..".")
					return
				end

				-- verify the target is actually in your party
				local inParty = false
				local kickLower = string.lower(kick)
				for i = 1, 4 do
					local name = UnitName("party"..i)
					if name and string.lower(name) == kickLower then
						inParty = true
						break
					end
				end

				if inParty then
					if UninviteByName then
						UninviteByName(kick)
					elseif UninviteUnit then
						UninviteUnit(kick)
					else
						OGF_Print("Unable to uninvite on this client build.")
						return
					end

					-- Start 45s reinvite window
					ogf_Reinvite.active     = true
					ogf_Reinvite.name       = kick
					ogf_Reinvite.startedAt  = GetTime()
					ogf_Reinvite.nextInvite = ogf_Reinvite.startedAt + 30   -- first reinvite at 45s
					ogf_Reinvite.interval   = 1                              -- retry every 5s after first try
					ogf_Reinvite.timeoutAt  = ogf_Reinvite.startedAt + 65   -- stop after 3 minutes (safety)
					OGF_Print("Removed "..kick..". Will reinvite in 30s.")
				else
					--OGF_Print(kick.." is not in your party.")
					
				end
				return
			end	
		end

		if not UnitExists("target") or (UnitHealth("player") / UnitHealthMax("player") < 0.3) then
			InviteByName(ogfFollowTarget)
		end
end

function OGF_TryScorpionArcane()

    local lsHandler = SlashCmdList["LAZYSCRIPT"]
    local hasTarget = UnitExists("target")
    local isNPC = hasTarget and not UnitIsPlayer("target")
    local isScorpion = hasTarget and (UnitName("target") == "Qiraji Scorpion")

    if (not hasTarget) or (not isNPC) or (not isScorpion) then
        -- One action this press: attempt to acquire the correct target
        TargetNearestEnemy() -- exact-match usually OK on Turtle
        return
    end

    -- One action this press: perform the arcane action via /ls
    lsHandler("arcane")
end

---------------------------
-- Command Parser (/ogf)
---------------------------
function ogFollow_CmdParser(parm1)
    parm1 = tostring(parm1 or "")
    if parm1 == "" then parm1 = "help" end

    local parm = parm1
    local rest = ""
    do
        local space = string.find(parm, " ")
        if space then rest = string.sub(parm, space + 1) end
    end

    local parms = splitBySpace(parm)

    if parms[1] == "help" then
        OGF_Print(MOD_NAME.." v"..FMVer)
        OGF_Print("Usage:")
        OGF_Print("/ogf status     - Show status")
        OGF_Print("/ogf target <name>")
        OGF_Print("/ogf enable|disable")
        OGF_Print("/ogf combat     - Toggle following during combat")
        OGF_Print("/ogf assist     - Assist follow target")
        OGF_Print("/ogf drink      - Use best drink in bags")
        OGF_Print("/ogf herb [...] - Herb selection tools")
        OGF_Print("/ogf spec [...] - ItemRack set mapping")
        OGF_Print("/ogf cs   [...] - Cast sequences")
        return
    end

    local cmd = string.lower(parms[1] or "")
	
	if cmd == "aq40" then
		OGF_TryScorpionArcane()
		return
	end
	
	if cmd == "healtwink" then
		OGFollow_HealthTwink()
	end
	
	if cmd == "twinkheal" then
		OGFollow_TwinkHeal()
	end
	
	if cmd == "twink" then
		OGFollow_TwinkTag(parms)
		return
	end


    if cmd == "status" then
        local msg = OGFEnabled and "Enabled" or "Disabled"
        local combatStatus = ogfCombat and "Follow During Combat: True (breaks autoattack in group)" or "Follow During Combat: False"
        OGF_Print("OG-Follow: "..msg)
        OGF_Print("Target: "..(ogfFollowTarget or ""))
        OGF_Print(combatStatus)
        return
    end

    if cmd == "combat" then
        ogfCombat = not ogfCombat
        OGF_CharOptions.Combat = ogfCombat
        if ogfCombat then
            OGF_Print("Follow during Combat Toggled ON.")
            OGF_Print("NOTE: This does not work outside of party!")
        else
            OGF_Print("Follow during Combat Toggled OFF.")
        end
        return
    end

    if cmd == "target" then
        local tName = parms[2]
        if not tName then
            OGF_Print("OGFollow Target Required")
            UIErrorsFrame:AddMessage("OGFollow Target Required", 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
            return
        end
        ogfFollowTarget = tName
        OGF_CharOptions.Target = tName
        OGF_Print("OGFollow Target Set "..tName)
        UIErrorsFrame:AddMessage("OGFollow Target Set "..tName, 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
        return
    end

    if cmd == "enable" and not OGFEnabled then OGFEnabled = true;  OGF_Print("OGFollow Enabled");  return end
    if cmd == "disable" and OGFEnabled then OGFEnabled = false; OGF_Print("OGFollow Disabled"); return end

    if cmd == "assist" then OGFollow_Assist(); return end

    -- ItemRack spec mapping
    if cmd == "spec" then
        local setTalent, setName = parms[2], parms[3]
        OGF_Print("ItemRack Integration")

        if string.lower(setTalent or "") == "list" then
            if not OGF_CharOptions.SpecSets or next(OGF_CharOptions.SpecSets) == nil then
                OGF_Print("No spec mappings defined.")
            else
                OGF_Print("Current Spec -> ItemRack mappings:")
                for talent, set in pairs(OGF_CharOptions.SpecSets) do
                    OGF_Print("  " .. talent .. " => " .. set)
                end
            end
            return
        end

        if string.lower(setTalent or "") == "clear" then
            OGF_CharOptions.SpecSets = {}
            OGF_Print("All spec mappings cleared.")
            return
        end

        if not setTalent and not setName then
            OGF_Print("Checking talents and calling ItemRack.")
            local spec = OGFollow_GetDominantSpec()
            if not spec then OGF_Print("Unable to determine dominant spec."); return end
            local mappedSet = OGF_CharOptions.SpecSets and OGF_CharOptions.SpecSets[string.lower(spec)]
            if not mappedSet then OGF_Print("No ItemRack set mapped to spec: " .. spec); return end
            OGFollow_ItemRack(mappedSet)
            return
        end

        if setTalent and setName then
            OGF_CharOptions.SpecSets = OGF_CharOptions.SpecSets or {}
            OGF_CharOptions.SpecSets[string.lower(setTalent)] = setName
            OGF_Print("Mapped talent tree '"..setTalent.."' to ItemRack set '"..setName.."'")
            return
        end

        if setTalent == "help" then
            OGF_Print("Usage:")
            OGF_Print("/ogf spec [TalentTree] [SetName] - Register a set")
            OGF_Print("/ogf spec - Equip set based on dominant talent tree")
            OGF_Print("/ogf spec list - List current mappings")
            OGF_Print("/ogf spec clear - Remove all mappings")
            return
        end
    end

    if cmd == "ls"     then OGFollow_RunLazyScriptForPartySize(); return end
    if cmd == "priest" then OGFollow_PriestHybrid(); return end
    if cmd == "drink"  then OGFollow_Drink(); return end

    if cmd == "ds" then
        local i, spellName, rank, texture = 1
        while true do
            spellName, rank = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then break end
            texture = GetSpellTexture(i, BOOKTYPE_SPELL)
            DEFAULT_CHAT_FRAME:AddMessage(i..". "..spellName.." ("..(rank or "No Rank")..") - "..(texture or "No Texture"))
            i = i + 1
        end
        return
    end

    if cmd == "herb" then
        OGF_HandleHerb(rest or "")
        return
    end

    if cmd == "cs" then
        OGF_Cmd_CS(rest)
        return
    end
end
