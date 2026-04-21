local ADDON, TB = "tankBuddy", {}
_G[ADDON] = TB

-- GetItemStats keys para cada stat
local STAT_MAP = {
    haste       = "ITEM_MOD_HASTE_RATING_SHORT",
    crit        = "ITEM_MOD_CRIT_RATING_SHORT",
    mastery     = "ITEM_MOD_MASTERY_RATING_SHORT",
    versatility = "ITEM_MOD_VERSATILITY_SHORT",
    leech       = "ITEM_MOD_LEECH_SHORT",
    avoidance   = "ITEM_MOD_AVOIDANCE_SHORT",
    speed       = "ITEM_MOD_SPEED_SHORT",
}

local STAT_REVERSE = {}
for k, v in pairs(STAT_MAP) do STAT_REVERSE[v] = k end

TB.EQUIP_SLOTS = {
    { id = 1,  name = "Head"     },
    { id = 2,  name = "Neck"     },
    { id = 3,  name = "Shoulder" },
    { id = 15, name = "Back"     },
    { id = 5,  name = "Chest"    },
    { id = 9,  name = "Wrist"    },
    { id = 10, name = "Hands"    },
    { id = 6,  name = "Waist"    },
    { id = 7,  name = "Legs"     },
    { id = 8,  name = "Feet"     },
    { id = 11, name = "Ring1"    },
    { id = 12, name = "Ring2"    },
    { id = 13, name = "Trinket1" },
    { id = 14, name = "Trinket2" },
    { id = 16, name = "MainHand" },
    { id = 17, name = "OffHand"  },
}

-- invTypes que ocupan dos slots: se compara contra el peor equipado
local DUAL_SLOT_TYPES = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }


function TB.ScoreItem(itemLink)
    if not itemLink then return 0 end
    local cfg = tankBuddy_Config
    if not cfg then return 0 end

    local itemStats = {}
    GetItemStats(itemLink, itemStats)

    local score = 0
    for statKey, amount in pairs(itemStats) do
        local cfgKey = STAT_REVERSE[statKey]
        if cfgKey then
            local statCfg = cfg.Stats[cfgKey]
            if statCfg and statCfg.weight and amount > 0 then
                score = score + amount * statCfg.weight
            end
        end
    end
    return score
end

function TB.GetEquippedItem(slotId)
    local link = GetInventoryItemLink("player", slotId)
    return link, TB.ScoreItem(link)
end

function TB.ScanBags()
    local items = {}
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local score = TB.ScoreItem(link)
                if score > 0 then
                    local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(link)
                    if invType and invType ~= "" and invType ~= "INVTYPE_NON_EQUIP" and invType ~= "INVTYPE_BAG" then
                        table.insert(items, {
                            link    = link,
                            score   = score,
                            ilvl    = ilvl or 0,
                            invType = invType,
                        })
                    end
                end
            end
        end
    end
    return items
end

function TB.FindUpgrades()
    -- Para cada invType, guardamos el peor slot equipado (el que más fácil se mejora)
    local equippedByType = {}
    for _, s in ipairs(TB.EQUIP_SLOTS) do
        local link, score = TB.GetEquippedItem(s.id)
        if link then
            local _, _, _, _, _, _, _, _, invType = GetItemInfo(link)
            if invType then
                local existing = equippedByType[invType]
                if not existing then
                    equippedByType[invType] = { link = link, score = score, slotName = s.name }
                elseif DUAL_SLOT_TYPES[invType] and score < existing.score then
                    equippedByType[invType] = { link = link, score = score, slotName = s.name }
                end
            end
        end
    end

    local upgrades = {}
    for _, item in ipairs(TB.ScanBags()) do
        local equipped = equippedByType[item.invType]
        if equipped then
            local diff = item.score - equipped.score
            if diff > 0.5 then
                table.insert(upgrades, {
                    link          = item.link,
                    score         = item.score,
                    ilvl          = item.ilvl,
                    diff          = diff,
                    invType       = item.invType,
                    equippedLink  = equipped.link,
                    equippedScore = equipped.score,
                    slotName      = equipped.slotName,
                })
            end
        end
    end

    table.sort(upgrades, function(a, b) return a.diff > b.diff end)
    return upgrades
end

function TB.PrintUpgrades()
    local cfg = tankBuddy_Config
    if not cfg then
        print("|cffff4444[tankBuddy]|r No config. Ejecuta murlok_scraper.py primero.")
        return
    end
    local upgrades = TB.FindUpgrades()
    if #upgrades == 0 then
        print("|cff4fc3f7[tankBuddy]|r |cff00ff00No hay upgrades en tus bolsas.|r")
        return
    end
    print(string.format("|cff4fc3f7[tankBuddy]|r |cffffff00%d upgrade(s) encontrado(s):|r", #upgrades))
    for i, u in ipairs(upgrades) do
        print(string.format(
            "  %d. %s |cff888888ilvl %d|r  |cff00ff00+%.1f|r  vs %s",
            i, u.link, u.ilvl, u.diff, u.equippedLink
        ))
    end
end

function TB.PrintEquipped()
    local cfg = tankBuddy_Config
    if not cfg then
        print("|cffff4444[tankBuddy]|r No config. Ejecuta murlok_scraper.py primero.")
        return
    end
    print(string.format(
        "|cff4fc3f7[tankBuddy]|r %s | %d chars | %s",
        cfg.UpdatedAt, cfg.CharacterCount, cfg.Spec
    ))
    for _, s in ipairs(TB.EQUIP_SLOTS) do
        local link, score = TB.GetEquippedItem(s.id)
        if link and score > 0 then
            print(string.format("  |cffaaaaaa%-10s|r %s  |cff888888(%.1f)|r", s.name, link, score))
        end
    end
end
