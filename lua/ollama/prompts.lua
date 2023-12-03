local response_format = "Respond EXACTLY in this format:\n```$ftype\n<your code>\n```"

local prompts = {
	Ask_About_Code = {
		prompt = "I have a question about this: $input\n\n Here is the code:\n```$ftype\n$sel```",
		input_label = "Q",
	},

	Explain_Code = {
		prompt = "Explain this code:\n```$ftype\n$sel\n```",
	},

	-- basically "no prompt"
	Raw = {
		prompt = "$input",
		input_label = ">",
		action = "display",
	},

	Simplify_Code = {
		prompt = "Simplify the following $ftype code so that it is both easier to read and understand. "
			.. response_format
			.. "\n\n```$ftype\n$sel```",
		action = "replace",
	},

	Modify_Code = {
		prompt = "Modify this $ftype code in the following way: $input\n\n"
			.. response_format
			.. "\n\n```$ftype\n$sel```",
		action = "replace",
	},

	Generate_Code = {
		prompt = "Generate $ftype code that does the following: $input\n\n" .. response_format,
		action = "insert",
	},
}

return prompts
