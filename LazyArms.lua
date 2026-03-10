-- Lazy lookup: grab libdebuff at call time, not at load time
-- pfUI may not be fully loaded when this addon initializes
local function get_libdebuff()
  return pfUI and pfUI.api and pfUI.api.libdebuff
end

SetCVar("NP_EnableAutoAttackEvents", "1")

local SPELL_ID_CHARGE = 11578
local SPELL_ID_INTERCEPT = 20617
local SPELL_ID_INTERVENE = 45595
local SPELL_ID_OVERPOWER = 11585
local SPELL_ID_REVENGE = 11601
local SPELL_ID_SLAM = 45961
local SPELL_ID_MORTALSTRIKE = 27580
local SPELL_ID_WHIRLWIND = 1680
local SPELL_ID_BATTLE_SHOUT = 11551

local function get_sunder_stacks()
  local libdebuff = get_libdebuff()
  if not libdebuff then
    print("LazyArms: pfUI libdebuff not available")
    return 0
  end

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

local function in_combat()
  local flags = GetUnitField("player", "flags", 1)
  local UNIT_FLAG_IN_COMBAT = 524288
  return bit.band(flags, UNIT_FLAG_IN_COMBAT) ~= 0
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
    if spell_is_on_cooldown and spell_is_on_cooldown == 0 then
      return true
    else
      return false
    end
  end
end

-- Saved variable for persistence
local rotationState = rotationState
  or {
    stepIndex = 1,
    lastAction = nil,
    nextStepAfter = nil,
    waitingFor = nil,
    queued_attack_id = nil,
  }

-- Define the rotation as a state machine
local rotation = {
  -- Step 1: Slam
  {
    spell = "Slam",
    next = 2,
    condition = function()
      if
        GetUnitField("player", "power2", 1) >= 15
        and is_on_cooldown(SPELL_ID_SLAM)
        -- Check if a higher-priority spell is already queued (by ID)
        and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
        and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
        and UnitExists("target")
        and IsSpellInRange("Slam", "target") == 1
      then
        return true
      end
    end,
  },
  -- Step 2: Wait for Auto
  {
    waitFor = "auto",
    next = 3,
    condition = function()
      -- Check if auto attack just happened
      return GetTime() - (rotationState.lastAutoTime or 0) > 0.1
    end,
  },
  -- Step 3: Mortal Strike
  {
    spell = "Mortal Strike",
    next = 4,
    condition = function()
      if
        GetUnitField("player", "power2", 1) >= 30
        and is_on_cooldown(SPELL_ID_MORTALSTRIKE)
        and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
        and not IsCurrentAction(62)
        and UnitExists("target")
        and IsSpellInRange("Mortal Strike", "target") == 1
      then
        return true
      end
    end,
  },
  -- Step 4: Slam
  {
    spell = "Slam",
    next = 5,
    condition = function()
      if
        GetUnitField("player", "power2", 1) >= 15
        and is_on_cooldown(SPELL_ID_SLAM)
        and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
        and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
        and UnitExists("target")
        and IsSpellInRange("Slam", "target") == 1
      then
        return true
      end
    end,
  },
  -- Step 5: Wait for Auto
  {
    waitFor = "auto",
    next = 6,
    condition = function()
      return GetTime() - (rotationState.lastAutoTime or 0) > 0.1
    end,
  },
  -- Step 6: Whirlwind
  {
    spell = "Whirlwind",
    next = 7,
    condition = function()
      if
        GetUnitField("player", "power2", 1) >= 25
        and is_on_cooldown(SPELL_ID_WHIRLWIND)
        and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
        and not IsCurrentAction(62)
        and UnitExists("target")
        and IsSpellInRange("Whirlwind", "target") == 1
      then
        return true
      end
    end,
  },
  -- Step 7: Slam
  {
    spell = "Slam",
    next = 8,
    condition = function()
      if
        GetUnitField("player", "power2", 1) >= 15
        and is_on_cooldown(SPELL_ID_SLAM)
        and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
        and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
        and UnitExists("target")
        and IsSpellInRange("Slam", "target") == 1
      then
        return true
      end
    end,
  },
  -- Step 8: Wait for Auto
  {
    waitFor = "auto",
    next = 3, -- Loop back to Mortal Strike
    condition = function()
      return GetTime() - (rotationState.lastAutoTime or 0) > 0.1
    end,
  },
}

-- Track when auto attacks happen
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

local function run()
  -- ==========
  -- Auto Attack
  -- ==========
  local auto_attack = 1
  for i = 1, 172 do
    if IsCurrentAction(i) then
      auto_attack = 0
    end
  end
  if auto_attack == 1 then
    CastSpellByName("Attack")
    return
  end

  -- ==========
  -- Charge & Intercept
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    if IsSpellInRange("Charge", "target") == 1 then
      if not in_combat() and is_on_cooldown(SPELL_ID_CHARGE) then
        CastSpellByName("Charge")
        return
      end
    end
    if IsSpellInRange("Intercept", "target") == 1 then
      if is_on_cooldown(SPELL_ID_INTERCEPT) and GetUnitField("player", "power2", 1) >= 10 then
        CastSpellByName("Intercept")
        return
      end
    end
  end

  -- ==========
  -- Berserker Stance
  -- ==========
  local auras = GetUnitField("player", "aura", 1)
  local STANCE_BERSERKER = 2458
  local STANCE_DEFENSIVE = 71
  local STANCE_BATTLE = 2457
  local is_berserker = 0

  for i, spellId in ipairs(auras) do
    if spellId == STANCE_BERSERKER then
      is_berserker = 1
      break
    end
  end

  if not is_berserker then
    CastSpellByName("Berserker Stance")
    return
  end

  -- ==========
  -- Battle Shout
  -- ==========
  if not has_buff(SPELL_ID_BATTLE_SHOUT) then
    CastSpellByName("Battle Shout")
    return
  end

  -- ==========
  -- Execute
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health", 1)
    local target_maxhp = GetUnitField("target", "maxHealth", 1)
    if (target_hp / target_maxhp * 100) <= 20 and GetUnitField("player", "power2", 1) >= 15 then
      -- print("Executing!")
      CastSpellByName("Execute")
      return
    end
  end

  -- ==========
  -- Sunder Armor
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    if IsSpellInRange("Sunder Armor", "target") == 1 then
      local sunder_stacks, sunder_timeleft = get_sunder_stacks()
      if sunder_stacks < 5 or sunder_timeleft < 5 then
        -- Get target's current armor value
        local resistances = GetUnitField("target", "resistances")
        local armor = resistances and resistances[1] or 0
        if armor > 0 and GetUnitField("player", "power2", 1) >= 10 then
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- ==========
  -- Reactions
  -- ==========
  local overpower = IsSpellUsable("Overpower")
  if overpower == 1 and GetUnitField("player", "power2", 1) <= 25 and is_on_cooldown(SPELL_ID_OVERPOWER) then
    CastSpellByName("Overpower")
    return
  end

  local revenge = IsSpellUsable("Revenge")
  if revenge == 1 and GetUnitField("player", "power2", 1) <= 25 and is_on_cooldown(SPELL_ID_REVENGE) then
    CastSpellByName("Revenge")
    return
  end

  -- ==========
  -- Rest of the rotation
  -- ==========

  local currentStep = rotation[rotationState.stepIndex]
  if not currentStep then
    rotationState.stepIndex = 1
    return
  end

  -- Check if conditions are met
  if currentStep.condition() then
    -- Cast spell if this step has one
    if currentStep.spell then
      -- print("Casting: " .. currentStep.spell)
      CastSpellByName(currentStep.spell)
      rotationState.lastCast = currentStep.spell
    end

    -- Move to next step
    rotationState.stepIndex = currentStep.next
  end
end

SlashCmdList["LAZYARMS_SLASH"] = run
SLASH_LAZYARMS_SLASH1 = "/lazyarms"
