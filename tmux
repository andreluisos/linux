# Start windows and panes at 1, not 0
set -g base-index 1
set -g pane-base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on
set -g mouse on
set -g status-right-length 100
set -g status-right "#(~/.config/tmux/status.sh) | %a %Y-%m-%d %H:%M"

# Initialize TMUX plugin manager (keep this line at the very bottom)
# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'christoomey/vim-tmux-navigator'

# Enable automatic restore
set -g @continuum-restore 'on'

# Optional: Set autosave interval (default is 15 minutes)
set -g @continuum-save-interval '15'

run "$HOME/.tmux/plugins/tpm/tpm"
