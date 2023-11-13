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
---@field action Ollama.PromptActionBuiltinEnum | Ollama.PromptAction | nil How to handle the output (default: config.action)
---@field model string? The model to use for this prompt (default: config.model)
---@field extract string? A `string.match` pattern to use for an Action to extract the output from the response [Insert/Replace] (default: "```$ftype\n(.-)```" )

---Built-in actions
---@alias Ollama.PromptActionBuiltinEnum "display" | "replace" | "insert" | "display_replace" | "display_insert"

-- Handles the output of a prompt. Custom Actions can be defined in lieu of a builtin.
---@alias Ollama.PromptAction table | Ollama.PromptActionFields
-- The function to call when a response is received from the server
-- `Job` is passed in when streaming is enabled
-- TODO: type the data because we can predict the shape
---@alias Ollama.PromptActionResponseCallback fun(data: table, job: Job?)

---@class Ollama.PromptActionFields
-- TODO: type the fn arg table
---@field fn fun(prompt: table): Ollama.PromptActionResponseCallback | false | nil
---@field opts Ollama.PromptAction.Opts?

---@class Ollama.PromptAction.Opts
---@field stream? boolean

---@class Ollama.Config
---@field model string? The default model to use
---@field prompts table<string, Ollama.Prompt | false>? A table of prompts to use for each model
---@field action Ollama.PromptActionBuiltinEnum | Ollama.PromptAction | nil How to handle prompt outputs when not specified by prompt
---@field url string? The url to use to connect to the ollama server
---@field serve Ollama.Config.Serve? Configuration for the ollama server

---@class Ollama.Config.Serve
---@field on_start boolean? Whether to start the ollama server on startup
---@field command string? The command to use to start the ollama server
---@field args string[]? The arguments to pass to the serve command
---@field stop_command string? The command to use to stop the ollama server
---@field stop_args string[]? The arguments to pass to the stop command

function M.default_config()
	return {
		model = "mistral",
		url = "http://127.0.0.1:11434",
		prompts = require("ollama.prompts"),
		serve = {
			on_start = false,
			command = "ollama",
			args = { "serve" },
			stop_command = "pkill",
			stop_args = { "-SIGTERM", "ollama" },
		},
	}
end

M.config = M.default_config()

---@alias Ollama.StatusEnum "WORKING" | "IDLE"

local jobs = {}
local jobs_length = 0

local function update_jobs_length()
	jobs_length = 0
	for _, _ in pairs(jobs) do
		jobs_length = jobs_length + 1
	end
end

---@param job Job
local function add_job(job)
	jobs[job.pid] = job
	update_jobs_length()
end

---@param job Job
local function del_job(job)
	jobs[job.pid] = nil
	update_jobs_length()
end

function M.cancel_all_jobs()
	for _, job in ipairs(jobs) do
		job:shutdown()
	end
end

---@type fun(): Ollama.StatusEnum
function M.status()
	if jobs_length > 0 then
		return "WORKING"
	end
	return "IDLE"
end

local function get_prompts_list()
	local prompts = {}
	for name, prompt in pairs(M.config.prompts) do
		if prompt then
			table.insert(prompts, name)
		end
	end
	return prompts
end

---@param prompt Ollama.Prompt
local function parse_prompt(prompt)
	local text = prompt.prompt
	if text:find("$input") then
		local input_prompt = prompt.input_label or "> "
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
		local sel_start = vim.fn.getpos("'<") or { 0, 0, 0, 0 }
		local sel_end = vim.fn.getpos("'>") or { 0, 0, 0, 0 }

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
	-- Get the list of prompts and sort them in alphabetical order
	local prompts = get_prompts_list()
	table.sort(prompts, function(a, b)
		return a:gsub("_", " ") < b:gsub("_", " ")
	end)

	-- Show the prompt picker with the sorted list of prompts
	vim.ui.select(prompts, {
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
--- When setting up a keymap, format the rhs like this to properly forward visual selection:
--- `:<c-u>lua require("ollama").prompt()`
function M.prompt(name)
	if not name or name:len() < 1 then
		show_prompt_picker(M.prompt)
		return
	end
	---@cast name string

	---@type Ollama.Prompt
	local prompt = M.config.prompts[name]
	if prompt == nil or prompt == false then
		vim.api.nvim_notify(("Prompt '%s' not found"):format(name), vim.log.levels.ERROR, { title = "Ollama" })
		return
	end

	local model = prompt.model or M.config.model
	-- resolve the action fn based on priority:
	-- 1. prompt.action (if it exists)
	-- 2. config.action (if it exists)
	-- 3. default action (display)

	-- builtin actions map to the actions.lua module

	local action = prompt.action or M.config.action
	if action == nil then
		action = "display"
	end

	if type(action) == "string" then
		action = require("ollama.actions")[action]
	end

	-- TODO: check if action is { fn, opts } or { fn = fn, opts = opts }

	local fn = action[1] or action.fn
	local opts = action[2] or action.opts

	local parsed_prompt = parse_prompt(prompt)

	local extract = prompt.extract or "```$ftype\n(.-)```"
	local parsed_extract = parse_prompt({ prompt = extract })

	-- this can probably be improved
	local cb = fn({
		model = model,
		prompt = prompt.prompt,
		input_label = prompt.input_label,
		extract = parsed_extract,
		action = action,
	})

	if not cb then
		return
	end

	if opts and opts.stream then
		local job = require("plenary.curl").post(M.config.url .. "/api/generate", {
			body = vim.json.encode({
				model = model,
				prompt = parsed_prompt,
				-- TODO: accept options in ollama spec such as temperature, etc
			}),
			stream = require("ollama.util").handle_stream(cb),
		})
		job:add_on_exit_callback(del_job)
		---@cast job Job because we're streaming

		add_job(job)
	else
		-- get response then send to cb

		local job = require("plenary.curl").post(M.config.url .. "/api/generate", {
			body = vim.json.encode({
				model = model,
				stream = false,
				prompt = parsed_prompt,
			}),
			callback = function(res)
				-- not the prettiest, but reuses the stream handler to process the response
				-- since it comes in the same format.
				require("ollama.util").handle_stream(cb)(nil, res.body)
			end,
		})
		job:add_on_exit_callback(del_job)

		add_job(job)
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
		return vim.json.decode(res.body)
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
---@param opts? { silent: boolean? }
function M.run_serve(opts)
	opts = opts or {}
	local serve_job = require("plenary.job"):new({
		command = M.config.serve.command,
		args = M.config.serve.args,
		on_exit = function(_, code)
			if code == 1 and not opts.silent then
				vim.schedule_wrap(vim.api.nvim_notify)(
					"Serve command exited with code 1. Is it already running?",
					vim.log.levels.WARN,
					{ title = "Ollama" }
				)
			elseif code == 127 and not opts.silent then
				vim.schedule_wrap(vim.api.nvim_notify)(
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

-- Stop the ollama server
---@param opts? { silent: boolean? }
function M.stop_serve(opts)
	opts = opts or {}
	require("plenary.job")
		:new({
			command = M.config.serve.stop_command,
			args = M.config.serve.stop_args,
			on_exit = function(_, code)
				if code == 1 and not opts.silent then
					vim.schedule_wrap(vim.api.nvim_notify)(
						"Server is already stopped",
						vim.log.levels.WARN,
						{ title = "Ollama" }
					)
				elseif code == 127 and not opts.silent then
					vim.schedule_wrap(vim.api.nvim_notify)(
						"Stop command not found. Is it installed?",
						vim.log.levels.ERROR,
						{ title = "Ollama" }
					)
				else
					vim.schedule_wrap(vim.api.nvim_notify)(
						"Ollama server stopped",
						vim.log.levels.INFO,
						{ title = "Ollama" }
					)
				end
			end,
		})
		:start()
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

	vim.api.nvim_create_user_command("OllamaServe", function()
		M.run_serve()
	end, { desc = "Start the ollama server" })
	vim.api.nvim_create_user_command("OllamaServeStop", function()
		M.stop_serve()
	end, { desc = "Start the ollama server" })

	if M.config.serve.on_start then
		M.run_serve()
	end
end

return M
