local api = {}

---@class Ollama.ModelsApiResponseModel
---@field name string
---@field modified_at string
---@field size number
---@field digest string

---@class Ollama.ModelsApiResponse
---@field models Ollama.ModelsApiResponseModel[]

---@class Ollama.CompletionParams
---@field model string the model name
---@field prompt string? the prompt to `/generate` a response for
---@field images string[]? base64-encoded image data, for multimodal models
---@field format "json" | nil
---@field options Ollama.PromptOptions?
---@field system string?
---@field template string?
---@field context integer[]? context param returned from a previous `/generate`, for short conversational memory
---@field stream boolean? whether to stream the response or not (defaults to false)
---@field raw boolean?
---@field messages Ollama.ChatMessage[]? message including history for `/chat` endpoints

---@class Ollama.ChatMessage
---@field role "system" | "user" | "assistant"
---@field content string
---@field images string[]? base64-encoded image data, for multimodal models

---Query the ollama server for available models
---@param base_url string
function api.list_models(base_url)
	local res = require("plenary.curl").get(base_url .. "/api/tags")

	local _, body = pcall(function()
		return vim.json.decode(res.body)
	end)

	if body == nil then
		return {}
	end

	---@cast body Ollama.ModelsApiResponse

	---@type string[]
	local models = {}
	for _, model in pairs(body.models) do
		table.insert(models, model.name)
	end

	return models
end

---@param body Ollama.CompletionParams
function api.generate(base_url, body, cb)
	body = body or {}
	body.stream = body.stream or false

	local stream_called = false

	local job = require("plenary.curl").post(base_url .. "/api/generate", {
		body = vim.json.encode(body),
		stream = function(_, chunk, job)
			if body.stream then
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

	return job
end

---near duplicate of generate method, but with a different endpoint
---and I expect to need to make some chat-specific changes down the road
---@param body Ollama.CompletionParams
function api.chat(base_url, body, cb)
	body = body or {}

	local stream_called = false

	local job = require("plenary.curl").post(base_url .. "/api/chat", {
		body = vim.json.encode(body),
		stream = function(_, chunk, job)
			if body.stream then
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

	return job
end

return api
