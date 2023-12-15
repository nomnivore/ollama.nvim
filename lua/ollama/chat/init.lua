local Chat = {}

local unpack = table.unpack or unpack

local Popup = require("nui.popup")
local Layout = require("nui.layout")
local object = require("nui.object")

---@class ChatUi
---@field new fun(): ChatUi
---@field layout NuiLayout
---@field output NuiPopup
---@field input NuiPopup
---@field is_open boolean
---@field show fun()
---@field hide fun()
---@field close fun()
---@field toggle fun(): boolean
local ChatUi = object("ChatUi")

function ChatUi.init(self)
	self.output = Popup({
		border = {
			style = "rounded",
			text = {
				top = "Ollama Chat",
				top_align = "center",
				bottom = "<Tab> toggle focus",
				bottom_align = "right",
			},
		},
		buf_options = {
			buftype = "nofile",
			filetype = "markdown",
		},
		win_options = {
			wrap = true,
			linebreak = true,
		},
	})

	self.input = Popup({
		enter = true,
		border = {
			style = "rounded",
			text = {
				top = "Input",
				top_align = "left",
			},
		},
		buf_options = {
			buftype = "nofile",
			filetype = "markdown",
		},
		win_options = {
			wrap = true,
			linebreak = true,
		},
	})

	self.layout = Layout(
		{
			relative = "editor",
			size = { height = "80%", width = 95 },
			position = "50%",
		},
		Layout.Box({
			Layout.Box(self.output, { grow = 1 }),
			Layout.Box(self.input, { size = { height = 8 } }),
		}, { dir = "col" })
	)

	self.input:map("n", "<Tab>", function()
		vim.api.nvim_set_current_win(self.output.winid)
	end)
	self.output:map("n", "<Tab>", function()
		vim.api.nvim_set_current_win(self.input.winid)
	end)

	self.input:map("n", "<CR>", function()
		local lines = vim.api.nvim_buf_get_lines(self.input.bufnr, 0, -1, false)
		vim.api.nvim_buf_set_lines(self.input.bufnr, 0, -1, false, {})

		vim.api.nvim_buf_set_lines(self.output.bufnr, -1, -1, false, { "", unpack(lines) })
	end)

	self.is_open = false

	self.hide = function()
		self.layout:hide()
		self.input:hide()
		self.output:hide()
		self.is_open = false
	end
	self.show = function()
		self.layout:show()
		self.input:show()
		self.output:show()
		self.is_open = true
	end

	self.toggle = function()
		if self.is_open then
			self:hide()
		else
			self:show()
		end

		return self.is_open
	end

	self.close = function()
		vim.inspect(self)
		self.layout:unmount()
	end
end

---@type ChatUi?
local chatui

function Chat.open()
	if chatui == nil then
		chatui = ChatUi:new()
		chatui:show()
	else
		chatui:toggle()
	end
end

function Chat.close()
	if chatui ~= nil then
		chatui:close()
		chatui = nil
	end
end

return Chat
