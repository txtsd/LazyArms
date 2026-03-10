-- LazyArms for TurtleWoW
-- Requires pfUI (with libdebuff), Nampower, and UnitXP_SP3.

-- ============================================================================
-- 1. Dependency checks (run once at load)
-- ============================================================================

-- Check pfUI and its libdebuff
local libdebuff = pfUI and pfUI.api and pfUI.api.libdebuff
if not libdebuff then
  print("LazyArms: pfUI or its libdebuff not found – addon disabled.")
  return
end

-- Check Nampower by testing for its version
if not GetNampowerVersion or type(GetNampowerVersion) ~= "function" then
  print("LazyArms: Nampower not loaded – addon disabled.")
  return
end

-- Check UnitXP_SP3 by testing for UnitXP function
if not UnitXP or type(UnitXP) ~= "function" then
  print("LazyArms: UnitXP_SP3 not loaded – addon disabled.")
  return
end

-- ============================================================================
-- 2. Nampower configuration (safe because Nampower is present)
-- ============================================================================
SetCVar("NP_EnableAutoAttackEvents", "1")

-- ============================================================================
-- 3. Spell ID constants (unchanged)
-- ============================================================================
local SPELL_ID_CHARGE = 11578
local SPELL_ID_INTERCEPT = 20617
local SPELL_ID_INTERVENE = 45595
local SPELL_ID_OVERPOWER = 11585
local SPELL_ID_REVENGE = 11601
local SPELL_ID_SLAM = 45961
local SPELL_ID_MORTALSTRIKE = 27580
local SPELL_ID_WHIRLWIND = 1680
local SPELL_ID_BATTLE_SHOUT = 11551
local SPELL_ID_HEROIC_STRIKE = 11567
local SPELL_ID_CLEAVE = 20569
local SPELL_ID_SWEEPING_STRIKES = 12292

local STANCE_BERSERKER = 2458
local STANCE_DEFENSIVE = 71
local STANCE_BATTLE = 2457

-- ============================================================================
-- 4. Helper functions (using stored libdebuff and Nampower)
-- ============================================================================
local function get_sunder_stacks()
  if not UnitExists("target") then
    return 0
  end

  for slot = 1, 16 do
    local name, _, _, stacks, _, _, timeleft = libdebuff:UnitDebuff("target", slot)
    if name and name == "Sunder Armor" then
      return stacks, timeleft or 0
    end
  end
  return 0
end

-- Combat flag caching using Nampower's UNIT_FLAGS_GUID event
local inCombat = false
local combatFrame = CreateFrame("Frame", "LazyArmsCombatTracker")
combatFrame:RegisterEvent("UNIT_FLAGS_GUID")
combatFrame:SetScript("OnEvent", function()
  -- arg1: guid, arg2: isPlayer, arg3: isTarget, arg4: isMouseover, arg5: isPet, arg6: partyIndex, arg7: raidIndex
  if arg2 == 1 then -- only care about player
    local flags = GetUnitField("player", "flags", 1)
    local UNIT_FLAG_IN_COMBAT = 524288
    inCombat = flags and (bit.band(flags, UNIT_FLAG_IN_COMBAT) ~= 0) or false
  end
end)

-- Initialize combat flag
local flags = GetUnitField("player", "flags", 1)
inCombat = flags and (bit.band(flags, 524288) ~= 0) or false

-- Replace existing in_combat() with cached value
local function in_combat()
  return inCombat
end

local function has_buff(spellId)
  -- Retrieve the aura table for the player; indices 1‑48 correspond to slots 0‑47
  local auras = GetUnitField("player", "aura", 1)
  if not auras then
    return false
  end

  for i = 1, 48 do
    if auras[i] == spellId then
      return true
    end
  end
  return false
end

local function is_on_cooldown(spell_id)
  local cd_table = GetSpellIdCooldown(spell_id)
  if cd_table then
    local spell_is_on_cooldown = cd_table.isOnCooldown
    return spell_is_on_cooldown == 0
  end
  return false
end

-- ============================================================================
-- 5. Rotation state
-- ============================================================================
local rotationState = rotationState
  or {
    queued_attack_id = nil,
    lastAutoTime = nil,
    lastSlamCast = nil,
  }

-- ============================================================================
-- 6. Event handling (auto attack, spell queue, etc.)
-- ============================================================================
local frame_autoattack = CreateFrame("Frame", "LazyArmsAutoAttack")
frame_autoattack:RegisterEvent("AUTO_ATTACK_SELF")
frame_autoattack:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
frame_autoattack:RegisterEvent("SPELL_QUEUE_EVENT")
frame_autoattack:SetScript("OnEvent", function()
  if event == "AUTO_ATTACK_SELF" then
    local attackerGuid = arg1
    local targetGuid = arg2
    local hitInfo = arg4
    local victimState = arg5

    if hitInfo then
      -- print("Got autoattack event!")
      rotationState.lastAutoTime = GetTime()
    end
  elseif event == "SPELL_DAMAGE_EVENT_SELF" then
    local spellId = arg3
    local hitInfo = arg6

    if hitInfo then
      -- print("Got hit event: " .. GetSpellRecField(spellId, "name", 1))
    end
  elseif event == "SPELL_QUEUE_EVENT" then
    local eventCode = arg1
    local spellId = arg2

    -- eventCode values: 0=ON_SWING_QUEUED, 1=ON_SWING_QUEUE_POPPED,
    -- 2=NORMAL_QUEUED, 3=NORMAL_QUEUE_POPPED,
    -- 4=NON_GCD_QUEUED, 5=NON_GCD_QUEUE_POPPED
    if eventCode == 0 or eventCode == 2 or eventCode == 4 then
      -- A spell was queued – store its ID
      rotationState.queued_attack_id = spellId
    elseif eventCode == 1 or eventCode == 3 or eventCode == 5 then
      -- A spell was popped from queue – clear the ID
      rotationState.queued_attack_id = nil
    end
  end
end)

-- ============================================================================
-- 7. Pre-rotation (shared between single-target and AoE)
-- ============================================================================
local function pre_rotation(use_sweeping_strikes)
  -- Auto Attack
  local _, _, _, _, _, _, autoattack = GetCurrentCastingInfo()
  if autoattack ~= 1 then
    CastSpellByName("Attack")
    return true
  end

  -- Charge & Intercept
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    if IsSpellInRange("Intercept", "target") == 1 then
      if is_on_cooldown(SPELL_ID_INTERCEPT) and GetUnitField("player", "power2", 1) >= 10 then
        CastSpellByName("Intercept")
        return true
      end
    end
    if IsSpellInRange("Charge", "target") == 1 then
      if not in_combat() and is_on_cooldown(SPELL_ID_CHARGE) then
        CastSpellByName("Charge")
        return true
      end
    end
  end

  -- Sweeping Strikes (AoE only, before stance check to avoid loop)
  if use_sweeping_strikes then
    if
      in_combat()
      and is_on_cooldown(SPELL_ID_SWEEPING_STRIKES)
      and UnitExists("target")
    then
      CastSpellByName("Sweeping Strikes")
      return true
    end
  end

  -- Berserker Stance
  local auras = GetUnitField("player", "aura", 1)
  local is_berserker = 0
  if auras then
    for i = 1, 32 do
      if auras[i] == STANCE_BERSERKER then
        is_berserker = 1
        break
      end
    end
  end
  if is_berserker == 0 then
    CastSpellByName("Berserker Stance")
    return true
  end

  -- Battle Shout
  if not has_buff(SPELL_ID_BATTLE_SHOUT) then
    CastSpellByName("Battle Shout")
    return true
  end

  return false
end

-- ============================================================================
-- 8. Single-target rotation runner
-- ============================================================================
local function run()
  if pre_rotation(false) then return end

  -- Reset rotation state if no target or out of combat
  if not UnitExists("target") or not in_combat() then
    rotationState.lastSlamCast = nil
  end

  -- Execute
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health", 1)
    local target_maxhp = GetUnitField("target", "maxHealth", 1)
    if
      target_hp
      and target_maxhp
      and (target_hp / target_maxhp * 100) <= 20
      and GetUnitField("player", "power2", 1) >= 15
    then
      CastSpellByName("Execute")
      return
    end
  end

  -- Sunder Armor
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    if IsSpellInRange("Sunder Armor", "target") == 1 then
      local sunder_stacks, sunder_timeleft = get_sunder_stacks()
      if sunder_stacks < 5 or sunder_timeleft < 5 then
        local resistances = GetUnitField("target", "resistances")
        local armor = resistances and resistances[1] or 0
        if armor > 0 and GetUnitField("player", "power2", 1) >= 10 then
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- Reactions
  if
    IsSpellUsable("Overpower") == 1
    and GetUnitField("player", "power2", 1) <= 25
    and is_on_cooldown(SPELL_ID_OVERPOWER)
  then
    CastSpellByName("Overpower")
    return
  end
  if
    IsSpellUsable("Revenge") == 1
    and GetUnitField("player", "power2", 1) <= 25
    and is_on_cooldown(SPELL_ID_REVENGE)
  then
    CastSpellByName("Revenge")
    return
  end

  -- Rotation (priority-based: MS > WW > Slam)
  local castId = GetCurrentCastingInfo()
  local isCastingSlam = castId == SPELL_ID_SLAM

  -- Mortal Strike (instant, highest priority)
  if
    not isCastingSlam
    and GetUnitField("player", "power2", 1) >= 30
    and is_on_cooldown(SPELL_ID_MORTALSTRIKE)
    and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
    and UnitExists("target")
    and IsSpellInRange("Mortal Strike", "target") == 1
  then
    CastSpellByName("Mortal Strike")
    return
  end

  -- Whirlwind (instant, second priority)
  if
    not isCastingSlam
    and GetUnitField("player", "power2", 1) >= 25
    and is_on_cooldown(SPELL_ID_WHIRLWIND)
    and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
    and UnitExists("target")
    and UnitXP("distanceBetween", "player", "target", "AoE") <= 8
  then
    CastSpellByName("Whirlwind")
    return
  end

  -- Slam (filler, gated on auto-attack to avoid delaying swings)
  local autoSinceSlam = rotationState.lastAutoTime
    and (not rotationState.lastSlamCast or rotationState.lastAutoTime > rotationState.lastSlamCast)
  if
    autoSinceSlam
    and GetUnitField("player", "power2", 1) >= 15
    and is_on_cooldown(SPELL_ID_SLAM)
    and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
    and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
    and UnitExists("target")
    and IsSpellInRange("Slam", "target") == 1
  then
    CastSpellByName("Slam")
    rotationState.lastSlamCast = GetTime()
    return
  end

  -- Heroic Strike (dump excess rage to avoid capping)
  if
    GetUnitField("player", "power2", 1) >= 80
    and rotationState.queued_attack_id ~= SPELL_ID_HEROIC_STRIKE
    and UnitExists("target")
    and IsSpellInRange("Heroic Strike", "target") == 1
  then
    CastSpellByName("Heroic Strike")
    return
  end
end

-- ============================================================================
-- 9. AoE rotation runner
-- ============================================================================
local function run_aoe()
  if pre_rotation(true) then return end

  -- Keep Cleave queued (on-swing, no GCD conflict)
  if
    GetUnitField("player", "power2", 1) >= 20
    and rotationState.queued_attack_id ~= SPELL_ID_CLEAVE
    and UnitExists("target")
  then
    CastSpellByName("Cleave")
    return
  end

  -- Whirlwind (top GCD priority)
  if
    GetUnitField("player", "power2", 1) >= 25
    and is_on_cooldown(SPELL_ID_WHIRLWIND)
    and UnitExists("target")
    and UnitXP("distanceBetween", "player", "target", "AoE") <= 8
  then
    CastSpellByName("Whirlwind")
    return
  end

  -- Sunder Armor (once per target, tab after this lands)
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    if IsSpellInRange("Sunder Armor", "target") == 1 then
      local sunder_stacks = get_sunder_stacks()
      if sunder_stacks < 1 then
        local resistances = GetUnitField("target", "resistances")
        local armor = resistances and resistances[1] or 0
        if armor > 0 and GetUnitField("player", "power2", 1) >= 10 then
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- Mortal Strike (fill GCDs)
  if
    GetUnitField("player", "power2", 1) >= 30
    and is_on_cooldown(SPELL_ID_MORTALSTRIKE)
    and UnitExists("target")
    and IsSpellInRange("Mortal Strike", "target") == 1
  then
    CastSpellByName("Mortal Strike")
    return
  end

  -- Execute (low priority, only as last GCD)
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health", 1)
    local target_maxhp = GetUnitField("target", "maxHealth", 1)
    if
      target_hp
      and target_maxhp
      and (target_hp / target_maxhp * 100) <= 20
      and GetUnitField("player", "power2", 1) >= 15
    then
      CastSpellByName("Execute")
      return
    end
  end
end

-- ============================================================================
-- 10. Slash command registration
-- ============================================================================
SlashCmdList["LAZYARMS_SLASH"] = run
SLASH_LAZYARMS_SLASH1 = "/lazyarms"

SlashCmdList["LAZYARMS_AOE_SLASH"] = run_aoe
SLASH_LAZYARMS_AOE_SLASH1 = "/lazyarmsaoe"
