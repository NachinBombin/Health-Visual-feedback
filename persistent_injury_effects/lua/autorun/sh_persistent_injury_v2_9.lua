--[[-------------------------------------------------------------------------
    Persistent Injury Effects - Shared Config V2.9 (PERSISTENT SWAY)
    Compatible with V2.9 Client Script
    
    Changes from V2.7:
    - Added Persistent Sway ConVars (pfx_v2_psway_*)
    - Updated version strings
    - All previous ConVars unchanged (fully backward compatible)
---------------------------------------------------------------------------]]
print("[Persistent Injury V2.9 PERSISTENT SWAY] Shared script loading...")

-- =====================
-- Core ConVars
-- =====================
CreateConVar("pfx_v2_enable", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enable Persistent Injury Effects V2?", 0, 1)
CreateConVar("pfx_v2_intensity_preset", "3", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Intensity preset (1–5)", 1, 5)
CreateConVar("pfx_v2_frequency_mult", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Global frequency multiplier", 0.1, 10)
CreateConVar("pfx_v2_intensity_mult", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Global intensity multiplier", 0.1, 10)
CreateConVar("pfx_v2_muffle_max", "0.8", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Max muffle intensity", 0, 1)

-- =====================
-- Fatigue System ConVars
-- =====================
CreateConVar("pfx_v2_fatigue_check_interval", "8.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How often to check for fatigue tilt (seconds)", 1.0, 30.0)
CreateConVar("pfx_v2_fatigue_chance", "18.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Chance of fatigue tilt occurring per check (%)", 0, 100)
CreateConVar("pfx_v2_fatigue_duration", "3.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Duration of fatigue tilt effect (seconds)", 1.0, 10.0)
CreateConVar("pfx_v2_fatigue_max_angle", "8.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum angle for fatigue tilt (degrees)", 1.0, 30.0)
CreateConVar("pfx_v2_fatigue_cooldown", "5.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Cooldown after fatigue tilt (seconds)", 1.0, 30.0)
CreateConVar("pfx_v2_fatigue_crouch_mult", "1.8", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Fatigue angle multiplier during forced crouch", 1.0, 3.0)

-- =====================
-- Seizure System ConVars
-- =====================
CreateConVar("pfx_v2_seizure_enable", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enable seizure effect at very low HP?", 0, 1)
CreateConVar("pfx_v2_seizure_threshold", "10", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "HP percentage threshold for seizures", 1, 25)
CreateConVar("pfx_v2_seizure_max_duration", "8.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum duration of seizure effect (seconds)", 2.0, 60.0)
CreateConVar("pfx_v2_seizure_cooldown", "15.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Cooldown between seizures (seconds)", 5.0, 120.0)

-- =====================
-- Forced Crouch ConVars
-- =====================
CreateConVar("pfx_v2_forced_crouch_enable", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enable forced crouch effect?", 0, 1)
CreateConVar("pfx_v2_crouch_chance", "15.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Chance of forced crouch per check (%)", 0, 100)
CreateConVar("pfx_v2_crouch_check_interval", "12.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How often to check for forced crouch (seconds)", 1.0, 30.0)
CreateConVar("pfx_v2_crouch_duration_min", "2.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Minimum forced crouch duration (seconds)", 0.5, 10.0)
CreateConVar("pfx_v2_crouch_duration_max", "4.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum forced crouch duration (seconds)", 1.0, 20.0)
CreateConVar("pfx_v2_crouch_cooldown", "8.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Cooldown after forced crouch (seconds)", 3.0, 60.0)
CreateConVar("pfx_v2_crouch_min_severity", "3", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Minimum severity level for forced crouch (1-5)", 1, 5)

-- =====================
-- Persistent Sway ConVars (V2.9)
-- Always-on continuous sway that scales with HP severity (WoundedWalk-inspired)
-- =====================
CreateConVar("pfx_v2_psway_enable",              "1",   {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enable continuous HP-driven persistent sway layer?", 0, 1)
CreateConVar("pfx_v2_psway_threshold",           "75",  {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "HP % at which persistent sway begins (sway grows below this)", 10, 100)
CreateConVar("pfx_v2_psway_intensity",           "1.2", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Persistent sway amplitude multiplier", 0.1, 3.0)
CreateConVar("pfx_v2_psway_speed",               "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How fast the sway accelerates as HP drops", 0.1, 3.0)
CreateConVar("pfx_v2_psway_ignore_weapon_base",  "1",   {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Suppress sway for ARC9 / MW-base weapons?", 0, 1)

-- =====================
-- Preset Multipliers (MENU DEPENDS ON THIS)
-- =====================
PFX_IntensityPresetMults = {
    [1] = 0.4,
    [2] = 0.7,
    [3] = 1.0,
    [4] = 1.3,
    [5] = 1.7
}

-- =====================
-- Linked Micro Shake
-- =====================
PFX_LinkedShake = {
    amplitude = 0.35,
    frequency = 2.8,
    duration  = 0.6,
    intervalMin = 0.7,
    intervalMax = 1.3
}

-- =====================
-- Seizure Settings (Used by Client)
-- =====================
PFX_SEIZURE_SETTINGS = {
    shake_amp = 2.5,
    shake_freq = 15.0,
    blur_intensity = 0.35,
    muffle_intensity = 0.75,
    muffle_dsp = 18
}

-- =====================
-- Health → Severity
-- =====================
PERSISTENT_FX_THRESHOLDS_V2 = {
    { hp_percent = 80, severity = 1 },
    { hp_percent = 69, severity = 2 },
    { hp_percent = 45, severity = 3 },
    { hp_percent = 29, severity = 4 },
    { hp_percent = 19, severity = 5 }
}

-- =====================
-- Severity Settings
-- =====================
PERSISTENT_FX_SEVERITY_SETTINGS_V2 = {
    [1] = {
        check_interval = 4.5,
        surge_chance = 4,
        min_cooldown = 16,
        duration_min = 0.8,
        duration_max = 1.2,
        effects = {
            muffle = { chance=25, dsp=1, intensity=0.25 },
            shake  = { chance=10, amp=0.15, freq=2.0, dur=0.5 }
        },
        limp = { check_interval=2.8, chance=7, cooldown=7, duration_min=0.6, duration_max=1.0, angle=1.8 }
    },

    [2] = {
        check_interval = 4.0,
        surge_chance = 8,
        min_cooldown = 13,
        duration_min = 1.0,
        duration_max = 1.5,
        effects = {
            muffle = { chance=35, dsp=1, intensity=0.35 },
            blur   = { chance=20, intensity=0.07 },
            shake  = { chance=15, amp=0.20, freq=2.5, dur=0.6 }
        },
        limp = { check_interval=2.5, chance=11, cooldown=6, duration_min=0.7, duration_max=1.1, angle=2.5 }
    },

    [3] = {
        check_interval = 3.5,
        surge_chance = 15,
        min_cooldown = 11,
        duration_min = 1.2,
        duration_max = 1.8,
        effects = {
            muffle = { chance=45, dsp=16, intensity=0.45 },
            blur   = { chance=35, intensity=0.10 },
            shake  = { chance=20, amp=0.25, freq=3.0, dur=0.7 }
        },
        limp = { check_interval=2.1, chance=18, cooldown=5, duration_min=0.7, duration_max=1.2, angle=4.2 }
    },

    [4] = {
        check_interval = 3.0,
        surge_chance = 25,
        min_cooldown = 9,
        duration_min = 1.5,
        duration_max = 2.2,
        effects = {
            muffle = { chance=55, dsp=16, intensity=0.55 },
            blur   = { chance=50, intensity=0.15 },
            shake  = { chance=30, amp=0.35, freq=3.5, dur=0.8 }
        },
        limp = { check_interval=1.8, chance=26, cooldown=4, duration_min=0.8, duration_max=1.3, angle=5.0 }
    },

    [5] = {
        check_interval = 2.5,
        surge_chance = 40,
        min_cooldown = 7,
        duration_min = 1.8,
        duration_max = 2.5,
        effects = {
            muffle = { chance=70, dsp=18, intensity=0.65 },
            blur   = { chance=65, intensity=0.20 },
            shake  = { chance=50, amp=0.45, freq=3.8, dur=0.9 }
        },
        limp = { check_interval=1.5, chance=35, cooldown=3.5, duration_min=0.9, duration_max=1.4, angle=5.5 }
    }
}

-- =====================
-- BACKWARD COMPATIBILITY
-- =====================
PERSISTENT_FX_THRESHOLDS        = PERSISTENT_FX_THRESHOLDS_V2
PERSISTENT_FX_SEVERITY_SETTINGS = PERSISTENT_FX_SEVERITY_SETTINGS_V2

print("[Persistent Injury V2.9 PERSISTENT SWAY] Shared script loaded successfully.")
print("[Persistent Injury V2.9] All ConVars registered and configuration tables initialized.")
