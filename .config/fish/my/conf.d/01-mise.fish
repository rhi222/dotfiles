# mise (runtime manager) settings
if type -q mise
    ~/.local/bin/mise activate fish | source

    # default packages
    set -gx MISE_PYTHON_DEFAULT_PACKAGES_FILE $HOME/.config/mise/.default-python-packages
    set -gx MISE_NODE_DEFAULT_PACKAGES_FILE $HOME/.config/mise/.default-npm-packages
    set -gx MISE_GO_DEFAULT_PACKAGES_FILE $HOME/.config/mise/.default-go-packages
end