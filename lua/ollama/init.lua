local M = {}

---@class Ollama.Prompt
---@field prompt string The prompt to send to the model.
--[[
		Replaces the following tokens:
		$input: The input from the user
		$sel:   The currently selected text
		$ftype: The filetype of the current buffer
		$fname: The filename of the current buffer
		$buf:   The contents of the current buffer
		$line:  The current line in the buffer
		$lnum:  The current line number in the buffer
--]]
---@field input_label string? The label to use for an input field
---@field action "display" | "display:float" | "insert" | "replace" | nil How to handle the output (default: display)
---@field model string? The model to use for this prompt (default: config.model)

---@class Ollama.Config
---@field model string? The default model to use
---@field prompts table<string, Ollama.Prompt>? A table of prompts to use for each model
---@field url string? The url to use to connect to the ollama server
---@field serve Ollama.Config.Serve? Configuration for the ollama server

---@class Ollama.Config.Serve
---@field on_start boolean? Whether to start the ollama server on startup
---@field command string? The command to use to start the ollama server
---@field args string[]? The arguments to pass to the ollama server

function M.default_config()
	return {
		model = "mistral",
		url = "http://127.0.0.1:11434",
		prompts = {
			Ask = {
				prompt = "I have a question: $input",
				input_label = "Q",
			},

			Explain_Code = {
				prompt = "Explain this code:\n```$ftype\n$sel\n```",
			},

			Raw = {
				prompt = "$input",
				input_label = ">",
			},
		},
		serve = {
			on_start = false,
			command = "ollama",
			args = { "serve" },
		},
	}
end

M.config = M.default_config()

local function get_prompts_list()
	local prompts = {}
	for name, _ in pairs(M.config.prompts) do
		table.insert(prompts, name)
	end
	return prompts
end

---@param prompt Ollama.Prompt
local function parse_prompt(prompt)
	local text = prompt.prompt
	if text:find("$input") then
		local input_prompt = prompt.input_label or "Ollama:"
		-- add space to end if not there
		if input_prompt:sub(-1) ~= " " then
			input_prompt = input_prompt .. " "
		end

		text = text:gsub("$input", vim.fn.input(input_prompt))
	end

	text = text:gsub("$ftype", vim.bo.filetype)
	text = text:gsub("$fname", vim.fn.expand("%:t"))
	text = text:gsub("$line", vim.fn.getline("."))
	text = text:gsub("$lnum", tostring(vim.fn.line(".")))

	if text:find("$buf") then
		local buf_text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		text = text:gsub("$buf", table.concat(buf_text, "\n"))
	end

	if text:find("$sel") then
		local sel_start = vim.fn.getpos("'<")
		local sel_end = vim.fn.getpos("'>")

		local sel_text = vim.api.nvim_buf_get_text(
			-- TODO: check if buf exists
			---@diagnostic disable-next-line: param-type-mismatch
			vim.fn.bufnr("%"),
			sel_start[2] - 1,
			sel_start[3] - 1,
			sel_end[2] - 1,
			sel_end[3] - 1,
			{}
		)
		text = text:gsub("$sel", table.concat(sel_text, "\n"))
	end

	return text
end

---@param callback function function to call with the selected prompt name
local function show_prompt_picker(callback)
	vim.ui.select(get_prompts_list(), {
		prompt = "Select a prompt:",
		format_item = function(item)
			return item:gsub("_", " ")
		end,
	}, function(selected, _)
		if selected then
			callback(selected)
		end
	end)
end

--- Query the ollama server with the given prompt
--- Ollama model used is specified in the config and optionally overridden by the prompt
---@param name string? The name of the prompt to use
function M.prompt(name)
	if not name or name:len() < 1 then
		show_prompt_picker(M.prompt)
		return
	end
	---@cast name string

	local prompt = M.config.prompts[name]
	if prompt == nil then
		vim.api.nvim_notify(("Prompt '%s' not found"):format(name), vim.log.levels.ERROR, { title = "Ollama" })
		return
	end

	local model = prompt.model or M.config.model

	-- curl and stream in response
	local tokens = {}
	local out_buf = vim.api.nvim_create_buf(false, true)

	-- show a rotating spinner while waiting for the response
	local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local curr_char = 1
	local timer = vim.loop.new_timer()
	timer:start(
		100,
		100,
		vim.schedule_wrap(function()
			vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, { "Generating... " .. spinner_chars[curr_char], "" })
			curr_char = curr_char % #spinner_chars + 1
		end)
	)

	---@type Job because we're streaming
	local job = require("plenary.curl").post(M.config.url .. "/api/generate", {
		body = vim.json.encode({
			model = model,
			prompt = parse_prompt(prompt),
			-- TODO: accept options in ollama spec such as temperature, etc
		}),
		stream = require("ollama.util").handle_stream(function(body)
			if timer:is_active() then
				timer:stop()
			end
			table.insert(tokens, body.response)
			vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, vim.split(table.concat(tokens), "\n"))

			if body.done then
				vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })
			end
		end),
	})

	if prompt.action == nil or vim.startswith(prompt.action, "display") then
		-- set some default text to show that the query is loading
		vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, { "Loading..." })

		local out_win = vim.api.nvim_open_win(out_buf, true, {
			relative = "editor",
			width = 160,
			height = 25,
			row = 10,
			col = 10,
			style = "minimal",
			border = "rounded",
			title = M.config.model,
			title_pos = "center",
		})

		-- vim.api.nvim_buf_set_name(out_buf, "OllamaOutput")
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = out_buf })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = out_buf })
		vim.api.nvim_set_option_value("wrap", true, { win = out_win })

		-- set some keybinds for the buffer
		vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

		vim.api.nvim_buf_attach(out_buf, false, {
			on_detach = function()
				job:shutdown()
			end,
		})
	end
end

---@class Ollama.ModelsApiResponseModel
---@field name string
---@field modified_at string
---@field size number
---@field digest string

---@class Ollama.ModelsApiResponse
---@field models Ollama.ModelsApiResponseModel[]

-- Query the ollama server for available models
local function query_models()
	local res = require("plenary.curl").get(M.config.url .. "/api/tags")

	local _, body = pcall(function()
		return vim.fn.json_decode(res.body)
	end)

	if body == nil then
		return {}
	end

	local models = {}
	for _, model in pairs(body.models) do
		table.insert(models, model.name)
	end

	return models
end

-- Method for choosing models
function M.choose_model()
	local models = query_models()

	if #models < 1 then
		vim.api.nvim_notify(
			"No models found. Is the ollama server running?",
			vim.log.levels.ERROR,
			{ title = "Ollama" }
		)
		return
	end

	vim.ui.select(models, {
		prompt = "Select a model:",
		format_item = function(item)
			if item == M.config.model then
				return item .. " (current)"
			end
			return item
		end,
	}, function(selected)
		if not selected then
			return
		end

		M.config.model = selected
		vim.api.nvim_notify(("Selected model '%s'"):format(selected), vim.log.levels.INFO, { title = "Ollama" })
	end)
end

-- Run the ollama server
function M.run_serve()
	local serve_job = require("plenary.job"):new({
		command = M.config.serve.command,
		args = M.config.serve.args,
		on_exit = function(_, code)
			if code == 1 then
				vim.api.nvim_notify(
					"Serve command exited with code 1. Is it already running?",
					vim.log.levels.ERROR,
					{ title = "Ollama" }
				)
			elseif code == 127 then
				vim.api.nvim_notify(
					"Serve command not found. Is it installed?",
					vim.log.levels.ERROR,
					{ title = "Ollama" }
				)
			end
		end,
	})
	serve_job:start()
	-- TODO: can we check if the server started successfully from this job?
end

--- Setup the plugin
---@param opts Ollama.Config configuration options
function M.setup(opts)
	---@diagnostic disable-next-line: assign-type-mismatch
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- add command
	vim.api.nvim_create_user_command("Ollama", function(arg)
		M.prompt(arg.args[1] or arg.args or nil)
	end, {
		nargs = "?",
		range = true,
		complete = function()
			return get_prompts_list()
		end,
		desc = "Query ollama server with the chosen prompt",
	})

	vim.api.nvim_create_user_command("OllamaModel", M.choose_model, {
		desc = "List and select from available ollama models",
	})

	if M.config.serve.on_start then
		M.run_serve()
	end
end

return M
