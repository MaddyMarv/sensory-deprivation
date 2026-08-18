return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`sensory_deprivation` encountered an error loading the Darktide Mod Framework.")

        new_mod("sensory_deprivation", {
            mod_script       = "sensory_deprivation/scripts/mods/sensory_deprivation/sensory_deprivation",
            mod_data         = "sensory_deprivation/scripts/mods/sensory_deprivation/sensory_deprivation_data",
            mod_localization = "sensory_deprivation/scripts/mods/sensory_deprivation/sensory_deprivation_localization",
        })
    end,
    packages = {},
}
