# ollama.nvim

A plugin for managing and integrating your [ollama](https://ollama.ai) workflows in neovim.

Designed to be flexible in configuration and extensible
with custom functionality.

## Features

- [x] Connects over HTTP, run your ollama server anywhere
- [x] Query and select from available models
- [x] Prompt the LLM with context from your buffer
- [x] Display, replace, or write your own actions for the response

- [ ] Specify additional parameters for a prompt (temperature, top_k, etc)
- [ ] Download and manage models?
- [ ] Clone or create models from [Modelfiles](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md)?
- [ ] Chat??

## Usage

`ollama.nvim` provides the following commands, which map to
methods exposed by the plugin:

- `Ollama`: Prompt the user to select a prompt to run.
- `OllamaModel`: Prompt the user to select a model to use as session default.
- `OllamaServe`: Start the ollama server.
- `OllamaServeStop`: Stop the ollama server.

## Installation

Install using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "nomnivore/ollama.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },

  -- All the user commands added by the plugin
  cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },

  -- Sample keybind for prompting. Note that the <c-u> is important for selections to work properly.
  keys = {
    {
      "<leader>oo",
      ":<c-u>lua require('ollama').prompt()<cr>",
      desc = "ollama prompt",
      mode = { "n", "v" },
    },
  },

  ---@type Ollama.Config
  opts = {
    -- your configuration overrides
  }
}
```

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

| Key         | Type                           | Description                                                                                                                        |
| ----------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| prompt      | `string`                       | The prompt to send to the LLM. Can contain special tokens that are substituted with context before sending. See [Tokens](#tokens). |
| model       | `string` (Optional)            | The model to use for the prompt. Defaults to the global `opts.model`.                                                              |
| input_label | `string` (Optional)            | The label to use for the input prompt. Defaults to `"> "`.                                                                         |
| action      | `string` or `table` (Optional) | The action to take with the response from the LLM. See [Actions](#actions). Defaults to "display".                                 |
| extract     | `string` (Optional)            | A Lua match pattern to extract from the response. Used only by certain actions. See [Extracting](#extracting).                     |

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

- `display`: Display the response in a floating window.
- `replace`: Replace the current selection with the response.
  - Uses the `extract` pattern to extract the response.

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

## Credits

- [ollama](https://github.com/jmorganca/ollama) for running LLMs locally
- [gen.nvim](https://github.com/David-Kunz/gen.nvim) for inspiration
