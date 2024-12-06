local ENTITY = FindMetaTable("Entity")
local PLAYER = FindMetaTable("Player")
local eGetMoveType = ENTITY.GetMoveType
local viewbobCompensation = CreateClientConVar("cl_cview_viewbob_compensation", 1, true, false, "Intensity of cBobbing angular compensation.", 0, 5)
local timeScale = GetConVar("host_timescale")
local viewBobTime = 0
local viewBobIntensity = 1
local originalPos = Vector()
local originalAng = Angle()
local lastCalcViewBob = 0

local function DoViewbob(ply, pos, ang, time, intensity, moveType, frameTime)
    originalAng:Set(ang)

    local sysTime = SysTime()
    local delta = math.min(sysTime - lastCalcViewBob, frameTime or FrameTime(), 1 / 30)
    delta = (delta * game.GetTimeScale()) * timeScale:GetFloat()

    moveType = moveType or eGetMoveType(ply)

    local right = vector_origin

    -- COMMENT
    if moveType != MOVETYPE_LADDER then
        right = originalAng:Right()
    end

    originalPos:Set(pos)

    local up = originalAng:Up()

    -- local hitDist = 196
    -- BobEyeFocus = math.Approach(BobEyeFocus, hitDist, (hitDist - BobEyeFocus) * delta * 5)

    pos:Add(up * math.sin((time + 0.5) * (4 * math.pi)) * 0.3 * intensity * -7)
    pos:Add(right * math.sin((time + 0.5) * (2 * math.pi)) * 0.3 * intensity * -7)

    local bobEyeFocus = 196
    local fw = originalAng:Forward()

    fw:Mul(bobEyeFocus)
    originalPos:Add(fw)
    originalPos:Sub(pos)

    local newAng = originalPos:GetNormalized():Angle()
    originalAng:Normalize()
    newAng:Normalize()

    local bobFac = math.Clamp(1 - math.pow(math.abs(originalAng.p) / 90, 3), 0, 1) * viewbobCompensation:GetFloat()
    ang.y = ang.y - math.Clamp(math.AngleDifference(originalAng.y, newAng.y), -2, 2) * bobFac
    ang.p = ang.p - math.Clamp(math.AngleDifference(originalAng.p, newAng.p), -2, 2) * bobFac

    lastCalcViewBob = sysTime
end

local aIsValid = IsValid
local aGetViewEntity = GetViewEntity
local pIsAlive = PLAYER.Alive
local pGetVehicle = PLAYER.GetVehicle
local eGetVelocity = ENTITY.GetVelocity
local eGetMoveType = ENTITY.GetMoveType
local pGetRunSpeed = PLAYER.GetRunSpeed
local eIsFlagSet = ENTITY.IsFlagSet
local pIsSprinting = PLAYER.IsSprinting
local pGetActiveWeapon = PLAYER.GetActiveWeapon
local eIsValid = ENTITY.IsValid
local eGetNW2Bool = ENTITY.GetNW2Bool
local viewbobEnabled = CreateClientConVar("cl_cview_viewbob_enabled", 1, true, false, "", 0, 1)
local viewbobIntensityCVar = CreateClientConVar("cl_cview_viewbob_intensity", 1.0, true, false, "Intensity of cBobbing viewbob.", 0.1, 10)
local viewRoll = CreateClientConVar("cl_cview_viewroll_enabled", 0, true, false, "", 0, 1)
local viewRollIntensity = CreateClientConVar("cl_cview_viewroll_intensity", 1.0, true, false, "", 0.1, 10)
local moveRW = false

hook.Add("CalcView", "CView", function(ply, origin, angles, fov, zNear, zFar)
    if ply != aGetViewEntity() or !pIsAlive(ply) or aIsValid(pGetVehicle(ply)) then
        return
    end

    local velocity = eGetVelocity(ply)
    local moveType = eGetMoveType(ply)
    local isNoClipping = moveType == MOVETYPE_NOCLIP

    -- View roll
    if !isNoClipping and viewRoll:GetBool() then
        local side = velocity:Dot(angles:Right())
        local sign = 1

        if side < 0 then
            sign = -1
        end

        side = math.Clamp(math.abs(side), 0, 1000) * viewRollIntensity:GetFloat()

        angles.r = angles.r + (sign * side) * 0.005
    end

    local frameTime = FrameTime()

    -- Viewpunch
    if !isNoClipping and viewbobEnabled:GetBool() and !eGetNW2Bool(ply, "TrueSlide.IsSliding", false) then
        local airWalkScale = eIsFlagSet(ply, FL_ONGROUND) and 1 or 0.2

        if moveRW == false then
            moveRW = GetConVar("sv_kait_enabled") or GetConVar("kait_movement_enabled")
        end

        local runSpeed = pGetRunSpeed(ply)
        local moveRWEnabled = moveRW and moveRW:GetBool()

        -- WORKAROUND: Movement reworked mults run speed by 1.5 for some reason.
        if moveRWEnabled then
            runSpeed = runSpeed / 1.5
        end

        -- HACK: At full speed, the view bob looks terrible no matter what the intensity convar is set to.
        -- This alievates the issue.
        runSpeed = runSpeed * 1.5

        local velocityFrac = math.max(velocity:Length2D() * airWalkScale - velocity.z * 0.5, 0)
        local rate = math.Clamp(math.sqrt(velocityFrac / runSpeed) * 1.75, 0.15, 2)

        viewBobTime = viewBobTime + frameTime * rate
        viewBobIntensity = 0.15 + velocityFrac / runSpeed

        DoViewbob(ply, origin, angles, viewBobTime, viewBobIntensity * viewbobIntensityCVar:GetFloat(), moveType, frameTime)
    end
end)

local eGetTable = ENTITY.GetTable
local eGetOwner = ENTITY.GetOwner
local pShouldDrawLocalPlayer = PLAYER.ShouldDrawLocalPlayer
local blacklistedBases = {
    ["cw_base"] = true,
    ["mg_base"] = true
}

hook.Add("CalcViewModelView", "CView.Viewbob", function(wep, vm, oPos, oAng, pos, ang)
    -- COMMENT
    if !viewbobEnabled:GetBool() or blacklistedBases[wep.Base] then
        return
    end

    local owner = eGetOwner(wep)

    if owner != LocalPlayer() or eGetMoveType(owner) == MOVETYPE_NOCLIP or pShouldDrawLocalPlayer(owner) or (TrueSlide and eGetNW2Bool(owner, "TrueSlide.IsSliding", false)) then
        return
    end

    DoViewbob(owner, pos, ang, viewBobTime, viewBobIntensity * viewbobIntensityCVar:GetFloat())
end)