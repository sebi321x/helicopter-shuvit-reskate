local title = "Helicopter Shove It"
local gravity = 9.8 -- m/s², the stock on-board gravity
local maximum_strength = 80 -- percent of stock gravity
local maximum_tick = 0.08 -- Ignore discontinuities when the game stalls.
local stick_threshold_squared = 0.42 ^ 2
local spin_threshold = math.rad(100) -- radians per second relative to the skater
local spin_gap_limit = 0.18 -- Keep the accumulated turn through short input and pose gaps.
local reversal_threshold = math.rad(22)
local thrust_fade = 0.28
local air_gravity = reskate.skater.air_gravity
local air_descent = reskate.skater.air_descent
local air_lift = reskate.skater.air_lift
local controlled_lift = air_lift or air_descent

local function number_in_range(value, default, minimum, maximum)
    if type(value) ~= "number" or value ~= value then return default end
    return math.clamp(value, minimum, maximum)
end

local enabled = reskate.storage.get("enabled") ~= false
local function load_number(key, default, minimum, maximum)
    return number_in_range(reskate.storage.get(key), default, minimum, maximum)
end
local legacy_lift = load_number("lift_percent", 80, 0, maximum_strength)
local lift = load_number("descent_strength", legacy_lift / maximum_strength * 100, 0, 100)
local drop = load_number("drop_percent", 40, 0, maximum_strength)
local descent_speed = load_number("descent_speed", 1.75, 0.75, 6)
local saved_descent_speed = reskate.storage.get("descent_speed")
local lift_target = load_number("lift_target", type(saved_descent_speed) == "number" and -descent_speed or 2.5, -6, 6)
local start_degrees = load_number("start_degrees", 270, 180, 1080)
local start_360_degrees = load_number("start_360_degrees", 405, 360, 1440)
local ramp_degrees = load_number("ramp_degrees", 135, 45, 720)
local curve_bias = load_number("curve_bias", 0, -100, 100)
local lift_directions = {"Backside", "Frontside", "Both directions"}
local lift_direction = math.round(load_number("lift_direction", 3, 1, #lift_directions))
local rotor_enabled = reskate.storage.get("rotor") ~= false
local log_jumps = reskate.storage.get("log_jumps") == true

local function wrap(angle)
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function trick_key(raw)
    local name = raw:lower():gsub("[^%w]", ""):gsub("shove", "shuv")
    name = name:gsub("^infinite", ""):gsub("^continuous", "")
    name = name:gsub("^switch", ""):gsub("^fakie", ""):gsub("^nollie", ""):gsub("^n", "")
    return (name:gsub("frontside", "fs"):gsub("backside", "bs"))
end

local function shuv_name(key)
    local name = key:gsub("shuvit$", "shuv")
    local side, turns = name:match("^(%a*)(%d*)popshuv$")
    if side == nil then turns, side = name:match("^(%d+)(%a+)popshuv$") end
    if side ~= "" and side ~= "fs" and side ~= "bs" then return nil end
    local degrees = turns == "" and 180 or tonumber(turns)
    if degrees ~= 180 and degrees ~= 360 then return nil end
    return side == "fs" and -1 or 1, degrees
end

local function relative_yaw()
    local board = reskate.board.motion()
    local deck = board and board.deck
    if not deck then return nil, "deck unavailable" end
    local rider_yaw = reskate.skater.heading()
    if not rider_yaw then return nil, "rider heading unavailable" end

    local x, y, z, w = table.unpack(deck.rotation)
    -- A tilted deck can still give a stable heading. Reject it when upside
    -- down or when the forward axis is too close to vertical to measure yaw.
    local forward_x = 2 * (x * z + w * y)
    local forward_z = 1 - 2 * (x * x + y * y)
    if 1 - 2 * (x * x + z * z) <= 0 or forward_x ^ 2 + forward_z ^ 2 < 0.36 then
        return nil, "deck tilted"
    end
    local board_yaw = math.atan2(forward_x, forward_z)
    return wrap(board_yaw - rider_yaw)
end

local in_air = false
local previous
local sample_seconds, sweep = 0, 0
local spin_gap, reverse_sweep = 0, 0
local requested, peak_sweep, lift_seconds = 0, 0, 0
local thrust_weight = 0
local release_time, release_weight = 0, 0
local observed_trick, shuv_direction, shuv_degrees
local last_error, rotor
local rotor_unavailable = false
local holding_gravity = false
local jump_notes = {}
local jump_names = {}
local arc_samples = {}
local air_seconds, next_arc_sample = 0, 0
local online_before

local function note(reason)
    if log_jumps then jump_notes[reason] = (jump_notes[reason] or 0) + 1 end
end

local function stop_rotor()
    if rotor then reskate.audio.stop(rotor) end
    rotor = nil
end

local function stop_effect()
    if holding_gravity then air_gravity(1) end
    holding_gravity = false
    thrust_weight, release_time, release_weight = 0, 0, 0
    stop_rotor()
end

local function update_rotor(thrust)
    if not rotor_enabled or thrust < 0.025 then
        stop_rotor()
        return
    end
    if rotor_unavailable then return end
    local options = {volume = 0.17 * math.sqrt(thrust), pitch = 0.50, throttle = 0.14 + 0.65 * thrust}
    if rotor and reskate.audio.set(rotor, options) then return end
    local reason
    rotor, reason = reskate.audio.play("motor", options)
    rotor_unavailable = not rotor
    if rotor then
        note("rotor started")
    elseif reason then
        reskate.log(title .. " rotor: " .. reason, "warn")
    end
end

local function clear_spin()
    previous = nil
    sample_seconds, sweep, spin_gap, reverse_sweep = 0, 0, 0, 0
end

local function note_spin_gap(reason, dt)
    note(reason)
    spin_gap += dt
    if spin_gap >= spin_gap_limit then clear_spin() end
end

local function sample_arc(dt_ms)
    if not log_jumps or dt_ms <= 0 or dt_ms > maximum_tick * 1000 then return end
    air_seconds += dt_ms * 0.001
    if air_seconds < next_arc_sample or #arc_samples >= 32 then return end
    local skater = reskate.skater.get()
    if not skater then return end
    table.insert(arc_samples, string.format("%.2fs y=%+.2f vy=%+.2f",
        air_seconds, skater.position.y, skater.vertical_speed))
    next_arc_sample = air_seconds + 0.20
end

local function finish_jump()
    if in_air and log_jumps then
        local notes, names = {}, {}
        for label, count in pairs(jump_notes) do table.insert(notes, string.format("%s=%d", label, count)) end
        for name in pairs(jump_names) do table.insert(names, name) end
        table.sort(notes)
        table.sort(names)
        local thrust_log = air_gravity and string.format("%+.3f m/s estimated from fixed-gravity requests", requested) or "rotor only"
        if jump_notes["lift requests accepted"] then
            thrust_log = string.format("%.2fs controlled lift requested", lift_seconds)
        end
        reskate.log(string.format("%s | %s | %.0f degrees of deck swing | %s | %s",
            title, table.concat(names, ", "), math.deg(peak_sweep), thrust_log, table.concat(notes, ", ")))
        if #arc_samples >= 3 then
            reskate.log(string.format("%s arc | %.2fs | %s", title, air_seconds, table.concat(arc_samples, " | ")))
        end
    end
    table.clear(jump_notes)
    table.clear(jump_names)
    table.clear(arc_samples)
    air_seconds, next_arc_sample = 0, 0
    in_air = false
    observed_trick, shuv_direction, shuv_degrees = nil, nil, nil
    requested, peak_sweep, lift_seconds = 0, 0, 0
    rotor_unavailable = false
    clear_spin()
    stop_effect()
end

local function bias_curve(balanced, squared)
    local bias = curve_bias / 100
    if bias < 0 then return balanced + -bias * (squared - balanced) end
    return balanced + bias * (balanced - squared)
end

-- Integrate smoothstep and its square over the ramp. Their blend keeps the
-- selected shape smooth at both ends, including when favoring earlier thrust.
-- Taking the difference over each sample keeps the ramp consistent across frame rates.
local function integrated_curve(turn, ramp_turn)
    local x = math.clamp(turn / ramp_turn, 0, 1)
    local balanced = x ^ 3 * (1 - 0.5 * x)
    local squared = x ^ 5 * (1.8 - 2 * x + (4 / 7) * x ^ 2)
    return ramp_turn * bias_curve(balanced, squared) + math.max(turn - ramp_turn, 0)
end

local function spin_sample(dt)
    local trick = reskate.animation.trick()
    if log_jumps then jump_names[trick or "no trick name"] = true end
    local pad = reskate.input.gamepad()
    if not pad or pad.right_x ^ 2 + pad.right_y ^ 2 < stick_threshold_squared then
        previous, sample_seconds = nil, 0
        note_spin_gap(pad and "stick relaxed" or "controller unavailable", dt)
        return
    end
    if pad.left_trigger > 0.2 or pad.right_trigger > 0.2 then
        note("grab held")
        clear_spin()
        return
    end

    if trick and trick ~= observed_trick then
        local key = trick_key(trick)
        if key ~= "heldfliptrick" then
            local direction, turn = shuv_name(key)
            if shuv_direction and (direction ~= shuv_direction or turn ~= shuv_degrees) then clear_spin() end
            shuv_direction, shuv_degrees = direction, turn
            observed_trick = trick
        end
    end
    -- Sample from the start of the pop. The trick name can appear a few frames later.
    local yaw, why = relative_yaw()
    if not yaw then
        previous, sample_seconds = nil, 0
        note_spin_gap(why, dt)
        return
    end
    if not previous then
        previous = yaw
        return
    end

    sample_seconds += dt
    local step = wrap(yaw - previous)
    -- The drawn pose can repeat between frames. Give it a short window to advance.
    if math.abs(step) < math.rad(0.35) then
        note_spin_gap("deck still", dt)
        return
    end
    previous = yaw
    local elapsed = sample_seconds
    sample_seconds = 0
    if math.abs(step) > math.rad(75) or math.abs(step) < spin_threshold * elapsed then
        note_spin_gap("spin out of range", dt)
        return
    end
    spin_gap = 0
    if sweep * step < 0 then
        reverse_sweep += step
        if math.abs(reverse_sweep) < reversal_threshold then
            sweep += step
            note("brief turn back")
            return
        end
        note("spin reversed")
        step = reverse_sweep
        sweep = 0
    end
    reverse_sweep = 0
    local previous_sweep = math.abs(sweep)
    sweep += step
    peak_sweep = math.max(peak_sweep, math.abs(sweep))
    local start_turn = math.rad(shuv_degrees == 360 and start_360_degrees or start_degrees)
    if not shuv_degrees or math.abs(sweep) <= start_turn then
        note(not shuv_degrees and "shuv unrecognized" or "awaiting turn")
        return
    end

    local ramp_turn = math.rad(ramp_degrees)
    local curve = (integrated_curve(math.abs(sweep) - start_turn, ramp_turn)
        - integrated_curve(previous_sweep - start_turn, ramp_turn)) / math.abs(step)
    local lifts = lift_direction == 3 or shuv_direction == (lift_direction == 1 and 1 or -1)
    return lifts and 1 or -1, curve
end

local function apply_effect(ok, reason)
    if not ok then
        stop_effect()
        if reason ~= last_error then
            reskate.log(title .. ": " .. tostring(reason), "warn")
            last_error = reason
        end
        return false
    end
    holding_gravity = true
    last_error = nil
    return true
end

local function eased(x)
    x = math.clamp(x, 0, 1)
    return x ^ 2 * (3 - 2 * x)
end

local function update_thrust(dt, direction, curve)
    if direction then
        local strength = direction > 0 and lift or drop
        thrust_weight = direction * strength / 100 * math.clamp(curve, 0, 1)
        release_time = 0
    else
        if release_time == 0 then release_weight = thrust_weight end
        release_time += dt
        thrust_weight = release_weight * (1 - eased(release_time / thrust_fade))
    end
    local magnitude = math.abs(thrust_weight)
    if magnitude < 0.001 then
        stop_effect()
        return
    end

    if thrust_weight > 0 and controlled_lift then
        local target = air_lift and lift_target or descent_speed
        if not apply_effect(controlled_lift(target, magnitude)) then return end
        lift_seconds += dt
        note("lift requests accepted")
    elseif air_gravity then
        local fraction = thrust_weight > 0 and thrust_weight * maximum_strength / 100 or thrust_weight
        if not apply_effect(air_gravity(1 - fraction)) then return end
        requested += gravity * dt * fraction
        note("gravity requests accepted")
    end
    update_rotor(magnitude)
end

local function update(dt_ms)
    local online = reskate.session.active()
    if online ~= online_before then
        reskate.log(title .. (online and " paused in multiplayer" or " ready for offline play"))
        online_before = online
    end
    if not enabled or online or reskate.skater.state() ~= "air" then
        finish_jump()
        return
    end
    in_air = true

    sample_arc(dt_ms)
    local dt = dt_ms * 0.001
    if dt <= 0 or not reskate.input.allowed() then
        note(dt <= 0 and "frame gap" or "input blocked")
        clear_spin()
        stop_effect()
        return
    end
    if dt > maximum_tick then
        previous, sample_seconds = nil, 0
        note_spin_gap("frame gap", dt)
        update_thrust(dt)
        return
    end

    local direction, curve = spin_sample(dt)
    update_thrust(dt, direction, curve)
end

local function save(key, before, after)
    if before ~= after then reskate.storage.set(key, after) end
    return after
end

reskate.menu.page(title, function(ui)
    enabled = save("enabled", enabled, ui:toggle("enabled", "Enabled in offline play", enabled))
    ui:note("Turns on offline thrust for as long as you spin. You can stop and start again midair.")
    if not air_gravity then ui:note("Rotor only. Lift and drop require the flight gravity runtime patch.") end
    lift_direction = save("lift_direction", lift_direction,
        ui:dropdown("lift_direction", "Lift direction", lift_directions, lift_direction))
    ui:note("Both gives lift in either direction. Choose one direction to make the other dive.")
    lift = save("descent_strength", lift, ui:slider("lift", "Lift strength", lift, 0, 100, "%.0f%%"))
    ui:note("Higher settings brake harder and hold the target speed more closely.")
    if air_lift then
        lift_target = save("lift_target", lift_target,
            ui:stepper("lift_target", "Target vertical speed", lift_target, -6, 6, 0.25, "%.2f m/s"))
        ui:note("Positive climbs. Zero hovers. Negative descends.")
    elseif air_descent then
        descent_speed = save("descent_speed", descent_speed,
            ui:stepper("descent_speed", "Target descent speed", descent_speed, 0.75, 6, 0.25, "%.2f m/s"))
        ui:note("Sets how fast you drift down while lift is active.")
    end
    if lift_direction ~= 3 then
        drop = save("drop_percent", drop, ui:slider("drop", "Peak drop", drop, 0, maximum_strength, "%.0f%% of gravity"))
        ui:note("Adds downward acceleration. Set this to zero to turn the dive off.")
    end
    start_degrees = save("start_degrees", start_degrees,
        ui:stepper("start", "Start angle for pop shuvits", start_degrees, 180, 1080, 15, "%.0f°"))
    ui:note("How far the deck turns relative to you before thrust starts or restarts. Also applies to nollies.")
    start_360_degrees = save("start_360_degrees", start_360_degrees,
        ui:stepper("start_360", "Start angle for 360 shuvits", start_360_degrees, 360, 1440, 15, "%.0f°"))
    ui:note("A separate threshold for 360s gives a regular 360 shuv room to finish.")
    ramp_degrees = save("ramp_degrees", ramp_degrees,
        ui:stepper("ramp", "Rotation from start to peak", ramp_degrees, 45, 720, 15, "%.0f°"))
    ui:note("How much farther you spin to reach full thrust. A shorter ramp hits faster.")
    curve_bias = save("curve_bias", curve_bias, ui:slider("bias", "Curve bias", curve_bias, -100, 100, "%.0f"))
    ui:note("Negative builds later. Positive builds earlier. The gauge shows the halfway point.")
    ui:bar("Thrust halfway through the ramp", 100 * bias_curve(0.5, 0.25), 0, 100)
    rotor_enabled = save("rotor", rotor_enabled, ui:toggle("rotor", "Rotor sound", rotor_enabled))
    ui:note("Plays the chopper sound as thrust builds.")
    if not rotor_enabled then stop_rotor() end
    log_jumps = save("log_jumps", log_jumps, ui:toggle("log_jumps", "Log jumps for tuning", log_jumps))
    ui:note("Records spin, thrust and jump height in ReSkate.log.")
end)

reskate.on("tick", update)
reskate.on("level_unloading", finish_jump)
reskate.log(title .. (air_lift and " loaded (offline, continuous climb and hover)" or air_descent and " loaded (offline, controlled descent)"
    or air_gravity and " loaded (offline, flight gravity)" or " loaded (offline, rotor only)"))
