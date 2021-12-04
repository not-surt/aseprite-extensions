local json = dofile("json.lua")

function init(plugin)
    local defaults = {loadOnOpen=false, storeOnClose=false}
    if plugin.preferences == nil then plugin.preferences = {} end
    for key, value in pairs(defaults) do
        if plugin.preferences[key] == nil then plugin.preferences[key] = value end
    end

    local function storeUserData()
    end
    local function loadUserData()
    end

    local function buildDialog()
        local dlg = Dialog("Palette Utils")

        dlg:separator{text="Palette Switcher"}
        dlg:combobox{id="palette", label="Palette", options={"Palette 1", "Palette 2"}, option="Palette 1", onchange=function()
        end}
        dlg:entry{id="name", label="Name", text="Palette 1", onchange=function()
        end}
        dlg:slider{id="paletteSlider", label="Palette", min=1, max=4, value=0, onchange=function()
        end}
        dlg:button{text="Save New", onclick=function()
        end}
        dlg:button{text="Save Over", onclick=function()
        end}
        dlg:button{text="Delete", onclick=function()
        end}
        dlg:button{text="Delete All", onclick=function()
        end}
        dlg:newrow()
        dlg:button{text="Previous Palette", onclick=function()
        end}
        dlg:button{text="Next Palette", onclick=function()
        end}
        dlg:newrow()
        dlg:button{text="Load from User Data", onclick=function()
            loadUserData()
        end}
        dlg:button{text="Store in User Data", onclick=function()
            storeUserData()
        end}

        dlg:separator{text="Selection"}
        dlg:check{id="selectPixels", text="Select Pixels", selected=false}
        dlg:number{id="distanceThreshold", label="Distance Threshold", text=0}
        dlg:button{text="Select Similar", onclick=function()
        end}
        dlg:number{id="frequencyThreshold", label="Frequency Threshold", text=0}
        dlg:button{text="Select Infrequent", onclick=function()
        end}
        dlg:number{id="leastUsedCount", label="Least Used Count", text=0}
        dlg:button{text="Select Least Used", onclick=function()
        end}

        dlg:separator{text="Merging"}
        dlg:combobox{id="mergeMode", label="Merge Mode", options={"Most Frequent", "Weighted Average"}, option="Weighted Average"}
        dlg:button{text="Merge Selected", onclick=function()
        end}

        dlg:separator{text="Reduction"}
        dlg:combobox{id="reductionMode", label="Reduction Mode", options={"Replace With Nearest", "Weighted Average With Nearest"}, option="Replace With Nearest"}
        dlg:number{id="reduceToSize", label="Reduce to Size", text=16}
        dlg:button{text="Merge Selected", onclick=function()
        end}

        dlg:separator{text="Generation"}
        dlg:button{text="Add All Colours From Selection", onclick=function()
        end}
        dlg:button{text="Add Colour From Selection Average", onclick=function()
        end}

        dlg:separator{text="Misc."}
        dlg:button{text="Histogram", onclick=function()
        end}

        dlg:show{wait=false}
    end

    plugin:newCommand{
        id="Palette Utils",
        title="Palette Utils...",
        group="edit_fx",
        onclick=function()
            if plugin.preferences.loadOnOpen then
                loadUserData()
            end
            buildDialog()
        end
    }
end