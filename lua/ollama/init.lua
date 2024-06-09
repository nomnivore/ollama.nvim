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
---@field extract string | false | nil A `string.match` pattern to use for an Action to extract the output from the response (Insert/Replace) (default: "```$ftype\n(.-)```" )
---@field options Ollama.PromptOptions? additional model parameters, such as temperature, listed in the documentation for the [Modelfile](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)
---@field system string? The SYSTEM instruction specifies the system prompt to be used in the Modelfile template, if applicable. (overrides what's in the Modelfile)
---@field format "json"? the format to return a response in. Currently the only accepted value is json

-- Additional options for the prompt, as defined in `Modelfile` docs
-- Please check the official documentation for the latest information, as this may be out of date.
---@class Ollama.PromptOptions
---@field mirostat integer? Enable Mirostat sampling for controlling perplexity. (default: 0, 0 = disabled, 1 = Mirostat, 2 = Mirostat 2.0)
---@field mirostat_eta float? Influences how quickly the algorithm responds to feedback from the generated text. A lower learning rate will result in slower adjustments, while a higher learning rate will make the algorithm more responsive. (Default: 0.1)
---@field mirostat_tau float? Controls the balance between coherence and diversity of the output. A lower value will result in more focused and coherent text. (Default: 5.0)
---@field num_ctx integer? Sets the size of the context window used to generate the next token. (Default: 2048)
---@field num_gqa integer? The number of GQA groups in the transformer layer. Required for some models, for example, it is 8 for llama2:70b.
---@field num_gpu integer? The number of layers to send to the GPU(s). On macOS, it defaults to 1 to enable metal support, 0 to disable.
---@field num_thread integer? Sets the number of threads to use during computation. By default, Ollama will detect this for optimal performance. It is recommended to set this value to the number of physical CPU cores your system has (as opposed to the logical number of cores).
---@field repeat_last_n integer? Sets how far back for the model to look back to prevent repetition. (Default: 64, 0 = disabled, -1 = num_ctx)
---@field repeat_penalty float? Sets how strongly to penalize repetitions. A higher value (e.g., 1.5) will penalize repetitions more strongly, while a lower value (e.g., 0.9) will be more lenient. (Default: 1.1)
---@field temperature float? The temperature of the model. Increasing the temperature will make the model answer more creatively. (Default: 0.8)
---@field seed integer? Sets the random number seed to use for generation. Setting this to a specific number will make the model generate the same text for the same prompt. (Default: 0)
---@field stop string? Sets the stop sequences to use. When this pattern is encountered, the LLM will stop generating text and return. Multiple stop patterns may be set by specifying multiple separate stop parameters in a modelfile.
---@field tfs_z float? Tail free sampling is used to reduce the impact of less probable tokens from the output. A higher value (e.g., 2.0) will reduce the impact more, while a value of 1.0 disables this setting. (Default: 1)
---@field num_predict integer? Maximum number of tokens to predict when generating text. (Default: 128, -1 = infinite generation, -2 = fill context)
---@field top_k integer? Reduces the probability of generating nonsense. A higher value (e.g. 100) will give more diverse answers, while a lower value (e.g. 10) will be more conservative. (Default: 40)
---@field top_p float? Works together with top-k. A higher value (e.g., 0.95) will lead to more diverse text, while a lower value (e.g., 0.5) will generate more focused and conservative text. (Default: 0.9)

---Built-in actions
---@alias Ollama.PromptActionBuiltinEnum "display" | "replace" | "insert" | "display_replace" | "display_insert" | "display_prompt"

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
    local original_text = text

    if original_text:find("$input") then
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

    local buf_text = nil
    local before_text = nil
    local after_text = nil
    local has_buf = original_text:find("$buf")
    local has_before = original_text:find("$before")
    local has_after = original_text:find("$after")
    if has_buf or has_before or has_after then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        buf_text = table.concat(lines, "\n")

        local row, column = unpack(vim.api.nvim_win_get_cursor(0))
        local before_lines = {}
        local after_lines = {}
        for i, line in ipairs(lines) do
            if i < row then
                table.insert(before_lines, line)
            elseif i > row then
                table.insert(after_lines, line)
            else
                table.insert(before_lines, line:sub(1, column - 1))
                table.insert(after_lines, line:sub(column))
            end
        end

        before_text = table.concat(before_lines, "\n")
        after_text = table.concat(after_lines, "\n")
    end

    local sel_text = nil
    if original_text:find("$sel") then
        local sel_start = vim.fn.getpos("'<") or { 0, 0, 0, 0 }
        local sel_end = vim.fn.getpos("'>") or { 0, 0, 0, 0 }

        -- address inconsistencies between visual and visual line mode
        local mode = vim.fn.visualmode()
        if mode == "V" then
            sel_end[3] = sel_end[3] - 1
        end

        local buf_nr = vim.fn.bufnr("%")

        if buf_nr ~= -1 then
            local sel_buf_text = vim.api.nvim_buf_get_text(
            ---@diagnostic disable-next-line: param-type-mismatch
                buf_nr,
                sel_start[2] - 1,
                sel_start[3] - 1,
                sel_end[2] - 1,
                sel_end[3], -- end_col is exclusive
                {}
            )
            sel_text = table.concat(sel_buf_text, "\n")
        else
            sel_text = "No Buffer Found"
        end
    end

    local function replace_selector(match)
        if match == "$buf" then
            return buf_text
        elseif match == "$sel" then
            return sel_text
        elseif match == "$before" then
            return before_text
        elseif match == "$after" then
            return after_text
        else
            return match
        end
    end

    return text:gsub("(%$[%w_]+)", replace_selector)
end

---@param callback function function to call with the selected prompt name
local function show_prompt_picker(callback)
	-- Get the list of prompts and sort them in alphabetical order
	local prompts = get_prompts_list()
	table.sort(prompts, function(a, b)
		return a < b
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

	local fn = action[1] or action.fn
	local opts = action[2] or action.opts

	local parsed_prompt = parse_prompt(prompt)

	local extract = prompt.extract
	if extract == nil then
		extract = "```$ftype\n(.-)```"
	end
	local parsed_extract = nil
	if extract then
		parsed_extract = parse_prompt({ prompt = extract })
	end

	-- this can probably be improved
	local cb = fn({
		model = model,
		prompt = prompt.prompt,
		input_label = prompt.input_label,
		extract = parsed_extract,
		action = action,
		parsed_prompt = parsed_prompt,
	})

	if not cb then
		return
	end

	local stream = opts and opts.stream or false
	local stream_called = false

	local job = require("plenary.curl").post(M.config.url .. "/api/generate", {
		body = vim.json.encode({
			model = model,
			prompt = parsed_prompt,
			stream = stream,
			system = prompt.system,
			format = prompt.format,
			options = prompt.options,
		}),
		stream = function(_, chunk, job)
			if stream then
				stream_called = true
				require("ollama.util").handle_stream(cb)(_, chunk, job)
			end
		end,
	})
	---@param j Job
	job:add_on_exit_callback(function(j)
		if stream_called then
			return
		end

		if j.code ~= 0 then
			vim.schedule_wrap(vim.api.nvim_notify)(
				("Connection error (Code %s)"):format(tostring(j.code)),
				vim.log.levels.ERROR,
				{ title = "Ollama" }
			)
			return
		end

		-- not the prettiest, but reuses the stream handler to process the response
		-- since it comes in the same format.
		require("ollama.util").handle_stream(cb)(nil, j:result()[1])

		-- if res.body is like { error = "..." } then it should
		-- be handled in the handle_stream method
	end)
	job:add_on_exit_callback(del_job)

	add_job(job)
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
			if opts.silent then
				return
			end
			-- 1 = `ollama serve` already running
			-- 125 = docker name conflict (already running)
			-- `docker start` returns 0 if already running, not sure how to catch that case
			if code == 1 or code == 125 then
				vim.schedule_wrap(vim.api.nvim_notify)(
					"Serve command exited with code 1. Is it already running?",
					vim.log.levels.WARN,
					{ title = "Ollama" }
				)
			elseif code == 127 then
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
