-- Template config — regenerar con: python murlok_scraper.py <archivo_murlok> tankBuddy/Config.lua
-- Valores de referencia: murlok.io Blood DK M+ (21/04/2026)

tankBuddy_Config = {
    UpdatedAt      = "template",
    CharacterCount = 0,
    Spec           = "blood",
    Stats = {
        haste        = { median_rating =  628, median_bonus = 19.00, weight = 0.2359 },
        crit         = { median_rating =  607, median_bonus = 18.00, weight = 0.2280 },
        mastery      = { median_rating =  591, median_bonus = 42.00, weight = 0.2220 },
        versatility  = { median_rating =  447, median_bonus =  8.00, weight = 0.1679 },
        avoidance    = { median_rating =  100, median_bonus =  1.44, weight = 0.0376 },
        leech        = { median_rating =   50, median_bonus =  1.00, weight = 0.0188 },
        speed        = { median_rating =   30, median_bonus =  0.50, weight = 0.0113 },
    },
}
