
# Load my custom configurations in order
for file in ~/.config/fish/my/conf.d/*.fish
    if test -r $file
        source $file
    end
end

# Add my functions directory to fish_function_path
set -g fish_function_path ~/.config/fish/my/functions $fish_function_path
