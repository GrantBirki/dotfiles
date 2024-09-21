# frozen_string_literal: true

require "irb"
require "irb/completion"

IRB.conf[:AUTO_INDENT] = true

# Load the readline module.
IRB.conf[:USE_READLINE] = true

IRB.conf[:SAVE_HISTORY] = 200
IRB.conf[:HISTORY_FILE] = "#{ENV['HOME']}/.irb_history"

# Remove the annoying irb(main):001:0 and replace with >>
IRB.conf[:PROMPT_MODE]  = :SIMPLE

# Clear the screen
def clear
  system 'clear'
end

# Shortcuts
alias c clear

# history command
def history(count = 0)
  # Get history into an array
  history_array = Readline::HISTORY.to_a

  # if count is > 0 we'll use it.
  # otherwise set it to 0
  count = count.positive? ? count : 0

  if count.positive?
    from = history_array.length - count
    history_array = history_array[from..]
  end

  print history_array.join("\n")
end

alias h history
