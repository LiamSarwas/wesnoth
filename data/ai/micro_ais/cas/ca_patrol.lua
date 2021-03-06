local H = wesnoth.require "lua/helper.lua"
local AH = wesnoth.require "ai/lua/ai_helper.lua"

local ca_patrol = {}

function ca_patrol:evaluation(ai, cfg)
    local patrol
    if cfg.filter then
        patrol = wesnoth.get_units({
            side = wesnoth.current.side,
            { "and", cfg.filter },
            formula = '$this_unit.moves > 0' }
        )[1]
    else
        patrol = wesnoth.get_units({ id = cfg.id, formula = '$this_unit.moves > 0' })[1]
    end

    -- Check if unit exists as sticky BCAs are not always removed successfully
    if patrol then return cfg.ca_score end
    return 0
end

function ca_patrol:execution(ai, cfg, self)
    local patrol
    if cfg.filter then
        patrol = wesnoth.get_units({
            side = wesnoth.current.side,
            { "and", cfg.filter },
            formula = '$this_unit.moves > 0' }
        )[1]
    else
        patrol = wesnoth.get_units({ id = cfg.id, formula = '$this_unit.moves > 0' })[1]
    end

    cfg.waypoint_x = AH.split(cfg.waypoint_x, ",")
    cfg.waypoint_y = AH.split(cfg.waypoint_y, ",")

    local n_wp = #cfg.waypoint_x  -- just for convenience

    -- Set up waypoints, taking into account whether 'reverse' is set
    -- This works even the first time, when self.data.id_reverse is not set yet
    local waypoints = {}
    if self.data[patrol.id..'_reverse'] then
        for i = 1,n_wp do
            waypoints[i] = { tonumber(cfg.waypoint_x[n_wp-i+1]), tonumber(cfg.waypoint_y[n_wp-i+1]) }
        end
    else
        for i = 1,n_wp do
            waypoints[i] = { tonumber(cfg.waypoint_x[i]), tonumber(cfg.waypoint_y[i]) }
        end
    end

    -- if not set, set next location (first move)
    -- This needs to be in WML format, so that it persists over save/load cycles
    if (not self.data[patrol.id..'_x']) then
        self.data[patrol.id..'_x'] = waypoints[1][1]
        self.data[patrol.id..'_y'] = waypoints[1][2]
        self.data[patrol.id..'_reverse'] = false
    end

    while patrol.moves > 0 do
        -- Check whether one of the enemies to be attacked is next to the patroller
        -- If so, don't move, but attack that enemy
        local enemies = wesnoth.get_units {
            id = cfg.attack,
            { "filter_adjacent", { id = cfg.id } },
            { "filter_side", {{ "enemy_of", { side = wesnoth.current.side } }} }
        }
        if next(enemies) then break end

        -- Also check whether we're next to any unit (enemy or ally) which is on the next waypoint
        local unit_on_wp = wesnoth.get_units {
            x = self.data[patrol.id..'_x'],
            y = self.data[patrol.id..'_y'],
            { "filter_adjacent", { id = cfg.id } }
        }[1]

        for i,wp in ipairs(waypoints) do
            -- If the patrol is on a waypoint or adjacent to one that is occupied by any unit
            if ((patrol.x == wp[1]) and (patrol.y == wp[2]))
                or (unit_on_wp and ((unit_on_wp.x == wp[1]) and (unit_on_wp.y == wp[2])))
            then
                if (i == n_wp) then
                    -- Move him to the first one (or reverse route), if he's on the last waypoint
                    -- Unless cfg.one_time_only is set
                    if cfg.one_time_only then
                        self.data[patrol.id..'_x'] = waypoints[n_wp][1]
                        self.data[patrol.id..'_y'] = waypoints[n_wp][2]
                    else
                        -- Go back to first WP or reverse direction
                        if cfg.out_and_back then
                            self.data[patrol.id..'_x'] = waypoints[n_wp-1][1]
                            self.data[patrol.id..'_y'] = waypoints[n_wp-1][2]

                            -- We also need to reverse the waypoints right here, as this might not be the end of the move
                            self.data[patrol.id..'_reverse'] = not self.data[patrol.id..'_reverse']
                            local tmp_wp = {}
                            for i,wp in ipairs(waypoints) do tmp_wp[n_wp-i+1] = wp end
                            waypoints = tmp_wp
                        else
                            self.data[patrol.id..'_x'] = waypoints[1][1]
                            self.data[patrol.id..'_y'] = waypoints[1][2]
                        end
                    end
                else
                    -- ... else move him on the next waypoint
                    self.data[patrol.id..'_x'] = waypoints[i+1][1]
                    self.data[patrol.id..'_y'] = waypoints[i+1][2]
                end
            end
        end

        -- If we're on the last waypoint on one_time_only is set, stop here
        if cfg.one_time_only and
            (patrol.x == waypoints[n_wp][1]) and (patrol.y == waypoints[n_wp][2])
        then
            AH.checked_stopunit_moves(ai, patrol)
        else  -- otherwise move toward next WP
            local x, y = wesnoth.find_vacant_tile(self.data[patrol.id..'_x'], self.data[patrol.id..'_y'], patrol)
            local nh = AH.next_hop(patrol, x, y)
            if nh and ((nh[1] ~= patrol.x) or (nh[2] ~= patrol.y)) then
                AH.checked_move(ai, patrol, nh[1], nh[2])
            else
                AH.checked_stopunit_moves(ai, patrol)
            end
        end
        if (not patrol) or (not patrol.valid) then return end
    end

    -- Attack unit on the last waypoint under all circumstances if cfg.one_time_only is set
    local enemies = {}
    if cfg.one_time_only then
        enemies = wesnoth.get_units{
            x = waypoints[n_wp][1],
            y = waypoints[n_wp][2],
            { "filter_adjacent", { id = cfg.id } },
            { "filter_side", {{ "enemy_of", { side = wesnoth.current.side } }} }
        }
    end

    -- Otherwise attack adjacent enemy (if specified)
    if (not next(enemies)) then
        enemies = wesnoth.get_units{
            id = cfg.attack,
            { "filter_adjacent", { id = cfg.id } },
            { "filter_side", {{ "enemy_of", { side = wesnoth.current.side } }} }
        }
    end

    if next(enemies) then
        for i,v in ipairs(enemies) do
            AH.checked_attack(ai, patrol, v)
            break
        end
    end
    if (not patrol) or (not patrol.valid) then return end

    AH.checked_stopunit_all(ai, patrol)
end

return ca_patrol
