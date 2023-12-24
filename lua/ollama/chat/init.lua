local Chat = {}

local Popup = require("nui.popup")
local Layout = require("nui.layout")
local object = require("nui.object")

-- TODO: add functionality to save/load sessions (model/paramter info and chat history) in temp files
-- either under session storage or a temp/configurable directory
-- files can be named by timestamp by default

---@class ChatUi
-- constructor
---@field new fun(): ChatUi
-- views/ui
---@field views table<string, NuiLayout.Box>
---@field layout NuiLayout
---@field output NuiPopup
---@field input NuiPopup
---@field session_list NuiPopup
-- state
---@field is_open boolean
-- methods
---@field show fun()
---@field hide fun()
---@field close fun()
---@field toggle fun(): boolean
---@field open_session_list fun()
---@field send_message fun()
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

	self.session_list = Popup({
		border = {
			style = "rounded",
			text = {
				top = "Sessions",
				top_align = "center",
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

	-- populate session menu with fake data
	-- vim.api.nvim_buf_set_lines(self.session_list.bufnr, 0, -1, false, {
	-- 	"2023-01-01 12:00:00",
	-- 	"2023-01-01 15:22:54",
	-- 	"2023-02-15 08:45:30",
	-- 	"2023-03-05 18:30:12",
	-- 	"2023-04-10 10:12:45",
	-- 	"2023-05-20 14:55:21",
	-- 	"2023-06-08 22:17:33",
	-- 	"2023-07-03 16:40:09",
	-- 	"2023-08-12 09:28:56",
	-- 	"2023-09-25 20:03:40",
	-- 	"2023-10-18 11:50:25",
	-- 	"2023-11-30 19:14:08",
	-- 	"2023-12-15 13:36:42",
	-- })

	self.views = {
		main = Layout.Box({
			Layout.Box(self.output, { grow = 1 }),
			Layout.Box(self.input, { size = { height = 8 } }),
		}, { dir = "col", grow = 1 }),

		with_sessions = Layout.Box({
			Layout.Box({
				Layout.Box(self.output, { grow = 1 }),
				Layout.Box(self.input, { size = { height = 8 } }),
			}, { dir = "col", grow = 1 }),

			Layout.Box(self.session_list, { size = { width = 25 } }),
		}, { dir = "row" }),
	}

	self.layout = Layout({
		relative = "editor",
		size = { height = "80%", width = 95 },
		position = "50%",
	}, self.views.main)

	self.input:map("n", "<Tab>", function()
		vim.api.nvim_set_current_win(self.output.winid)
	end)
	self.output:map("n", "<Tab>", function()
		vim.api.nvim_set_current_win(self.input.winid)
	end)

	self.input:map("n", "<S-Tab>", function()
		self.open_session_list()
	end)

	self.input:map("n", "<CR>", function()
		self:send_message()
	end)
	self.is_open = false

	self.hide = function()
		self.layout:hide()
		self.is_open = false
	end
	self.show = function()
		self.layout:update(self.views.main)
		self.layout:show()
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

	self.open_session_list = function()
		self.layout:update(self.views.with_sessions)
	end

	-- hacking together a quick proof-of-concept
	---@type Ollama.ChatMessage[]
	local messages = {
		{
			role = "system",
			content = 'You are Ollama Chat, a helpful coding assistant. Please ensure all code blocks are properly formatted with triple backticks and a language identifier. For example:\n```js\nprint("Hello world!")\n```',
		},
	}
	local loading = false
	local ns_id = vim.api.nvim_create_namespace("ollama_chat")

	local scroll_to_bottom = true
	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = self.output.bufnr,
		callback = function()
			scroll_to_bottom = false
		end,
	})

	self.send_message = function()
		if loading then
			return
		end

		-- get message from input box
		local msg_lines = vim.api.nvim_buf_get_lines(self.input.bufnr, 0, -1, false)
		if #msg_lines == 0 then
			return
		end

		loading = true
		scroll_to_bottom = true

		local append_at = vim.api.nvim_buf_line_count(self.output.bufnr)

		vim.api.nvim_buf_set_lines(self.input.bufnr, 0, -1, false, {})

		-- vim.api.nvim_set_option_value("modifiable", true, { buf = self.output.bufnr })
		-- display user's message in output box
		local header_lines = { "# USER", "" }
		vim.list_extend(header_lines, msg_lines)
		vim.list_extend(header_lines, { "", "# ASSISTANT", "" })
		vim.api.nvim_buf_set_lines(self.output.bufnr, append_at, -1, false, header_lines)

		append_at = vim.api.nvim_buf_line_count(self.output.bufnr)
		local assistant_headline_nr = append_at - 2

		local spinner = require("ollama.util").show_spinner(
			self.output.bufnr,
			{ format = "# ASSISTANT %s", start_ln = assistant_headline_nr, end_ln = assistant_headline_nr + 1 }
		)

		---@type Ollama.ChatMessage
		local msg_obj = { role = "user", content = table.concat(msg_lines, "\n") }
		table.insert(messages, msg_obj)

		local tokens = {}

		require("ollama.api").chat(require("ollama").config.url, {
			model = require("ollama").config.model,
			messages = messages,
			stream = true,
		}, function(body, _)
			if body.message then
				table.insert(tokens, body.message.content)
				local lines = vim.split(table.concat(tokens), "\n")
				vim.api.nvim_buf_set_lines(self.output.bufnr, append_at, -1, false, lines)
				if scroll_to_bottom then
					-- scroll window to bottom
					for _, winnr in ipairs(vim.api.nvim_list_wins()) do
						if vim.api.nvim_win_get_buf(winnr) == self.output.bufnr then
							vim.api.nvim_win_set_cursor(winnr, { vim.api.nvim_buf_line_count(self.output.bufnr), 0 })
						end
					end
				end
			end
			if body.done then
				table.insert(messages, { role = "assistant", content = table.concat(tokens) })
				-- clear spinner
				spinner:stop()
				vim.api.nvim_buf_set_lines(
					self.output.bufnr,
					assistant_headline_nr,
					assistant_headline_nr + 1,
					false,
					{ "# ASSISTANT" }
				)
				-- set virtual text to show assistant is done
				vim.api.nvim_buf_set_extmark(self.output.bufnr, ns_id, assistant_headline_nr, 0, {
					virt_text = {
						{
							("in %ss"):format(
								string.format("%.2f", require("ollama.util").nano_to_seconds(body.total_duration))
							),
							"Comment",
						},
					},
					virt_text_pos = "eol",
				})

				-- vim.api.nvim_set_option_value("modifiable", false, { buf = self.output.bufnr })
				loading = false
			end
		end)
	end
end
---@type ChatUi?
local chatui

function Chat.open_or_toggle()
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

function Chat.toggle_session_list()
	if chatui ~= nil then
		chatui.open_session_list()
	end
end

return Chat
