local prompts = {
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

	Simplify_Code = {
		prompt = "Simplify the following $ftype code so that it is both easier to read and understand. Respond EXACTLY in this format:\n```$ftype\n<your code>\n```\n\n```$ftype\n$sel```",
		action = "replace",
		input_label = "",
	},

	Generate_Code = {
		prompt = "Generate $ftype code that does the following: $input\n\nRespond EXACTLY in this format:\n```$ftype\n<your code>\n```",
		action = "replace",
	},
}

return prompts
