DoIncludeScript("util.nut", null);

const CAM_DISTANCE = 350;
const CAM_YAW = 90;

const PLAYER_YAW = -90;
const PLAYER_X = 0; // we only move on yz-plane
const PLAYER_TURN_INTERVAL = 0.5;
const PLAYER_DOUBLE_JUMP_PARTICLE = "ExplosionCore_MidAir";
const PLAYER_DOUBLE_JUMP_SOUND = "weapons/explode1.wav";
const PLAYER_DOUBLE_JUMP_VEL = 400;

const AIM_INDICATOR_START = 25;
const AIM_INDICATOR_END = 40;
const AIM_INDICATOR_TIP = 5;

const ANGLE_MAX_ERROR = 2.0;

PrecacheSound(PLAYER_DOUBLE_JUMP_SOUND);

function Think()
{
    local ply = null;
    while(ply = Entities.FindByClassname(ply, "player"))
    {
        if (IsValidAndAlive(ply) && IsPlayingTeam(ply.GetTeam()))
        {
            HandleDirection(ply);

            local eyeAngles = ply.EyeAngles();
            // Don't snap eye angles every frame, can cause pitch to become "stuck" randomly.
            // Only correct if drifting too far from the 2D plane.
            // We can't move on the X-axis anyways so small error here is not big issue.
            if (
                abs(eyeAngles.y - ::j2d_players[ply.entindex()].wish_yaw) > ANGLE_MAX_ERROR ||
                abs(eyeAngles.z) > ANGLE_MAX_ERROR
            )
            {
                eyeAngles.y = ::j2d_players[ply.entindex()].wish_yaw;
                eyeAngles.z = 0.0;
                ply.SnapEyeAngles(eyeAngles);
            }

            local playerOrigin = ply.GetOrigin();
            playerOrigin.x = PLAYER_X;
            ply.SetAbsOrigin(playerOrigin);

            DrawAimIndicator(ply, eyeAngles);
            HandleDoubleJump(ply);
            RefillPlayer(ply);
        }
    }
    // think every frame
    return 0;
}

::HandleDirection <- function(ply)
{
    local buttons = GetButtons(ply);
    if (buttons & Constants.FButtons.IN_ATTACK2 && Time() - ::j2d_players[ply.entindex()].last_turn > PLAYER_TURN_INTERVAL)
    {
        ::j2d_players[ply.entindex()].wish_yaw = -::j2d_players[ply.entindex()].wish_yaw;
        ::j2d_players[ply.entindex()].last_turn = Time();
        SendToConsole(format("cam_idealyaw %f", -::j2d_players[ply.entindex()].wish_yaw));
    }
}

::DrawAimIndicator <- function(ply, angles)
{
    local dir = angles.Forward();
    local start = ply.EyePosition() + dir * AIM_INDICATOR_START;
    local end = start + dir * AIM_INDICATOR_END;
    DebugDrawLine_vCol(start, end, Vector(255, 255, 255), true, 0);

    local tip1 = end - (dir - angles.Up()) * AIM_INDICATOR_TIP;
    local tip2 = end - (dir + angles.Up()) * AIM_INDICATOR_TIP;
    DebugDrawLine_vCol(end, tip1, Vector(255, 255, 255), true, 0);
    DebugDrawLine_vCol(end, tip2, Vector(255, 255, 255), true, 0);
}

::HandleDoubleJump <- function(ply)
{
    local ground = GetGroundEntity(ply);
    local buttons = GetButtons(ply);

    if (ground != null)
    {
        ::j2d_players[ply.entindex()].double_jumped = false;
        ::j2d_players[ply.entindex()].ground_time = Time();
    }
    else if (
        buttons & Constants.FButtons.IN_JUMP &&
        !(::j2d_players[ply.entindex()].prev_buttons & Constants.FButtons.IN_JUMP) &&
        ::j2d_players[ply.entindex()].double_jumped == false &&
        Time() - ::j2d_players[ply.entindex()].ground_time > 0.1
    )
    {
        local vel = ply.GetAbsVelocity();
        if (vel.z < PLAYER_DOUBLE_JUMP_VEL)
        {
            vel.z = PLAYER_DOUBLE_JUMP_VEL;
            ply.SetAbsVelocity(vel);
            ::j2d_players[ply.entindex()].double_jumped = true;
            DispatchParticleEffect(PLAYER_DOUBLE_JUMP_PARTICLE, ply.GetOrigin(), Vector(90, 0, 0));
            ply.EmitSound(PLAYER_DOUBLE_JUMP_SOUND);
        }
    }

    ::j2d_players[ply.entindex()].prev_buttons = buttons;
}

::RefillPlayer <- function(ply)
{
    if (GetTFClass(ply) == Constants.ETFClass.TF_CLASS_DEMOMAN)
    {
        ply.SetHealth(175);
    }
    else
    {
        ply.SetHealth(300);
    }

    local weapon = ply.GetActiveWeapon();
    if (weapon && !weapon.IsMeleeWeapon())
    {
        if (weapon.UsesPrimaryAmmo())
        {
            NetProps.SetPropIntArray(ply, "m_iAmmo", 99, weapon.GetPrimaryAmmoType());
        }
        if (weapon.UsesSecondaryAmmo())
        {
            NetProps.SetPropIntArray(ply, "m_iAmmo", 99, weapon.GetSecondaryAmmoType());
        }
        if (weapon.UsesClipsForAmmo1)
        {
            weapon.SetClip1(weapon.GetMaxClip1());
        }
        if (weapon.UsesClipsForAmmo2)
        {
            weapon.SetClip2(weapon.GetMaxClip2());
        }
    }
}

::HandlePlayerCvars <- function(ply)
{
    local cvars = format(
        "    cam_idealdist %d; cam_idealyaw %d; thirdperson; thirdperson_screenspace 1;",
        CAM_DISTANCE
        CAM_YAW
    );

    if (!::j2d_players[ply.entindex()].set_mayamode)
    {
        // This is a toggle instead of 0/1 :(
        cvars += "; thirdperson_mayamode";
        ::j2d_players[ply.entindex()].set_mayamode = true;
    }

    if (ply == GetListenServerHost())
    {
        SendToConsole(cvars);
    }
    else
    {
        ClientPrint(ply, Constants.EHudNotify.HUD_PRINTCENTER, "This map is designed for singleplayer! Check console");
        ClientPrint(ply, Constants.EHudNotify.HUD_PRINTCONSOLE, "This map is designed for singleplayer! Setting these cvars in MP may work:");
        ClientPrint(ply, Constants.EHudNotify.HUD_PRINTCONSOLE, cvars);
    }
}

function OnGameEvent_player_spawn(params)
{
    local ply = GetPlayerFromUserID(params.userid);
    if (ply != null)
    {
        ::j2d_players[ply.entindex()].wish_yaw = PLAYER_YAW;
        HandlePlayerCvars(ply);
    }
}

if (!("j2d_loaded" in getroottable()))
{
    Log("j2d init");
    ::j2d_loaded <- true;
    ::j2d_players <- {};
    for (local i = 0; i < Constants.Server.MAX_PLAYERS; i+=1)
    {
        ::j2d_players[i] <- { double_jumped = false, prev_buttons = 0, ground_time = 0, wish_yaw = PLAYER_YAW, last_turn = 0, set_mayamode = false };
    }

    if (!("HOOKED_EVENTS" in getroottable()))
    {
        Log("j2d hook events");
        __CollectGameEventCallbacks(this);
        ::HOOKED_EVENTS <- true;
    }

    local thinker = SpawnEntityFromTable("info_target", { targetname = "j2d_thinker" } );
    if(thinker.ValidateScriptScope())
    {
        Log("j2d thinker valid");
        thinker.GetScriptScope()["Think"] <- Think;
        AddThinkToEnt(thinker, "Think");
    }
}
else
{
    Log("j2d already init");
}