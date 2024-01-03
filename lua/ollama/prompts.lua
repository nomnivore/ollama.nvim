local prompts = {}
local response_format = "Respond EXACTLY in this format:\n```$ftype\n<your code>\n```"

function prompts.generate_prompts(model, model_code)
	if model_code == nil then
		model_code = model
	end
	local prompts_table = {
		-- code based prompts
		Raw_Code = {
			prompt = "$input",
			input_label = ">",
			action = "display",
			model = model_code,
		},

		Ask_About_Code = {
			prompt = "I have a question about this: $input\n\n Here is the code:\n```$ftype\n$sel```",
			input_label = "Q",
			model = model_code,
		},

		Explain_Code = {
			prompt = "Explain this code:\n```$ftype\n$sel\n```",
			model = model_code,
		},

		Simplify_Code = {
			prompt = "Simplify the following $ftype code so that it is both easier to read and understand. "
				.. response_format
				.. "\n\n```$ftype\n$sel```",
			action = "replace",
			model = model_code,
		},

		Modify_Code = {
			prompt = "Modify this $ftype code in the following way: $input\n\n"
				.. response_format
				.. "\n\n```$ftype\n$sel```",
			action = "replace",
			model = model_code,
		},

		Generate_Code = {
			prompt = "Generate $ftype code that does the following: $input\n\n" .. response_format,
			action = "insert",
			model = model_code,
		},

		-- text based prompts
		Raw = {
			prompt = "$input",
			input_label = ">",
			action = "display",
			model = model,
		},

		Ask_About_Text = {
			prompt = "I have a question about this: $input\n\n Here is the text:\n\n$sel",
			input_label = "Q",
			model = model,
		},

		Explain_Text = {
			prompt = "Explain this text:\n\n$sel",
			model = model,
		},

		Simplify_Text = {
			prompt = "Simplify the following text so that it is both easier to read and understand. "
				.. "\n\n$sel",
			action = "replace",
			model = model,
		},

		Modify_Text = {
			prompt = "Modify this text in the following way: $input\n\n$sel",
			action = "replace",
			model = model,
		},

		Generate_Text = {
			prompt = "Generate text that does the following: $input\n\n",
			action = "insert",
			model = model,
		},
	}

	return prompts_table
end

return prompts
