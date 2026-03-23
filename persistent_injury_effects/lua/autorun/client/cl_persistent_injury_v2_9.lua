--[[-------------------------------------------------------------------------
    Persistent Injury Effects - Client Logic & Effects V2.9 (PERSISTENT SWAY)

    NEW in V2.9 - WoundedWalk-Inspired Persistent Sway Layer:
    - Continuous, always-on sway that scales with current HP severity
    - Three-axis Lissajous-figure motion (pitch/yaw/roll at offset frequencies)
    - Time variable accelerates as HP drops (faster wobble when critical)
    - Organic noise rides on top of the base sway for non-repetition
    - Sway amplitude tapers when episodic effects fire (no double-dipping)
    - Fully configurable: enable/disable, threshold, intensity, speed
    - Weapon base detection (suppresses sway for ARC9 / MW-base weapons)

    From V2.8 - Natural Camera Motion System:
    - Perlin noise-based organic movement instead of sine waves
    - Spring physics for smooth, natural transitions
    - Asymmetric recovery paths (no direct reversal)
    - Randomised motion patterns per effect instance
    - Breathing-like oscillations during sustained effects

    From V2.7 - Performance Optimisations:
    - ConVar caching (updated every 0.5s instead of every frame)
    - Optimised fade calculation with reusable function
    - Pixelvis dirty tracking to avoid redundant render calls
    - Early-exit thresholds on negligible effects
---------------------------------------------------------------------------]]
print("[Persistent Injury V2.9] Client script loading...")

-- ===========================================================================
-- State globals
-- ===========================================================================
local playerStates = {}

local currentSurgeTilt, currentLimpTilt, currentFatigueTilt = 0, 0, 0
local currentBlur,      currentMuffle,   currentCrouchBlur  = 0, 0, 0
local currentShakeTime, currentDSP,      currentLookDownPitch = 0, 0, 0
local nextLinkedShakeTime, linkedShakeParentEndTime          = 0, 0

local springVelocity = { surge = 0, limp = 0, fatigue = 0, lookDown = 0 }

local persistentSwayFactor     = 0
local persistentSwayTimeOffset = 0

local EFFECT_THRESHOLD = 0.001

-- ===========================================================================
-- ConVar Cache
-- ===========================================================================
local cachedConVars          = {}
local nextConVarUpdate       = 0
local CONVAR_UPDATE_INTERVAL = 0.5

local function UpdateConVarCache()
    cachedConVars.enable             = GetConVar("pfx_v2_enable"):GetBool()
    cachedConVars.intensityPreset    = GetConVar("pfx_v2_intensity_preset"):GetInt()
    cachedConVars.intensityMult      = GetConVar("pfx_v2_intensity_mult"):GetFloat()
    cachedConVars.frequencyMult      = GetConVar("pfx_v2_frequency_mult"):GetFloat()
    cachedConVars.muffleMax          = GetConVar("pfx_v2_muffle_max"):GetFloat()
    cachedConVars.seizureThreshold   = GetConVar("pfx_v2_seizure_threshold"):GetInt()
    cachedConVars.seizureEnable      = GetConVar("pfx_v2_seizure_enable"):GetBool()
    cachedConVars.seizureMaxDuration = GetConVar("pfx_v2_seizure_max_duration"):GetFloat()
    cachedConVars.seizureCooldown    = GetConVar("pfx_v2_seizure_cooldown"):GetFloat()
    cachedConVars.fatigueCheckInterval = GetConVar("pfx_v2_fatigue_check_interval"):GetFloat()
    cachedConVars.fatigueChance        = GetConVar("pfx_v2_fatigue_chance"):GetFloat()
    cachedConVars.fatigueDuration      = GetConVar("pfx_v2_fatigue_duration"):GetFloat()
    cachedConVars.fatigueMaxAngle      = GetConVar("pfx_v2_fatigue_max_angle"):GetFloat()
    cachedConVars.fatigueCooldown      = GetConVar("pfx_v2_fatigue_cooldown"):GetFloat()
    cachedConVars.forcedCrouchEnable   = GetConVar("pfx_v2_forced_crouch_enable"):GetBool()
    cachedConVars.crouchMinSeverity    = GetConVar("pfx_v2_crouch_min_severity"):GetInt()
    cachedConVars.crouchCheckInterval  = GetConVar("pfx_v2_crouch_check_interval"):GetFloat()
    cachedConVars.crouchChance         = GetConVar("pfx_v2_crouch_chance"):GetFloat()
    cachedConVars.crouchDurationMin    = GetConVar("pfx_v2_crouch_duration_min"):GetFloat()
    cachedConVars.crouchDurationMax    = GetConVar("pfx_v2_crouch_duration_max"):GetFloat()
    cachedConVars.crouchCooldown       = GetConVar("pfx_v2_crouch_cooldown"):GetFloat()
    cachedConVars.fatigueCrouchMult    = GetConVar("pfx_v2_fatigue_crouch_mult"):GetFloat()
    cachedConVars.pswayEnable           = GetConVar("pfx_v2_psway_enable"):GetBool()
    cachedConVars.pswayThreshold        = GetConVar("pfx_v2_psway_threshold"):GetInt()
    cachedConVars.pswayIntensity        = GetConVar("pfx_v2_psway_intensity"):GetFloat()
    cachedConVars.pswaySpeed            = GetConVar("pfx_v2_psway_speed"):GetFloat()
    cachedConVars.pswayIgnoreWeaponBase = GetConVar("pfx_v2_psway_ignore_weapon_base"):GetBool()

    local presetMult = (PFX_IntensityPresetMults and
                        PFX_IntensityPresetMults[cachedConVars.intensityPreset]) or 1.0
    cachedConVars.finalIntensityMult = presetMult * cachedConVars.intensityMult
end

UpdateConVarCache()

local function GetIntensityMultiplier() return cachedConVars.finalIntensityMult end
local function GetFrequencyMultiplier() return cachedConVars.frequencyMult end
local function GetMaxMuffleIntensity()  return cachedConVars.muffleMax end

-- ===========================================================================
-- Pixelvis (dirty-flag)
-- ===========================================================================
local ActivePixelvisHooks = {}
local pixelvisNeedsUpdate = false

local function ApplyPixelvisHooks()
    local combinedData, count = nil, 0
    for _, data in pairs(ActivePixelvisHooks) do
        if data and data.enabled then
            if not combinedData then combinedData = {} end
            for k, v in pairs(data) do combinedData[k] = v end
            count = count + 1
        end
    end
    if combinedData and count > 0 then
        render.SetPixelvis(combinedData)
    else
        render.RemovePixelvis()
    end
    pixelvisNeedsUpdate = false
end

function AddPixelvisHook(name, data)
    if not name or not data then return end
    local existing    = ActivePixelvisHooks[name]
    local needsUpdate = not existing
    if existing then
        for k, v in pairs(data) do
            if existing[k] ~= v then needsUpdate = true; break end
        end
    end
    if needsUpdate then
        ActivePixelvisHooks[name] = data
        pixelvisNeedsUpdate       = true
    end
end

function RemovePixelvisHook(name)
    if not name or not ActivePixelvisHooks[name] then return end
    ActivePixelvisHooks[name] = nil
    pixelvisNeedsUpdate       = true
end

-- ===========================================================================
-- Natural Motion Helpers
-- ===========================================================================

local function ApplySpringPhysics(current, target, velocity, dt, stiffness, damping)
    stiffness = stiffness or 0.12
    damping   = damping   or 0.85
    velocity  = velocity * damping + (target - current) * stiffness
    return current + velocity * dt * 60, velocity
end

local function GetOrganicNoise(time, seed, octaves)
    octaves = octaves or 2
    local value, amplitude, frequency = 0, 1.0, 1.0
    for i = 1, octaves do
        value     = value + math.noise(time * frequency + seed * 100, seed * 50 + i) * amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2.0
    end
    return value
end

local function GetBreathingPattern(time, seed, intensity)
    local breathRate  = 0.3 + (seed % 7)  * 0.05
    local breathDepth = 0.4 + (seed % 11) * 0.03
    local primary   = math.sin(time * breathRate       + seed)       * breathDepth
    local secondary = math.sin(time * breathRate * 2.3 + seed * 1.5) * breathDepth * 0.3
    local noise     = GetOrganicNoise(time * 0.5, seed, 2) * 0.15
    return (primary + secondary + noise) * intensity
end

-- ===========================================================================
-- Severity
-- ===========================================================================
local function GetSeverityLevelV2(ply)
    if not IsValid(ply) or not ply:Alive() then return 0 end
    if not PERSISTENT_FX_THRESHOLDS_V2 then
        print("ERR: PERSISTENT_FX_THRESHOLDS_V2 missing")
        return 0
    end
    local hpPct = (ply:Health() / ply:GetMaxHealth()) * 100
    for i = #PERSISTENT_FX_THRESHOLDS_V2, 1, -1 do
        if hpPct <= PERSISTENT_FX_THRESHOLDS_V2[i].hp_percent then
            return PERSISTENT_FX_THRESHOLDS_V2[i].severity
        end
    end
    return 0
end

-- ===========================================================================
-- Fade (smoothstep, asymmetric recovery)
-- ===========================================================================
local function CalculateFade(isActive, params, endTime, curTime, fadeInRatio, fadeOutRatio)
    if not isActive or not params or not params.duration or params.duration <= 0 then
        return 0
    end
    local elapsed = curTime - params.startTime
    local fadeIn  = params.duration * fadeInRatio
    local fadeOut = params.duration * fadeOutRatio
    local sustain = params.duration - fadeIn - fadeOut
    if elapsed < fadeIn then
        local t = elapsed / fadeIn
        return t * t * (3 - 2 * t)
    elseif elapsed < fadeIn + sustain then
        return 1
    else
        local t   = math.Clamp((endTime - curTime) / fadeOut, 0, 1)
        local var = GetOrganicNoise(curTime * 2, params.startTime, 1) * 0.08
        return math.Clamp(t * t * (3 - 2 * t) + var, 0, 1)
    end
end

-- ===========================================================================
-- Linked Shake
-- ===========================================================================
local function TriggerLinkedMiniShakeActual(ply)
    if not PFX_LinkedShake or not PFX_LinkedShake.amplitude then return end
    local im       = GetIntensityMultiplier()
    local severity = GetSeverityLevelV2(ply) or 1
    local amplitude = PFX_LinkedShake.amplitude * im * (1 + severity * 0.10)
    local frequency = PFX_LinkedShake.frequency * (1 + severity * 0.05)
    local duration  = (type(PFX_LinkedShake.duration) == "number" and PFX_LinkedShake.duration > 0)
                      and PFX_LinkedShake.duration or 0.6
    util.ScreenShake(ply:GetPos(), amplitude, frequency, duration, 1000)
end

local function StartPeriodicLinkedShake(parentEndTime)
    if not PFX_LinkedShake then return end
    nextLinkedShakeTime      = CurTime()
    linkedShakeParentEndTime = parentEndTime
end

-- ===========================================================================
-- Reset
-- ===========================================================================
local function ResetAllEffects(state)
    currentSurgeTilt, currentLimpTilt, currentFatigueTilt = 0, 0, 0
    currentBlur, currentMuffle, currentCrouchBlur          = 0, 0, 0
    currentShakeTime, currentDSP, currentLookDownPitch     = 0, 0, 0
    springVelocity     = { surge = 0, limp = 0, fatigue = 0, lookDown = 0 }
    persistentSwayFactor = 0
    render.SetDSP(0)
    RemovePixelvisHook("PersistentFX_Blur")
    RemovePixelvisHook("PersistentFX_CrouchFX")
    if state then
        state.activeEffects       = {}
        state.activeLimpParams    = {}
        state.activeFatigueParams = {}
        state.inSeizure           = false
    end
    nextLinkedShakeTime      = 0
    linkedShakeParentEndTime = 0
end

-- ===========================================================================
-- Think Hook
-- ===========================================================================
hook.Add("Think", "PersistentInjuryV2_ClientThink", function()
    local ply       = LocalPlayer()
    local curTime   = CurTime()
    local frameTime = FrameTime()

    if curTime >= nextConVarUpdate then
        UpdateConVarCache()
        nextConVarUpdate = curTime + CONVAR_UPDATE_INTERVAL
    end

    if not cachedConVars.enable or not IsValid(ply) then
        if playerStates[ply] and playerStates[ply].isActive then
            ResetAllEffects(playerStates[ply])
            playerStates[ply].isActive = false
        end
        return
    end

    if not playerStates[ply] then
        playerStates[ply] = { isActive = false }
    end
    local state = playerStates[ply]

    if not state.isActive then
        state.isActive              = true
        state.currentSeverity       = 0
        state.nextSurgeCheck        = 0
        state.surgeEndTime          = 0
        state.nextSurgePossibleTime = 0
        state.activeEffects         = {}
        state.nextLimpCheck         = 0
        state.limpEndTime           = 0
        state.activeLimpParams      = {}
        state.nextFatigueCheck      = 0
        state.fatigueEndTime        = 0
        state.activeFatigueParams   = {}
        state.nextCrouchCheck       = 0
        state.forcedCrouchEndTime   = 0
        state.inSeizure             = false
        state.seizureEndTime        = 0
        state.nextSeizurePossibleTime = 0
        ResetAllEffects(state)
        persistentSwayTimeOffset = math.Rand(0, 100)
    end

    if not ply:Alive() or ply:Health() >= 100 then
        if state.currentSeverity > 0 or state.inSeizure then
            ResetAllEffects(state)
        end
        state.currentSeverity         = 0
        state.nextSurgeCheck          = curTime + 3
        state.nextLimpCheck           = curTime + 3
        state.nextFatigueCheck        = curTime + 3
        state.nextCrouchCheck         = curTime + 3
        state.surgeEndTime            = 0
        state.nextEffectPossibleTime  = 0
        state.limpEndTime             = 0
        state.fatigueEndTime          = 0
        state.forcedCrouchEndTime     = 0
        state.seizureEndTime          = 0
        state.nextSeizurePossibleTime = 0
        return
    end

    local newSeverity = GetSeverityLevelV2(ply)
    if newSeverity ~= state.currentSeverity then
        state.currentSeverity         = newSeverity
        state.nextSurgeCheck          = curTime
        state.nextLimpCheck           = curTime
        state.nextFatigueCheck        = curTime
        state.nextCrouchCheck         = curTime
        state.nextSeizurePossibleTime = curTime
    end

    -- Persistent sway factor
    if cachedConVars.pswayEnable then
        local hpPct        = (ply:Health() / ply:GetMaxHealth()) * 100
        local swayThreshold = cachedConVars.pswayThreshold
        local targetFactor  = 0
        if hpPct < swayThreshold then
            targetFactor = math.Clamp((swayThreshold - hpPct) / swayThreshold, 0, 1)
        end
        persistentSwayFactor = math.Approach(persistentSwayFactor, targetFactor, frameTime * 0.4)
    else
        persistentSwayFactor = 0
    end

    -- Seizure
    local hpPercent = (ply:Health() / ply:GetMaxHealth()) * 100

    if cachedConVars.seizureEnable and not state.inSeizure and
       hpPercent <= cachedConVars.seizureThreshold and
       curTime >= state.nextSeizurePossibleTime then
        state.inSeizure               = true
        state.seizureEndTime          = curTime + cachedConVars.seizureMaxDuration
        state.nextSeizurePossibleTime = state.seizureEndTime + cachedConVars.seizureCooldown
        state.surgeEndTime            = curTime
        state.limpEndTime             = curTime
        state.fatigueEndTime          = curTime
        state.forcedCrouchEndTime     = curTime
        ResetAllEffects(state)
    elseif state.inSeizure and curTime >= state.seizureEndTime then
        state.inSeizure      = false
        state.seizureEndTime = 0
        ResetAllEffects(state)
        state.nextSurgeCheck         = curTime
        state.nextLimpCheck          = curTime
        state.nextFatigueCheck       = curTime
        state.nextCrouchCheck        = curTime
        state.nextEffectPossibleTime = curTime
    end

    if state.inSeizure then
        if PFX_SEIZURE_SETTINGS then
            local im = GetIntensityMultiplier()
            util.ScreenShake(ply:GetPos(),
                PFX_SEIZURE_SETTINGS.shake_amp * im,
                PFX_SEIZURE_SETTINGS.shake_freq, 0.5, 1000)
            currentLimpTilt, currentSurgeTilt, currentFatigueTilt = 0, 0, 0
            currentLookDownPitch = 0
            currentBlur   = math.Approach(currentBlur,   PFX_SEIZURE_SETTINGS.blur_intensity   * im, frameTime * 2)
            currentMuffle = math.Approach(currentMuffle, PFX_SEIZURE_SETTINGS.muffle_intensity * im, frameTime * 2)
            currentDSP    = PFX_SEIZURE_SETTINGS.muffle_dsp
            currentCrouchBlur = 0
        else
            print("[Persistent Injury] Warning: PFX_SEIZURE_SETTINGS missing!")
        end
    else
        local im       = GetIntensityMultiplier()
        local freqMult = GetFrequencyMultiplier()

        local canTrigger = state.currentSeverity > 0 and
                           curTime >= state.limpEndTime and
                           curTime >= state.fatigueEndTime and
                           curTime >= state.forcedCrouchEndTime

        -- Surge
        if canTrigger and curTime >= state.nextSurgeCheck and
           curTime >= state.nextSurgePossibleTime then
            local settings = PERSISTENT_FX_SEVERITY_SETTINGS_V2[state.currentSeverity]
            if settings then
                state.nextSurgeCheck = curTime + (settings.check_interval / freqMult) * math.Rand(0.9, 1.1)
                if math.Rand(0, 100) <= settings.surge_chance * freqMult then
                    state.surgeEndTime          = curTime + math.Rand(settings.duration_min, settings.duration_max)
                    state.nextSurgePossibleTime = state.surgeEndTime + settings.min_cooldown
                    local effectDur             = state.surgeEndTime - curTime
                    state.activeEffects         = {}
                    for effectType, params in pairs(settings.effects) do
                        if math.Rand(0, 100) <= params.chance then
                            local ef = table.Copy(params)
                            ef.startTime = curTime
                            ef.duration  = effectDur
                            if effectType == "tilt" then
                                ef.direction = (math.random(1, 2) == 1) and 1 or -1
                                ef.seed      = math.random(1, 10000)
                            end
                            if effectType == "shake" then
                                currentShakeTime = curTime + math.min(params.dur, effectDur)
                            end
                            state.activeEffects[effectType] = ef
                        end
                    end
                end
            else
                state.nextSurgeCheck = curTime + 3.0
            end
        end

        -- Limp
        if state.currentSeverity > 0 and curTime >= state.nextLimpCheck and
           curTime >= state.surgeEndTime and curTime >= state.fatigueEndTime and
           curTime >= state.forcedCrouchEndTime then
            local settings = PERSISTENT_FX_SEVERITY_SETTINGS_V2[state.currentSeverity]
            if settings and settings.limp then
                state.nextLimpCheck = curTime + (settings.limp.check_interval / freqMult) * math.Rand(0.8, 1.2)
                if math.Rand(0, 100) <= settings.limp.chance * freqMult then
                    state.limpEndTime      = curTime + math.Rand(settings.limp.duration_min, settings.limp.duration_max)
                    state.activeLimpParams = {
                        startTime = curTime,
                        duration  = state.limpEndTime - curTime,
                        max_angle = settings.limp.angle,
                        direction = (math.random(1, 2) == 1) and 1 or -1,
                        seed      = math.random(1, 10000),
                    }
                    state.nextLimpCheck = state.limpEndTime + settings.limp.cooldown
                    StartPeriodicLinkedShake(state.limpEndTime)
                end
            else
                state.nextLimpCheck = curTime + 3.0
            end
        end

        -- Fatigue
        if curTime >= state.nextFatigueCheck and curTime >= state.surgeEndTime and
           curTime >= state.limpEndTime and curTime >= state.forcedCrouchEndTime then
            state.nextFatigueCheck = curTime + (cachedConVars.fatigueCheckInterval / freqMult) * math.Rand(0.9, 1.1)
            if math.Rand(0, 100) <= cachedConVars.fatigueChance * freqMult then
                state.fatigueEndTime      = curTime + cachedConVars.fatigueDuration
                state.activeFatigueParams = {
                    startTime = curTime,
                    duration  = cachedConVars.fatigueDuration,
                    max_angle = cachedConVars.fatigueMaxAngle,
                    seed      = math.random(1, 10000),
                }
                state.nextFatigueCheck = state.fatigueEndTime + cachedConVars.fatigueCooldown
                StartPeriodicLinkedShake(state.fatigueEndTime)
            end
        end

        -- Forced Crouch
        if cachedConVars.forcedCrouchEnable and
           state.currentSeverity >= cachedConVars.crouchMinSeverity and
           curTime >= state.nextCrouchCheck and curTime >= state.surgeEndTime and
           curTime >= state.limpEndTime and curTime >= state.fatigueEndTime then
            state.nextCrouchCheck = curTime + (cachedConVars.crouchCheckInterval / freqMult) * math.Rand(0.8, 1.2)
            if math.Rand(0, 100) <= cachedConVars.crouchChance * freqMult then
                local duration            = math.Rand(cachedConVars.crouchDurationMin, cachedConVars.crouchDurationMax)
                state.forcedCrouchEndTime = curTime + duration
                state.nextCrouchCheck     = state.forcedCrouchEndTime + cachedConVars.crouchCooldown
                StartPeriodicLinkedShake(state.forcedCrouchEndTime)
                state.fatigueEndTime      = state.forcedCrouchEndTime
                state.activeFatigueParams = {
                    startTime = curTime,
                    duration  = duration,
                    max_angle = cachedConVars.fatigueMaxAngle * cachedConVars.fatigueCrouchMult,
                    seed      = math.random(1, 10000),
                }
            end
        end

        local activeSurge   = state.surgeEndTime        > curTime
        local activeLimp    = state.limpEndTime         > curTime
        local activeFatigue = state.fatigueEndTime      > curTime
        local activeCrouch  = state.forcedCrouchEndTime > curTime

        local surgeFade, limpFade, fatigueFade, crouchFade = 0, 0, 0, 0

        if activeSurge and state.activeEffects and next(state.activeEffects) then
            local fe = state.activeEffects[next(state.activeEffects)]
            surgeFade = CalculateFade(true, fe, state.surgeEndTime, curTime, 0.3, 0.4)
        else
            state.activeEffects = {}
        end

        if activeLimp then
            limpFade = CalculateFade(true, state.activeLimpParams, state.limpEndTime, curTime, 0.4, 0.6)
        else
            state.activeLimpParams = {}
        end

        if activeFatigue then
            fatigueFade = CalculateFade(true, state.activeFatigueParams, state.fatigueEndTime, curTime, 0.5, 0.5)
        else
            state.activeFatigueParams = {}
        end

        if activeCrouch then
            local cs = (state.activeFatigueParams and state.activeFatigueParams.startTime) or curTime
            crouchFade = CalculateFade(true,
                { startTime = cs, duration = state.forcedCrouchEndTime - cs },
                state.forcedCrouchEndTime, curTime, 0.3, 0.3)
        end

        local ae         = state.activeEffects
        local tiltFx     = ae and ae.tilt
        local blurFx     = ae and ae.blur
        local muffleFx   = ae and ae.muffle
        local shakeFx    = ae and ae.shake
        local lookDownFx = ae and ae.lookDown
        local lp         = state.activeLimpParams
        local fp         = state.activeFatigueParams

        -- Surge tilt
        local tgtSurgeRaw   = (tiltFx and tiltFx.angle) or 0
        local tgtSurgeFinal = tgtSurgeRaw * im * surgeFade
        currentSurgeTilt, springVelocity.surge =
            ApplySpringPhysics(currentSurgeTilt, tgtSurgeFinal, springVelocity.surge, frameTime, 0.14, 0.82)

        -- Blur
        local tgtBlur = (blurFx and blurFx.intensity * im) or 0
        currentBlur   = math.Approach(currentBlur, tgtBlur * surgeFade, frameTime * (tgtBlur + 0.1) * 5)

        -- Muffle
        local tgtMuffle = (muffleFx and muffleFx.intensity * im) or 0
        currentMuffle   = math.Approach(currentMuffle, tgtMuffle * surgeFade, frameTime * (tgtMuffle + 0.1) * 4)
        currentDSP      = (muffleFx and muffleFx.dsp) or 0

        -- Shake
        if currentShakeTime > curTime and shakeFx then
            util.ScreenShake(ply:GetPos(), shakeFx.amp * im, shakeFx.freq, shakeFx.dur, 1500)
        end
        if currentShakeTime > 0 and curTime >= currentShakeTime then currentShakeTime = 0 end

        -- Limp tilt
        local tgtLimpRaw   = (lp and lp.max_angle) or 0
        local tgtLimpFinal = tgtLimpRaw * im * limpFade
        currentLimpTilt, springVelocity.limp =
            ApplySpringPhysics(currentLimpTilt, tgtLimpFinal, springVelocity.limp, frameTime, 0.10, 0.88)

        -- Fatigue tilt
        local tgtFatigueRaw   = (fp and fp.max_angle) or 0
        local tgtFatigueFinal = tgtFatigueRaw * im * fatigueFade
        currentFatigueTilt, springVelocity.fatigue =
            ApplySpringPhysics(currentFatigueTilt, tgtFatigueFinal, springVelocity.fatigue, frameTime, 0.08, 0.90)

        -- Crouch blur
        local tgtCrouchBlur = activeCrouch and (0.15 * im) or 0
        currentCrouchBlur   = math.Approach(currentCrouchBlur, tgtCrouchBlur * crouchFade, frameTime * (tgtCrouchBlur + 0.1) * 4)

        -- Look-down pitch
        local tgtLookRaw   = (lookDownFx and lookDownFx.angle) or 0
        local tgtLookFinal = tgtLookRaw * im * surgeFade
        currentLookDownPitch, springVelocity.lookDown =
            ApplySpringPhysics(currentLookDownPitch, tgtLookFinal, springVelocity.lookDown, frameTime, 0.12, 0.85)
    end

    -- Periodic linked shake
    if curTime >= nextLinkedShakeTime and linkedShakeParentEndTime > curTime then
        TriggerLinkedMiniShakeActual(ply)
        if PFX_LinkedShake then
            nextLinkedShakeTime = curTime + math.Rand(PFX_LinkedShake.intervalMin, PFX_LinkedShake.intervalMax)
            if nextLinkedShakeTime >= linkedShakeParentEndTime then nextLinkedShakeTime = 0 end
        else
            nextLinkedShakeTime = 0
        end
    elseif curTime >= linkedShakeParentEndTime then
        nextLinkedShakeTime, linkedShakeParentEndTime = 0, 0
    end

    -- Final output
    local finalBlur   = currentBlur + currentCrouchBlur
    local finalMuffle = math.Clamp(currentMuffle, 0, GetMaxMuffleIntensity())

    if finalBlur > EFFECT_THRESHOLD then
        AddPixelvisHook("PersistentFX_Blur", {
            enabled = true,
            type    = "radial",
            density = math.Clamp(finalBlur * 1.5, 0, 0.6),
            alpha   = finalBlur,
        })
    else
        RemovePixelvisHook("PersistentFX_Blur")
    end

    if finalMuffle > EFFECT_THRESHOLD then
        render.SetDSP(currentDSP, false)
    elseif not state.inSeizure then
        render.SetDSP(0, false)
    end

    if pixelvisNeedsUpdate then ApplyPixelvisHooks() end
end)

-- ===========================================================================
-- CreateMove: Forced Crouch
-- ===========================================================================
hook.Add("CreateMove", "PersistentInjuryV2_ForceCrouch", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if not playerStates or not playerStates[ply] then return end
    local state = playerStates[ply]

    if not cachedConVars.enable or not cachedConVars.forcedCrouchEnable then
        RemovePixelvisHook("PersistentFX_CrouchFX")
        return
    end

    if CurTime() < state.forcedCrouchEndTime then
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
        if cmd:KeyDown(IN_JUMP) then
            cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_JUMP)))
        end
        local st = (state.activeFatigueParams and state.activeFatigueParams.startTime) or (CurTime() - 0.01)
        local cf = CalculateFade(true,
            { startTime = st, duration = state.forcedCrouchEndTime - st },
            state.forcedCrouchEndTime, CurTime(), 0.3, 0.3)
        local im = GetIntensityMultiplier()
        AddPixelvisHook("PersistentFX_CrouchFX", {
            enabled            = true,
            multiply           = Color(245, 245, 250),
            saturation         = math.Approach(1, 0.65, cf),
            vignette_intensity = math.Approach(0, 0.45 * im, cf),
            vignette_radius    = 0.6,
            contrast           = math.Approach(1, 0.9, cf),
        })
    else
        RemovePixelvisHook("PersistentFX_CrouchFX")
    end
end)

-- ===========================================================================
-- CalcView: Two-layer camera motion
-- ===========================================================================
hook.Add("CalcView", "ZZZ_PersistentInjuryV2_ViewModify", function(ply, origin, angles, fov, znear, zfar)
    if not cachedConVars.enable then return end
    if not IsValid(ply) or ply ~= LocalPlayer() then return end
    if not playerStates or not playerStates[ply] then return end

    local state   = playerStates[ply]
    local curTime = CurTime()

    if state.inSeizure then return end

    local ae         = state.activeEffects
    local tiltFx     = ae and ae.tilt
    local lookDownFx = ae and ae.lookDown
    local lp         = state.activeLimpParams
    local fp         = state.activeFatigueParams

    local baseSurgeRoll     = (currentSurgeTilt    ~= 0 and tiltFx and tiltFx.direction)  and (currentSurgeTilt    * tiltFx.direction)  or 0
    local baseLimpRoll      = (currentLimpTilt     ~= 0 and lp     and lp.direction)       and (currentLimpTilt     * lp.direction)      or 0
    local baseFatiguePitch  = currentFatigueTilt
    local baseLookDownPitch = currentLookDownPitch

    local totalRoll  = baseSurgeRoll + baseLimpRoll
    local totalPitch = baseFatiguePitch + baseLookDownPitch
    local totalYaw   = 0

    -- Layer 1: Persistent sway
    if persistentSwayFactor > EFFECT_THRESHOLD then
        local suppress = false
        if cachedConVars.pswayIgnoreWeaponBase then
            local weapon = ply:GetActiveWeapon()
            if IsValid(weapon) then
                local base = weapon.Base or ""
                if string.find(base, "arc9") or string.find(base, "mg_base") then
                    suppress = true
                end
            end
        end

        if not suppress then
            local totalMag    = math.abs(baseSurgeRoll) + math.abs(baseLimpRoll) + math.abs(baseFatiguePitch)
            local episodicAct = math.Clamp(totalMag / math.max(totalMag + 2.0, 2.0), 0, 1)
            local attenuation = math.Clamp(1.0 - episodicAct * 0.75, 0.25, 1.0)
            local sway        = persistentSwayFactor * cachedConVars.pswayIntensity * attenuation
            local t           = (curTime + persistentSwayTimeOffset) *
                                (1.0 + persistentSwayFactor * cachedConVars.pswaySpeed * 4.0)

            totalPitch = totalPitch + math.sin(t)       * sway * 3.0
            totalYaw   = totalYaw   + math.cos(t * 0.8) * sway * 2.0
            totalRoll  = totalRoll  + math.sin(t * 1.2) * sway * 5.0

            totalRoll  = totalRoll  + GetOrganicNoise(curTime * 0.25, persistentSwayTimeOffset,       2) * sway * 1.2
            totalPitch = totalPitch + GetOrganicNoise(curTime * 0.20, persistentSwayTimeOffset + 300, 2) * sway * 0.8
            totalYaw   = totalYaw   + GetOrganicNoise(curTime * 0.18, persistentSwayTimeOffset + 600, 2) * sway * 0.6
        end
    end

    -- Layer 2: Episodic event sway

    -- 2a. Fatigue
    if math.abs(baseFatiguePitch) > EFFECT_THRESHOLD and fp and fp.seed then
        local mag  = math.abs(baseFatiguePitch)
        local seed = fp.seed
        totalPitch = totalPitch + GetBreathingPattern(curTime, seed, mag * 0.35)
        totalRoll  = totalRoll  + GetOrganicNoise(curTime * 0.6, seed,        3) * mag * 0.45
        totalYaw   = totalYaw   + GetOrganicNoise(curTime * 0.5, seed + 500,  3) * mag * 0.30
        totalRoll  = totalRoll  + GetOrganicNoise(curTime * 4.0, seed + 1000, 2) * mag * 0.12
        totalYaw   = totalYaw   + GetOrganicNoise(curTime * 3.5, seed + 1500, 2) * mag * 0.08
    end

    -- 2b. Surge
    if math.abs(baseSurgeRoll) > EFFECT_THRESHOLD and tiltFx and tiltFx.seed then
        local mag  = math.abs(baseSurgeRoll)
        local seed = tiltFx.seed
        totalRoll  = totalRoll  + GetOrganicNoise(curTime * 1.2, seed,       3) * mag * 0.25
        totalYaw   = totalYaw   + GetOrganicNoise(curTime * 1.0, seed + 300, 3) * mag * 0.18
        totalPitch = totalPitch + GetOrganicNoise(curTime * 0.8, seed + 600, 2) * mag * 0.10
    end

    -- 2c. Limp
    if math.abs(baseLimpRoll) > EFFECT_THRESHOLD and lp and lp.seed then
        local mag       = math.abs(baseLimpRoll)
        local seed      = lp.seed
        local direction = lp.direction or 1
        local gaitPhase = curTime * 1.2 + seed * 0.1
        local primary   = math.sin(gaitPhase)              * mag * 0.28
        local secondary = math.sin(gaitPhase * 0.5 + 1.3)  * mag * 0.15
        local organic   = GetOrganicNoise(curTime * 0.7, seed, 2) * mag * 0.20
        totalRoll = totalRoll + (primary + secondary + organic) * direction
        totalYaw  = totalYaw  + math.sin(gaitPhase * 0.3) * mag * 0.15 * direction
    end

    -- 2d. Look-down
    if math.abs(baseLookDownPitch) > EFFECT_THRESHOLD and lookDownFx then
        local mag  = math.abs(baseLookDownPitch)
        local seed = lookDownFx.seed or curTime
        totalPitch = totalPitch + math.sin(curTime * 2.5 + seed) * mag * 0.12
        totalPitch = totalPitch + GetOrganicNoise(curTime * 3.0, seed,       2) * mag * 0.08
        totalRoll  = totalRoll  + GetOrganicNoise(curTime * 1.5, seed + 200, 2) * mag * 0.10
    end

    if math.abs(totalRoll)  > EFFECT_THRESHOLD or
       math.abs(totalPitch) > EFFECT_THRESHOLD or
       math.abs(totalYaw)   > EFFECT_THRESHOLD then
        angles.roll  = angles.roll  + totalRoll
        angles.pitch = angles.pitch + totalPitch
        angles.yaw   = angles.yaw   + totalYaw
    end
end)

-- ===========================================================================
-- Cleanup
-- ===========================================================================
hook.Add("ShutDown", "PersistentInjuryV2_Cleanup", function()
    playerStates         = {}
    ActivePixelvisHooks  = {}
    ApplyPixelvisHooks()
    render.SetDSP(0)
    nextLinkedShakeTime, linkedShakeParentEndTime     = 0, 0
    currentSurgeTilt, currentLimpTilt, currentFatigueTilt = 0, 0, 0
    currentBlur, currentMuffle, currentShakeTime, currentDSP, currentCrouchBlur = 0, 0, 0, 0, 0
    currentLookDownPitch = 0
    springVelocity           = { surge = 0, limp = 0, fatigue = 0, lookDown = 0 }
    persistentSwayFactor     = 0
    persistentSwayTimeOffset = 0
    print("[Persistent Injury V2.9] Cleanup performed.")
end)

-- ===========================================================================
-- UI Panel
-- ===========================================================================
local function BuildPersistentInjuryPanelV2(panel)
    panel:ClearControls()
    panel:Help("Configure Persistent Injury Effects V2.9")
    panel:ControlHelp("Spring physics + Perlin noise + continuous HP-driven sway layer.")
    panel:CheckBox("Enable ALL Effects", "pfx_v2_enable")
    panel:Label("")

    panel:NumSlider("Base Intensity Preset",       "pfx_v2_intensity_preset", 1,   5,   0):SetTooltip("1=Subtle -> 5=Extreme")
    panel:NumSlider("Global Intensity Multiplier", "pfx_v2_intensity_mult",   0.1, 10,  1):SetTooltip("Fine-tune overall effect strength.")
    panel:NumSlider("Global Frequency Multiplier", "pfx_v2_frequency_mult",   0.1, 10,  1):SetTooltip("How often surges/limps/fatigue trigger.")
    panel:NumSlider("Max Muffling Intensity",       "pfx_v2_muffle_max",       0,   1,   2):SetTooltip("0=None, 1=Total deafness.")
    panel:Label("")

    panel:NumSlider("Fatigue Tilt Max Angle",      "pfx_v2_fatigue_max_angle",   1,   30,  1)
    panel:NumSlider("Fatigue Tilt Duration (Sec)", "pfx_v2_fatigue_duration",    1,   10,  1)
    panel:NumSlider("Fatigue Crouch Multiplier",   "pfx_v2_fatigue_crouch_mult", 1,   3,   1)
    panel:Label("")

    panel:CheckBox("Enable Forced Crouch",          "pfx_v2_forced_crouch_enable")
    panel:NumSlider("Crouch Chance (%)",            "pfx_v2_crouch_chance",         0,   100, 0)
    panel:NumSlider("Crouch Check Interval (Sec)",  "pfx_v2_crouch_check_interval", 1,   30,  1)
    panel:NumSlider("Crouch Min Duration (Sec)",    "pfx_v2_crouch_duration_min",   0.5, 10,  1)
    panel:NumSlider("Crouch Max Duration (Sec)",    "pfx_v2_crouch_duration_max",   1,   20,  1)
    panel:NumSlider("Crouch Cooldown (Sec)",        "pfx_v2_crouch_cooldown",       3,   60,  1)
    panel:NumSlider("Crouch Min Severity Level",    "pfx_v2_crouch_min_severity",   1,   5,   0)
    panel:Label("")

    panel:CheckBox("Enable Seizure Effect",       "pfx_v2_seizure_enable")
    panel:NumSlider("Seizure Max Duration (Sec)", "pfx_v2_seizure_max_duration", 2,  60,  1)
    panel:NumSlider("Seizure HP Threshold (%)",   "pfx_v2_seizure_threshold",    1,  25,  0)
    panel:Help("Per-severity values are in lua/autorun/sh_persistent_injury_v2.lua")
    panel:Label("")

    panel:Help("--- Persistent Sway (V2.9, WoundedWalk-inspired) ---")
    panel:CheckBox("Enable Persistent Sway",               "pfx_v2_psway_enable"):SetTooltip("Continuous wobble tied to HP. Grows as HP drops.")
    panel:NumSlider("Sway HP Threshold (%)",               "pfx_v2_psway_threshold",  10,  100, 0):SetTooltip("Sway begins below this HP %.")
    panel:NumSlider("Sway Intensity",                      "pfx_v2_psway_intensity",  0.1, 3,   1):SetTooltip("Overall sway amplitude.")
    panel:NumSlider("Sway Speed Scaling",                  "pfx_v2_psway_speed",      0.1, 3,   1):SetTooltip("How fast sway accelerates as HP drops.")
    panel:CheckBox("Suppress Sway for ARC9/MW Weapons",   "pfx_v2_psway_ignore_weapon_base"):SetTooltip("Disables persistent sway for ARC9/MW-base weapons.")
end

hook.Add("PopulateToolMenu", "PersistentInjuryV2_AddOptionsPanel", function()
    spawnmenu.AddToolMenuOption("Options", "Realism", "PersistentInjuryV2_Panel",
        "Persistent Injury V2.9", "", "", BuildPersistentInjuryPanelV2)
end)

print("[Persistent Injury V2.9] Client script loaded successfully.")
print("[Persistent Injury V2.9] Features: persistent HP-sway, spring physics, Perlin noise, breathing, asymmetric recovery")
