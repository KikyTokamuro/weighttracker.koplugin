local DataStorage = require("datastorage")
local DateTimeWidget = require("ui/widget/datetimewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local _ = require("gettext")
local T = require("ffi/util").template

local function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local tmp = string.rep("  ", depth)

    if type(val) == "table" then
        local s = "{\n"
        for k, v in pairs(val) do
            s = s .. tmp .. "  [" .. serializeTable(k) .. "] = " .. serializeTable(v, nil, skipnewlines, depth + 1) .. ",\n"
        end
        return s .. tmp .. "}"
    elseif type(val) == "string" then
        return string.format("%q", val)
    else
        return tostring(val)
    end
end

local WeightTracker = WidgetContainer:extend{
    name = "weighttracker",
    is_doc_only = false,
    data_file = DataStorage:getDataDir() .. "/weight_data.lua",
    weight_data = {},
}

function WeightTracker:init()
    self:loadData()
    self.ui.menu:registerToMainMenu(self)
end

function WeightTracker:loadData()
    local f, err = loadfile(self.data_file)

    if f then
        local ok, data = pcall(f)

        if ok and type(data) == "table" then
            self.weight_data = data
            table.sort(self.weight_data, function(a, b) return a.date < b.date end)
        else
            self.weight_data = {}
        end
    else
        self.weight_data = {}
    end
end

function WeightTracker:saveData()
    local file = io.open(self.data_file, "w")

    if file then
        file:write("return " .. serializeTable(self.weight_data))
        file:close()
    end
end

function WeightTracker:addToMainMenu(menu_items)
    menu_items.weight_tracker = {
        text = _("Weight Tracker"),
        sorting_hint = "more_tools",
        sub_item_table = {
            { text = _("Add weight measurement"), callback = function() self:showAddWeightDialog() end },
            { text = _("View statistics"), callback = function() self:showStatistics() end },
            { text = _("View all measurements"), callback = function() self:showAllMeasurements() end },
            { text = _("Clear all data"), callback = function() self:confirmClearData() end, separator = true },
        }
    }
end

function WeightTracker:showAddWeightDialog()
    local current_date = os.date("*t")
    local selected_date = { year = current_date.year, month = current_date.month, day = current_date.day }

    local function getDescription()
        local date_str = self:formatDateForDisplay(selected_date)
        return T(_("Enter your weight (kg)\nDate: %1"), date_str)
    end

    self.add_weight_dialog = InputDialog:new{
        title = _("Add weight measurement"),
        input = "",
        input_type = "number",
        input_hint = "70.5",
        description = getDescription(),
        buttons = {
            {
                { text = _("Change date"), callback = function()
                    self:showDateDialog(selected_date, function(new_date)
                        selected_date = new_date
                        UIManager:close(self.add_weight_dialog)
                        self:showAddWeightDialogWithDate(new_date)
                    end)
                end },
                { text = _("Cancel"), callback = function() 
                    UIManager:close(self.add_weight_dialog) 
                end },
                { text = _("Save"), callback = function()
                    local weight_str = self.add_weight_dialog:getInputText()
                    local weight_num = tonumber(weight_str)

                    if weight_num and weight_num > 0 then
                        UIManager:close(self.add_weight_dialog)
                        self:saveWeightMeasurement(weight_num, selected_date)
                    else
                        UIManager:show(InfoMessage:new{ text = _("Please enter a valid weight") })
                    end
                end },
            }
        }
    }

    UIManager:show(self.add_weight_dialog)
    self.add_weight_dialog:onShowKeyboard()
end

function WeightTracker:showAddWeightDialogWithDate(selected_date)
    local function getDescription()
        local date_str = self:formatDateForDisplay(selected_date)
        return T(_("Enter your weight (kg)\nDate: %1"), date_str)
    end

    self.add_weight_dialog = InputDialog:new{
        title = _("Add weight measurement"),
        input = "",
        input_type = "number",
        input_hint = "70.5",
        description = getDescription(),
        buttons = {
            {
                { text = _("Change date"), callback = function()
                    self:showDateDialog(selected_date, function(new_date)
                        selected_date = new_date
                        UIManager:close(self.add_weight_dialog)
                        self:showAddWeightDialogWithDate(new_date)
                    end)
                end },
                { text = _("Cancel"), callback = function() 
                    UIManager:close(self.add_weight_dialog) 
                end },
                { text = _("Save"), callback = function()
                    local weight_str = self.add_weight_dialog:getInputText()
                    local weight_num = tonumber(weight_str)
                
                    if weight_num and weight_num > 0 then
                        UIManager:close(self.add_weight_dialog)
                        self:saveWeightMeasurement(weight_num, selected_date)
                    else
                        UIManager:show(InfoMessage:new{ text = _("Please enter a valid weight") })
                    end
                end },
            }
        }
    }
    UIManager:show(self.add_weight_dialog)
    self.add_weight_dialog:onShowKeyboard()
end

function WeightTracker:showDateDialog(current_date, callback)
    local widget = DateTimeWidget:new{
        year = current_date.year,
        month = current_date.month,
        day = current_date.day,
        ok_text = _("Select"),
        title_text = _("Select measurement date"),
        callback = function(time)
            callback(time)
            UIManager:close(widget)
        end
    }
    UIManager:show(widget)
end

function WeightTracker:formatDateForDisplay(date)
    if type(date) == "table" then
        return string.format("%02d.%02d.%04d", date.day, date.month, date.year)
    else
        local y, m, d = date:match("(%d+)-(%d+)-(%d+)")
        return string.format("%02d.%02d.%04d", tonumber(d), tonumber(m), tonumber(y))
    end
end

function WeightTracker:formatDateISO(date_table)
    return string.format("%04d-%02d-%02d", date_table.year, date_table.month, date_table.day)
end

function WeightTracker:saveWeightMeasurement(weight, date_table)
    local date_str = self:formatDateISO(date_table)
    
    for i = #self.weight_data, 1, -1 do
        if self.weight_data[i].date == date_str then
            table.remove(self.weight_data, i)
        end
    end
    
    table.insert(self.weight_data, { date = date_str, weight = weight })
    table.sort(self.weight_data, function(a, b) return a.date < b.date end)
    self:saveData()
    
    UIManager:show(InfoMessage:new{
        text = T(_("Weight saved: %1 kg on %2"), string.format("%.1f", weight), self:formatDateForDisplay(date_str))
    })
end

function WeightTracker:showStatistics()
    if #self.weight_data == 0 then
        UIManager:show(InfoMessage:new{ text = _("No weight data available") })
        return
    end
    
    local first = self.weight_data[1]
    local last = self.weight_data[#self.weight_data]
    local change = last.weight - first.weight
    local change_text

    if change > 0 then
        change_text = T(_("Gained: +%1 kg"), string.format("%.1f", change))
    elseif change < 0 then
        change_text = T(_("Lost: %1 kg"), string.format("%.1f", math.abs(change)))
    else
        change_text = _("No change")
    end
    
    local stats = {
        T(_("First measurement: %1 kg on %2"), string.format("%.1f", first.weight), self:formatDateForDisplay(first.date)),
        T(_("Last measurement: %1 kg on %2"), string.format("%.1f", last.weight), self:formatDateForDisplay(last.date)),
        change_text,
        T(_("Total measurements: %1"), #self.weight_data)
    }
    
    UIManager:show(InfoMessage:new{ text = table.concat(stats, "\n") , title = _("Weight Statistics") })
end

function WeightTracker:showAllMeasurements()
    if #self.weight_data == 0 then
        UIManager:show(InfoMessage:new{ text = _("No weight data available") })
        return
    end
    local txt = _("All measurements:\n")
    local limit = 20
    
    local end_index = #self.weight_data
    local start_index = math.max(1, end_index - limit + 1)
    
    for i = end_index, start_index, -1 do
        local entry = self.weight_data[i]
        txt = txt .. string.format("%s: %.1f kg\n", self:formatDateForDisplay(entry.date), entry.weight)
    end
    
    if #self.weight_data > limit then
        txt = txt .. T(_("... and %1 more measurements"), #self.weight_data - limit)
    end
    
    UIManager:show(InfoMessage:new{ text = txt, title = _("All Measurements") })
end

function WeightTracker:confirmClearData()
    if #self.weight_data == 0 then
        UIManager:show(InfoMessage:new{ text = _("No data to clear") })
        return
    end
    
    self.confirm_box = ConfirmBox:new{
        text = _("Are you sure you want to delete all weight data?"),
        ok_text = _("Delete all"),
        ok_callback = function()
            self.weight_data = {}
            self:saveData()
            UIManager:close(self.confirm_box)
            UIManager:show(InfoMessage:new{ text = _("All data has been deleted") })
        end
    }
    
    UIManager:show(self.confirm_box)
end

return WeightTracker