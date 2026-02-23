lazy_arms = CreateFrame("frame", nil, UIParent)

function lazy_arms:run()
  if UnitMana("player") > 10 then
    CastSpellByName("Sunder Armor")
  end
end

SlashCmdList["LAZYARMS_SLASH"] = lazy_arms.run
SLASH_LAZYARMS_SLASH1 = "/lazyarms"
