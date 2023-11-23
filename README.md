# ollama.nvim

A plugin for managing and integrating your [ollama](https://ollama.ai) workflows in neovim.

Designed to be flexible in configuration and extensible
with custom functionality.

## Features

- [x] Connects over HTTP, run your ollama server anywhere
- [x] Query and select from available models
- [x] Prompt the LLM with context from your buffer
- [x] Display, replace, or write your own actions for the response
- [x] Specify additional parameters for a prompt (temperature, top_k, etc)

### Planned / Ideas (implemented depending on interest)

- [ ] Download and manage models
- [ ] Clone or create models from [Modelfiles](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md)
- [ ] Chat

## Usage

`ollama.nvim` provides the following commands, which map to
methods exposed by the plugin:

- `Ollama`: Prompt the user to select a prompt to run.
- `OllamaModel`: Prompt the user to select a model to use as session default.
- `OllamaServe`: Start the ollama server.
- `OllamaServeStop`: Stop the ollama server.

## Installation

`ollama.nvim` uses `curl` to communicate with your ollama server over HTTP. Please ensure that `curl` is installed on your system.

Install using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "nomnivore/ollama.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },

  -- All the user commands added by the plugin
  cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },

  keys = {
    -- Sample keybind for prompt menu. Note that the <c-u> is important for selections to work properly.
    {
      "<leader>oo",
      ":<c-u>lua require('ollama').prompt()<cr>",
      desc = "ollama prompt",
      mode = { "n", "v" },
    },
    
    -- Sample keybind for direct prompting. Note that the <c-u> is important for selections to work properly.
    {
      "<leader>oG",
      ":<c-u>lua require('ollama').prompt('Generate_Code')<cr>",
      desc = "ollama Generate Code",
      mode = { "n", "v" },
    },
  },

  ---@type Ollama.Config
  opts = {
    -- your configuration overrides
  }
}
```

To get a fuzzy-finding Telescope prompt selector you can optionally install [`stevearc/dressing.nvim`](https://github.com/stevearc/dressing.nvim).

## Configuration

### Default Options

```lua
opts = {
  model = "mistral",
  url = "http://127.0.0.1:11434",
  serve = {
    on_start = false,
    command = "ollama",
    args = { "serve" },
    stop_command = "pkill",
    stop_args = { "-SIGTERM", "ollama" },
  },
  -- View the actual default prompts in ./lua/ollama/prompts.lua
  prompts = {
    Sample_Prompt = {
      prompt = "This is a sample prompt that receives $input and $sel(ection), among others.",
      input_label = "> ",
      model = "mistral",
      action = "display",
    }
  }
}
```

### Writing your own prompts

By default, `ollama.nvim` comes with a few prompts that are useful for most workflows.
However, you can also write your own prompts directly in your config, as shown above.

`prompts` is a dictionary of prompt names to prompt configurations. The prompt name is used in prompt selection menus
where you can select which prompt to run, where "Sample_Prompt" is shown as "Sample Prompt".

This dictionary accepts the following keys:

| Key         | Type                           | Description                                                                                                                                                                                                    |
| ----------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| prompt      | `string`                       | The prompt to send to the LLM. Can contain special tokens that are substituted with context before sending. See [Tokens](#tokens).                                                                             |
| model       | `string` (Optional)            | The model to use for the prompt. Defaults to the global `opts.model`.                                                                                                                                          |
| input_label | `string` (Optional)            | The label to use for the input prompt. Defaults to `"> "`.                                                                                                                                                     |
| action      | `string` or `table` (Optional) | The action to take with the response from the LLM. See [Actions](#actions). Defaults to "display".                                                                                                             |
| extract     | `string` (Optional)            | A Lua match pattern to extract from the response. Used only by certain actions. See [Extracting](#extracting). Set to `false` if you want to disable this step.                                                |
| options     | `table` (Optional)             | Additional model parameter overrides, such as temperature, listed in the documentation for the [Ollama Modelfile](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values) |
| system      | `string` (Optional)            | The system prompt to be used in the Modelfile template, if applicable. (overrides what's in the Modelfile)                                                                                                     |
| format      | `string` (Optional)            | The format to return a response in. Currently the only accepted value is "json"                                                                                                                                |

If you'd like to disable a prompt (such as one of the default ones), set the value of the prompt to `false`.

```lua
prompts = {
  Sample_Prompt = false
}
```

### Extracting

When using certain actions (or custom ones you write),
you may want to operate on a specific part of the response.
To do this, you can use the `extract` key in your prompt configuration.

````lua
extract = "```$ftype\n(.-)```"
````

`ollama.nvim` will parse the `extract` string the same way as a prompt, substituting tokens (see below). The parsed extract pattern
will then be sent to the action associated with the prompt.

### Tokens

Before sending the prompt, `ollama.nvim` will replace certain special tokens in
the prompt string with context in the following ways:

| Token  | Description                              |
| ------ | ---------------------------------------- |
| $input | Prompt the user for input.               |
| $sel   | The current or previous selection.       |
| $ftype | The filetype of the current buffer.      |
| $fname | The filename of the current buffer.      |
| $buf   | The full contents of the current buffer. |
| $line  | The current line in the buffer.          |
| $lnum  | The current line number in the buffer.   |

### Actions

`ollama.nvim` provides the following built-in actions:

- `display`: Stream and display the response in a floating window.
- `replace`: Replace the current selection with the response.
  - Uses the `extract` pattern to extract the response.
- `insert`: Insert the response at the current cursor line
  - Uses the `extract` pattern to extract the response.
- `display_replace`: Stream and display the response in a floating window, then replace the current selection with the response.
  - Uses the `extract` pattern to extract the response.
- `display_insert`: Stream and display the response in a floating window, then insert the response at the current cursor line.
  - Uses the `extract` pattern to extract the response.
- `display_prompt`: Append the parsed prompt and stream and display the response in a floating window.

Sometimes, you may need functionality that is not provided by
the built-in actions. In this case, you can write your own Custom Actions with the following interface:

```lua
---@type Ollama.PromptAction
action = {
  fn = function(prompt)
    -- This function is called when the prompt is selected
    -- just before sending the prompt to the LLM.
    -- Useful for setting up UI or other state.

    -- Return a function that will be used as a callback
    -- when a response is received.
    ---@type Ollama.PromptActionResponseCallback
    return function(body, job)
      -- body is a table of the json response
      -- body.response is the response text received

      -- job is the plenary.job object when opts.stream = true
      -- job is nil otherwise
    end

  end,

  opts = { stream = true } -- optional, default is false
}
```

Instead of returning a callback function, you can also return `false` or `nil`
to indicate that the prompt should be cancelled and not be sent to the LLM.
This can be useful for actions that require a selection or for other criteria not being met.

Actions can also be written without the table keys, like so:

```lua
action = {
  function(prompt)
    -- ...
    return function(body, job)
      -- ...
    end
  end,
  { stream = true }
}
```

### Status

`ollama.nvim` module exposes a `.status()` method for checking the status of the ollama server.
This is used to see if any jobs are currently running. It returns the type
`Ollama.StatusEnum` which is one of:

- `"IDLE"`: No jobs are running
- `"WORKING"`: One or more jobs are running

You can use this to display a prompt running status in your statusline.
Here is an example recipe for [lualine](https://github.com/nvim-lualine/lualine.nvim):

```lua
{
  "nvim-lualine/lualine.nvim",
  optional = true,

  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, {
      function()
        local status = require("ollama").status()

        if status == "IDLE" then
          return "󱙺" -- nf-md-robot-outline
        elseif status == "WORKING" then
          return "󰚩" -- nf-md-robot
        end
      end,
      cond = function()
        return package.loaded["ollama"] and require("ollama").status() ~= nil
      end,
    })
  end,
},
```

## Credits

- [ollama](https://github.com/jmorganca/ollama) for running LLMs locally
- [gen.nvim](https://github.com/David-Kunz/gen.nvim) for inspiration
