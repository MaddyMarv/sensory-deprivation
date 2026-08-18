local mod = get_mod("sensory_deprivation")

mod.original_gamma = nil
mod.original_volume = nil
mod.flash_timer = 0
mod.has_recorded_run = false

local function format_time(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    local ms = math.floor((seconds % 1) * 100)
    return string.format("%02d:%02d.%02d", mins, secs, ms)
end

local COLLISION_FILTER = "filter_player_character_ballistic_raycast"
local EXPIRE_BUCKET = 0.5
local RADIAL_MIN_PITCH = math.rad(-85)
local RADIAL_MAX_PITCH = math.rad(85)

local scanning = false
local scan_type = "fov"
local scan_row = 0
local line_object = nil
local line_world = nil
local dots = {}
local clock = 0
local next_expire = math.huge

local rebuilding = false
local rebuild_read = 1
local rebuild_write = 1
local rebuild_len = 0
local auto_pulse_timer = 0

mod.apply_gamma_challenge = function()
    local enable_blind = mod:get("enable_blind")

    if not enable_blind then
        mod.restore_blind()
        return
    end

    if mod.original_gamma == nil then
        mod.original_gamma = Application.user_setting("gamma") or 0
    end

    if Application.user_setting("gamma") ~= 100 then
        Application.set_user_setting("gamma", 100)
        Application.apply_user_settings()
    end
end

mod.restore_blind = function()
    if mod.original_gamma ~= nil then
        Application.set_user_setting("gamma", mod.original_gamma)
        mod.original_gamma = nil
    else
        Application.set_user_setting("gamma", 0)
    end
    Application.apply_user_settings()
    Application.save_user_settings()
end

mod.trigger_explosion_flash = function()
    mod.flash_timer = 1.5
end

mod.apply_deaf = function()
    local enable_deaf = mod:get("enable_deaf")
    if not enable_deaf then
        mod.restore_deaf()
        return
    end

    if mod.original_volume == nil then
        mod.original_volume = Application.user_setting("sound_settings", "option_master_slider") or 100
    end
    
    if Application.user_setting("sound_settings", "option_master_slider") ~= 0 then
        if Wwise then
            Wwise.set_parameter("option_master_slider", 0)
        end
        Application.set_user_setting("sound_settings", "option_master_slider", 0)
        Application.apply_user_settings()
    end
end

mod.restore_deaf = function()
    if mod.original_volume ~= nil then
        if Wwise then
            Wwise.set_parameter("option_master_slider", mod.original_volume)
        end
        Application.set_user_setting("sound_settings", "option_master_slider", mod.original_volume)
        mod.original_volume = nil
        Application.apply_user_settings()
        Application.save_user_settings()
    end
end

local function get_camera_pose()
    local local_player = Managers.player and Managers.player:local_player(1)
    if not local_player then return nil end

    local camera_manager = Managers.state and Managers.state.camera
    if not camera_manager then return nil end

    local viewport_name = local_player.viewport_name
    if not camera_manager:has_viewport(viewport_name) then return nil end

    return camera_manager:camera_pose(viewport_name)
end

local function get_radial_origin()
    local local_player = Managers.player and Managers.player:local_player(1)
    local unit = local_player and local_player.player_unit

    if unit and Unit.alive(unit) then
        return Unit.world_position(unit, 1) + Vector3(0, 0, 1.2)
    end

    local pose = get_camera_pose()
    return pose and Matrix4x4.translation(pose)
end

local function get_line_object()
    local world = Managers.world and Managers.world:world("level_world")
    if not world then return nil end

    if not line_object or line_world ~= world then
        line_object = World.create_line_object(world)
        if not line_object then return nil end
        line_world = world
    end

    return line_object, world
end

local function add_dot_lines(lo, pos, normal, r, num_lines)
    local color = (normal.z > 0.7) and Color(255, 255, 0, 0) or Color(255, 0, 255, 0)
    
    LineObject.add_line(lo, color, pos - Vector3(0, 0, r), pos + Vector3(0, 0, r))
    if num_lines >= 2 then
        LineObject.add_line(lo, color, pos - Vector3(r, 0, 0), pos + Vector3(r, 0, 0))
    end
    if num_lines >= 3 then
        LineObject.add_line(lo, color, pos - Vector3(0, r, 0), pos + Vector3(0, r, 0))
    end
end

local rebuild_step

local function start_rebuild()
    local lo = get_line_object()
    if not lo then return end

    LineObject.reset(lo)
    rebuilding = true
    rebuild_read = 1
    rebuild_write = 1
    rebuild_len = #dots
    next_expire = math.huge
end

rebuild_step = function(chunk)
    local lo, world = get_line_object()
    if not lo then
        rebuilding = false
        return
    end

    local dot_r = 5 / 1000
    local num_lines = 3
    local processed = 0

    while rebuild_read <= rebuild_len and processed < chunk do
        local dot = dots[rebuild_read]
        if dot.expire > clock then
            dots[rebuild_write] = dot
            rebuild_write = rebuild_write + 1

            add_dot_lines(lo, dot.pos:unbox(), dot.normal:unbox(), dot_r, num_lines)
            if dot.expire < next_expire then next_expire = dot.expire end
        end

        rebuild_read = rebuild_read + 1
        processed = processed + 1
    end

    LineObject.dispatch(world, lo)

    if rebuild_read > rebuild_len then
        for i = rebuild_len, rebuild_write, -1 do
            dots[i] = nil
        end
        rebuilding = false
    end
end

local function scan_rows(num_rows)
    local world = Managers.world and Managers.world:world("level_world")
    local physics_world = world and World.physics_world(world)
    if not physics_world then
        scanning = false
        return
    end

    local lo = get_line_object()
    if not lo then
        scanning = false
        return
    end

    local max_dots = 35000
    if #dots >= max_dots then
        scanning = false
        return
    end

    local origin, forward, right, up
    if scan_type == "radial" then
        origin = get_radial_origin()
        if not origin then
            scanning = false
            return
        end
    else
        local pose = get_camera_pose()
        if not pose then
            scanning = false
            return
        end
        origin = Matrix4x4.translation(pose)
        local cam_rotation = Matrix4x4.rotation(pose)
        forward = Quaternion.forward(cam_rotation)
        right = Quaternion.right(cam_rotation)
        up = Quaternion.up(cam_rotation)
    end

    local h_res = 80
    local v_res = 50
    local h_fov = math.rad(90)
    local v_fov = math.rad(60)
    
    local max_range = mod:get("lidar_range_meters") or 3
    
    local duration = 15
    local dot_r = 5 / 1000
    local num_lines = 3
    local expire = (math.floor((clock + duration) / EXPIRE_BUCKET) + 1) * EXPIRE_BUCKET
    local h_half_tan = math.tan(h_fov / 2)
    local v_half_tan = math.tan(v_fov / 2)
    local rows_done = 0
    local added = false

    while scan_row < v_res and rows_done < num_rows do
        for col = 0, h_res - 1 do
            local direction
            if scan_type == "radial" then
                local pitch = RADIAL_MIN_PITCH + (RADIAL_MAX_PITCH - RADIAL_MIN_PITCH) * (scan_row / (v_res - 1))
                local yaw = 2 * math.pi * (col / h_res)
                local cos_pitch = math.cos(pitch)
                direction = Vector3(cos_pitch * math.cos(yaw), cos_pitch * math.sin(yaw), math.sin(pitch))
            else
                local v_t = 2 * (scan_row / (v_res - 1)) - 1
                local h_t = 2 * (col / (h_res - 1)) - 1
                direction = Vector3.normalize(forward + right * (h_t * h_half_tan) + up * (-v_t * v_half_tan))
            end

            local ok, hit, hit_position, hit_distance, hit_normal = pcall(
                PhysicsWorld.raycast, physics_world, origin, direction, max_range,
                "closest", "types", "both", "collision_filter", COLLISION_FILTER)

            if ok and hit and hit_position and hit_normal then
                dots[#dots + 1] = {
                    pos = Vector3Box(hit_position),
                    normal = Vector3Box(hit_normal),
                    expire = expire,
                }
                add_dot_lines(lo, hit_position, hit_normal, dot_r, num_lines)
                added = true
                if expire < next_expire then next_expire = expire end
            end
        end

        scan_row = scan_row + 1
        rows_done = rows_done + 1
    end

    if added then
        LineObject.dispatch(line_world, lo)
    end

    if scan_row >= v_res then
        scanning = false
    end
end

mod.lidar_scan = function()
    if scanning or not mod:get("enable_lidar") then return end
    scanning = true
    scan_type = "fov"
    scan_row = 0
end

mod.radial_scan = function()
    if scanning or not mod:get("enable_lidar") then return end
    scanning = true
    scan_type = "radial"
    scan_row = 0
end

local function reset_state()
    scanning = false
    scan_row = 0
    dots = {}
    next_expire = math.huge
    rebuilding = false
    auto_pulse_timer = 0
end

local function clear_all()
    reset_state()
    if line_object and line_world then
        LineObject.reset(line_object)
        LineObject.dispatch(line_world, line_object)
    end
end

mod.is_in_active_gameplay = function()
    local state_manager = Managers.state
    local game_mode = state_manager and state_manager.game_mode
    if not game_mode or game_mode:game_mode_name() == "hub" then
        return false
    end
    return true
end

local was_in_gameplay = false

mod.update = function(dt)
    local in_gameplay = mod.is_in_active_gameplay()

    if in_gameplay and not was_in_gameplay then
        mod.apply_gamma_challenge()
        mod.apply_deaf()
    elseif not in_gameplay and was_in_gameplay then
        mod.restore_blind()
        mod.restore_deaf()
    end
    was_in_gameplay = in_gameplay

    if mod.flash_timer > 0 then
        mod.flash_timer = mod.flash_timer - dt
    end
    
    if not in_gameplay then
        if #dots > 0 then
            clear_all()
        end
        return
    end

    if mod:get("enable_lidar") then
        clock = clock + dt

        if rebuilding then
            rebuild_step(1500)
        else
            if scanning then
                scan_rows(5)
            end

            if clock >= next_expire then
                start_rebuild()
            end

            if mod:get("lidar_auto_pulse") then
                auto_pulse_timer = auto_pulse_timer + dt
                local interval = mod:get("lidar_auto_pulse_interval") or 2
                if auto_pulse_timer >= interval and not scanning and not rebuilding then
                    auto_pulse_timer = 0
                    scan_type = "radial"
                    scanning = true
                    scan_row = 0
                end
            else
                auto_pulse_timer = 0
            end
        end
    else
        if #dots > 0 then
            clear_all()
        end
    end
end



mod:hook("UIHud", "draw", function(func, self, dt, t, input_service, ...)
    if mod.flash_timer > 0 and mod:get("enable_explosion_flash") then
        local ui_renderer = self._ui_renderer
        if ui_renderer and ui_renderer.gui then
            local w = RESOLUTION_LOOKUP.width or 1920
            local h = RESOLUTION_LOOKUP.height or 1080
            local alpha = math.clamp((mod.flash_timer / 1.5) * 255, 0, 255)
            Gui.rect(ui_renderer.gui, Vector3(0, 0, 0), Vector2(w, h), Color(alpha, 255, 255, 255))
        end
    end
    return func(self, dt, t, input_service, ...)
end)

mod:hook_require("scripts/utilities/attack/explosion", function(instance)
    mod:hook(instance, "create_husk_explosion", function(func, world, physics_world, wwise_world, attacking_owner_unit_or_nil, explosion_template, position, ...)
        if mod:get("enable_explosion_flash") then
            if explosion_template and (explosion_template.vfx or explosion_template.scalable_vfx) then
                local player = Managers.player and Managers.player:local_player(1)
                local player_unit = player and player.player_unit
                if player_unit and POSITION_LOOKUP[player_unit] then
                    local dist_sq = Vector3.distance_squared(POSITION_LOOKUP[player_unit], position)
                    local range = mod:get("flash_range_meters") or 30
                    if dist_sq < (range * range) then
                        mod.trigger_explosion_flash()
                    end
                end
            end
        end
        return func(world, physics_world, wwise_world, attacking_owner_unit_or_nil, explosion_template, position, ...)
    end)
end)

mod:hook_require("scripts/managers/game_mode/game_mode_manager", function(instance)
    mod:hook(instance, "_set_end_conditions_met", function(func, self, outcome, ...)
        if mod:get("enable_speedrun_timer") and outcome == "won" and not mod.has_recorded_run then
            mod.has_recorded_run = true
            
            local mission_system = Managers.state.mission
            local mission = mission_system and mission_system:mission()
            local mission_name = mission and mission.mission_name
            local time = Managers.time and Managers.time:time("gameplay")
            
            if mission_name and time then
                local pb_key = "pb_" .. mission_name
                local current_pb = mod:get(pb_key)
                local formatted_time = format_time(time)
                
                if not current_pb or time < current_pb then
                    mod:set(pb_key, time, true)
                    mod:echo("NEW RECORD! Mission Time: " .. formatted_time)
                else
                    mod:echo("Mission Complete! Time: " .. formatted_time .. " (PB: " .. format_time(current_pb) .. ")")
                end
            end
        end
        return func(self, outcome, ...)
    end)
end)

mod.on_game_state_changed = function(status, state_name)
    if state_name == "StateGameplay" then
        if status == "enter" then
            mod.has_recorded_run = false
        elseif status == "exit" then
            was_in_gameplay = false
            mod.restore_blind()
            mod.restore_deaf()
            reset_state()
            line_object = nil
            line_world = nil
        end
    end
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "enable_lidar" then
        if not mod:get("enable_lidar") then
            clear_all()
        end
    end

    if not mod.is_in_active_gameplay() then return end
    
    if setting_id == "enable_blind" then
        mod.apply_gamma_challenge()
    elseif setting_id == "enable_deaf" then
        mod.apply_deaf()
    end
end

mod.on_unload = function()
    mod.restore_blind()
    mod.restore_deaf()
    clear_all()
end
mod.on_disabled = function()
    mod.restore_blind()
    mod.restore_deaf()
    clear_all()
end
