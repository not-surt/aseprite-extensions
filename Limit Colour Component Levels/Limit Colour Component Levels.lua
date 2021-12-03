----------------------------------------------------------------------
-- Limit Colour Component Levels
----------------------------------------------------------------------

local function log2(value)
    return math.log(value) / math.log(2)
end

local function clamp(min, max, value)
    return math.max(min, math.min(max, value))
end

local components = {"red", "green", "blue", "alpha"}
local componentLabels = {"Red", "Green", "Blue", "Alpha"}

local function levelComponent(levels, value, range)
    local levelStep = 256 / levels
    local level = clamp(0, levels - 1, math.floor(value / levelStep))
    local rangeFunc = {
        ["Stretch"] = function() return level * (256 / (levels - 1)) end,
        ["Lower"] = function() return level * levelStep end,
        ["Upper"] = function() return level * levelStep + levelStep - 1 end,
        ["Middle"] = function() return level * levelStep + (levelStep / 2) end,
    }
    return clamp(0, 255, math.floor(rangeFunc[range]()))
end

local function levelColour(levels, colour, range)
    local outColour = Color()
    for _, component in pairs(components) do
        if levels[component] ~= 0 then
            outColour[component] = levelComponent(levels[component], colour[component], range)
        else
            outColour[component] = colour[component]
        end
    end
    return outColour
end

local function applyLevels(levels, range)
    if app.activeSprite.colorMode == ColorMode.INDEXED then
        local palette = app.activeSprite.palettes[1]
        for i = 0, #palette-1 do
            local colour = palette:getColor(i)
            colour = levelColour(levels, colour, range)
            palette:setColor(i, colour)
        end
    elseif app.activeSprite.colorMode == ColorMode.RGB then
        local img = app.activeCel.image:clone()
        for it in img:pixels() do
            local pixelValue = it()
            local colour = Color(pixelValue)
            local outColour = levelColour(levels, colour, range)
            it(outColour.rgbaPixel)
        end
        app.activeCel.image = img
    end
end

function init(plugin)
    local prefs = plugin.preferences
    if prefs.levels == nil then
        prefs.scale = "Number"
        prefs.range = "Stretch"
        prefs.levels = {red=4, green=4, blue=4, alpha=0}
    end

    local dlg = Dialog("Limit Colour Component Levels")
    local function dlgScaleChanged()
        for _, component in pairs(components) do
            if dlg.data[component] ~= 0 then
                local value
                if dlg.data.scale == "Number" then
                    value=math.floor(2^dlg.data[component])
                else
                    value=math.ceil(log2(dlg.data[component]))
                end
                dlg:modify{id=component, text=value}
            end
        end
    end
    dlg:combobox{id="scale", label="Scale", options={"Number", "Bits"}, onchange=dlgScaleChanged}
    dlg:combobox{id="range", label="Range", options={"Stretch", "Lower", "Upper", "Middle"}}
    for i = 1, #components do
        dlg:number{id=components[i], label=componentLabels[i], decimals=0}
    end
    dlg:separator{}
    local function dlgApplyLevels()
        local levels
        if prefs.scale == "Number" then
            levels = prefs.levels
        else
            levels = {}
            for k, v in pairs(prefs.levels) do
                if prefs.levels[k] ~= 0 then
                    levels[k] = 2^v
                else
                    levels[k] = 0
                end
            end
        end
        app.transaction(function() applyLevels(levels, prefs.range) end)
        app.refresh()
    end
    local function dlgOk()
        prefs.scale = dlg.data.scale
        prefs.range = dlg.data.range
        prefs.levels = {}
        for _, component in pairs(components) do
            prefs.levels[component] = dlg.data[component]
        end
        dlgApplyLevels()
        dlg:close()
    end
    dlg:button{text="Ok", onclick=dlgOk}
    local function dlgCancel()
        dlg:close()
    end
    dlg:button{text="Cancel", onclick=dlgCancel}
    
    plugin:newCommand{
        id="LimitColourComponentLevels",
        title="Set Limit Colour Component Levels...",
        group="edit_fx",
        onclick=function()
            dlg:modify{id="scale", option=prefs.scale}
            dlg:modify{id="range", option=prefs.range}
            for _, component in pairs(components) do
                dlg:modify{id=component, text=prefs.levels[component]}
            end
            dlg:show{wait=false}
        end
    }
    plugin:newCommand{
        id="LimitColourComponentLevelsReapply",
        title="Reapply Limit Colour Component Levels",
        group="edit_fx",
        onclick=dlgApplyLevels
    }
end

function exit(plugin)
end
