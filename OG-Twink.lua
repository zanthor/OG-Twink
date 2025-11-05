-- =========================================================
-- OG-Twink (Turtle WoW 1.12)
-- Author: Zanthor
-- Ported from OG-Follow twink functionality
-- =========================================================

---------------------------
-- Constants & State
---------------------------
local MOD_NAME = "OG-Twink"
local VERSION  = "1.0.0"

-- Runtime state
local OGTEnabled        = false
local ogfFollowTarget   = "Gnuzmas"
local following         = nil
local combat            = false
local drinkPause        = 10
local lastTick          = GetTime()

-- Saved variables declared in TOC
OGTwinkDB = OGTwinkDB or {
    Version = 1.0,
    Target = "Gnuzmas",
    Enabled = false,
}

---------------------------
-- Frame & Events
---------------------------
local OGTFrame = CreateFrame("Frame")

-- XML OnUpdate calls this every frame.
function ogt_onesecondtick()
    local now = GetTime()
    if now - lastTick >= 1 then
        lastTick = now
        OGT_OneSecondTick()
    end
end

-- Called once per second by the wrapper above
function OGT_OneSecondTick()
    OGTwink_Strobe()
end

---------------------------
-- UI Helpers
---------------------------
local function OGT_Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffOGT|r: "..tostring(msg))
end

local function OGT_Trim(s)
    s = tostring(s or "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
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
-- Initialize options on first load
OGTwink_InitOptions = function()
    OGTwinkDB = OGTwinkDB or {}
    OGTwinkDB.Target = OGTwinkDB.Target or "Gnuzmas"
    OGTwinkDB.Enabled = (OGTwinkDB.Enabled ~= nil) and OGTwinkDB.Enabled or false

    ogfFollowTarget = OGTwinkDB.Target
    OGTEnabled = OGTwinkDB.Enabled
end

-- Register slash commands at file load
SLASH_OGTWINK1 = "/ogt"
SLASH_OGTWINK2 = "/ogtwink"
SlashCmdList["OGTWINK"] = function(msg)
    ogTwink_CmdParser(msg)
end

-- Print load message
local LOAD_MSG = MOD_NAME.." ["..VERSION.."] loaded"
DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffOGT|r: "..LOAD_MSG)
DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffOGT|r: /ogtwink or /ogt for usage instructions.")
UIErrorsFrame:AddMessage(LOAD_MSG, 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)

-- Event handler
OGTFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        OGTwink_InitOptions()
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

    -- Auto-accept only from follow target; decline others
    if event == "PARTY_INVITE_REQUEST" then
        local inviter = arg1
        local target  = ogfFollowTarget or (OGTwinkDB and OGTwinkDB.Target) or ""

        if inviter and target and string.lower(inviter) == string.lower(target) then
            AcceptGroup()
            StaticPopup_Hide("PARTY_INVITE")
            OGT_Print("Auto-accepted party invite from "..inviter..".")
        elseif inviter == "Gnuzherbs" then
            AcceptGroup()
            StaticPopup_Hide("PARTY_INVITE")
            OGT_Print("Auto-accepted party invite from "..inviter..".")
        else
            OGT_Print("Declined party invite from "..(inviter or "?").." (not follow target).")
        end
        return
    end
end)

-- Register events
OGTFrame:RegisterEvent("VARIABLES_LOADED")
OGTFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
OGTFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
OGTFrame:RegisterEvent("AUTOFOLLOW_BEGIN")
OGTFrame:RegisterEvent("AUTOFOLLOW_END")
OGTFrame:RegisterEvent("PARTY_INVITE_REQUEST")

---------------------------
-- Follow / Strobe
---------------------------
-- Lua-side fallback: ensure we tick even if XML doesn't wire OnUpdate
if OGTFrame and not OGTFrame.__ogt_onupdate then
    OGTFrame.__ogt_onupdate = true
    OGTFrame:SetScript("OnUpdate", function()
        if type(ogt_onesecondtick) == "function" then
            ogt_onesecondtick()
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
ogt_Reinvite = ogt_Reinvite or { active = false }

local function OGT_IsInParty(name)
    if not name or name == "" then return false end
    local want = string.lower(name)
    for i = 1, 4 do
        local n = UnitName("party"..i)
        if n and string.lower(n) == want then return true end
    end
    return false
end

function OGTwink_Strobe()
    if ogt_Reinvite and ogt_Reinvite.active and ogt_Reinvite.name and ogt_Reinvite.name ~= "" then
        -- If they already rejoined, stop
        if OGT_IsInParty(ogt_Reinvite.name) then
            OGT_Print(ogt_Reinvite.name.." rejoined. Stopping reinvites.")
            ogt_Reinvite.active = false
        else
            local now = GetTime()
            -- Give up after timeout window (prevents infinite spam)
            if ogt_Reinvite.timeoutAt and now >= ogt_Reinvite.timeoutAt then
                OGT_Print("Reinvite window expired for "..ogt_Reinvite.name..".")
                ogt_Reinvite.active = false
            -- Primary reinvite at 30s
            elseif ogt_Reinvite.firstInvite and now >= ogt_Reinvite.firstInvite and not ogt_Reinvite.firstSent then
                if IsPartyLeader() or GetNumPartyMembers() == 0 then
                    OGT_Print("Sending primary reinvite (30s)...")
                    InviteByName(ogt_Reinvite.name)
                    ogt_Reinvite.firstSent = true
                else
                    OGT_Print("Cannot send reinvite - not party leader.")
                end
            -- Fallback reinvite at 40s
            elseif ogt_Reinvite.fallbackInvite and now >= ogt_Reinvite.fallbackInvite and not ogt_Reinvite.fallbackSent then
                if IsPartyLeader() or GetNumPartyMembers() == 0 then
                    OGT_Print("Sending fallback reinvite (40s)...")
                    InviteByName(ogt_Reinvite.name)
                    ogt_Reinvite.fallbackSent = true
                else
                    OGT_Print("Cannot send reinvite - not party leader.")
                end
            -- Continuous retry after fallback
            elseif ogt_Reinvite.nextInvite and now >= ogt_Reinvite.nextInvite and ogt_Reinvite.fallbackSent then
                if IsPartyLeader() or GetNumPartyMembers() == 0 then
                    OGT_Print("Retrying reinvite...")
                    InviteByName(ogt_Reinvite.name)
                    -- schedule next retry
                    ogt_Reinvite.nextInvite = now + 2  -- retry every 2s after fallback
                else
                    -- Not leader—try again later
                    ogt_Reinvite.nextInvite = now + 2
                end
            end
        end
    end
                
    -- brief pause after drinking detection
    if drinkPause < 15 then
        drinkPause = drinkPause + 1
        return
    end

    if PlayerFrame.inCombat then
        return
    end

    if OGTEnabled and not PlayerHasDrink() then
        -- avoid "cursor spell targeting" lingering
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
-- Twink Tools
---------------------------
-- Return "party1".."party4" if the given name is in your party, else nil
local function OGT_GetPartyUnitIdByName(name)
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

-- /ogt healtwink
-- Invite ogfFollowTarget if player's HP < 80%.
-- Remove ogfFollowTarget from party once player's HP > 80%.
function OGTwink_HealthTwink()
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
            OGT_Print("Cannot invite "..followName..": not party leader.")
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
                OGT_Print("Cannot remove "..followName..": not party leader.")
                return
            end
            if UninviteByName then
                UninviteByName(followName)
            elseif UninviteUnit then
                UninviteUnit(followName)
            else
                OGT_Print("Unable to uninvite on this client build.")
            end
        end
        return
    end
end

function OGTwink_TwinkTag(parms)
    local arg = parms[2]
    if not arg then
        OGT_Print("Usage: /ogt twink <percent>")
        return
    end

    local pct = tonumber(arg)
    if not pct then
        OGT_Print("Invalid percent: "..tostring(arg))
        return
    end
    
    if pct < 1 then pct = 1 elseif pct > 100 then pct = 100 end

    if (GetNumPartyMembers() > 0) and UnitExists("target") then
        local h, m = UnitHealth("target"), UnitHealthMax("target")
        if m > 0 and (h * 100) < (m * pct) then
            -- Kick ogfFollowTarget instead of leaving party
            local kick = ogfFollowTarget
            if not kick or kick == "" then
                OGT_Print("No follow target set to kick.")
                return
            end
            if not IsPartyLeader() then
                OGT_Print("You must be party leader to remove "..kick..".")
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
                    OGT_Print("Unable to uninvite on this client build.")
                    return
                end

                -- Start reinvite system with dual fallback
                local now = GetTime()
                ogt_Reinvite.active         = true
                ogt_Reinvite.name           = kick
                ogt_Reinvite.startedAt      = now
                ogt_Reinvite.firstInvite    = now + 30   -- primary reinvite at 30s
                ogt_Reinvite.fallbackInvite = now + 40   -- fallback reinvite at 40s
                ogt_Reinvite.nextInvite     = now + 42   -- continuous retry starts at 42s
                ogt_Reinvite.timeoutAt      = now + 65   -- stop after 65s total
                ogt_Reinvite.firstSent      = false
                ogt_Reinvite.fallbackSent   = false
                OGT_Print("Removed "..kick..". Will reinvite at 30s (fallback at 40s).")
            end
            return
        end  
    end

    if not UnitExists("target") or (UnitHealth("player") / UnitHealthMax("player") < 0.3) then
        InviteByName(ogfFollowTarget)
    end
end

---------------------------
-- Command Parser (/ogt)
---------------------------
function ogTwink_CmdParser(parm1)
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
        OGT_Print(MOD_NAME.." v"..VERSION)
        OGT_Print("Usage:")
        OGT_Print("/ogt status      - Show status")
        OGT_Print("/ogt target <name> - Set follow target")
        OGT_Print("/ogt enable|disable - Toggle sticky follow")
        OGT_Print("/ogt healtwink   - Health-based invite/kick")
        OGT_Print("/ogt twink <pct> - Tag at target HP% for XP optimization")
        return
    end

    local cmd = string.lower(parms[1] or "")
    
    if cmd == "healtwink" then
        OGTwink_HealthTwink()
        return
    end
    
    if cmd == "twink" then
        OGTwink_TwinkTag(parms)
        return
    end

    if cmd == "status" then
        local msg = OGTEnabled and "Enabled" or "Disabled"
        OGT_Print("OG-Twink: "..msg)
        OGT_Print("Target: "..(ogfFollowTarget or ""))
        return
    end

    if cmd == "target" then
        local tName = parms[2]
        if not tName then
            OGT_Print("Target name required")
            UIErrorsFrame:AddMessage("Target name required", 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
            return
        end
        ogfFollowTarget = tName
        OGTwinkDB.Target = tName
        OGT_Print("Follow target set to "..tName)
        UIErrorsFrame:AddMessage("Follow target set to "..tName, 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
        return
    end

    if cmd == "enable" and not OGTEnabled then 
        OGTEnabled = true
        OGTwinkDB.Enabled = true
        OGT_Print("Sticky follow enabled")
        return 
    end
    
    if cmd == "disable" and OGTEnabled then 
        OGTEnabled = false
        OGTwinkDB.Enabled = false
        OGT_Print("Sticky follow disabled")
        return 
    end

    -- Default fallback
    OGT_Print("Unknown command. Use '/ogt help' for usage.")
end