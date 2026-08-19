local mod = get_mod("sensory_deprivation")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "challenge_group",
                type = "group",
                tab = mod:localize("tab_challenge"),
                sub_widgets = {
                    {
                        setting_id = "enable_blind",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "enable_deaf",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "enable_explosion_flash",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "flash_range_meters",
                        type = "numeric",
                        default_value = 15,
                        range = { 5, 30 },
                        decimals_number = 0,
                    },
                },
            },
            {
                setting_id = "lidar_group",
                type = "group",
                tab = mod:localize("tab_lidar"),
                sub_widgets = {
                    {
                        setting_id = "enable_lidar",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "lidar_scan_key",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "lidar_scan",
                    },
                    {
                        setting_id = "lidar_radial_scan_key",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "radial_scan",
                    },
                    {
                        setting_id = "lidar_range_meters",
                        type = "numeric",
                        default_value = 3,
                        range = { 1, 30 },
                        decimals_number = 1,
                    },
                    {
                        setting_id = "lidar_auto_pulse",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "lidar_auto_pulse_interval",
                        type = "numeric",
                        default_value = 2,
                        range = { 1, 10 },
                        decimals_number = 1,
                    },
                },
            },
            {
                setting_id = "speedrun_group",
                type = "group",
                tab = mod:localize("tab_challenge"),
                sub_widgets = {
                    {
                        setting_id = "enable_speedrun_timer",
                        type = "checkbox",
                        default_value = false,
                    },
                },
            },
        },
    },
}
