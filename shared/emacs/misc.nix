# shared/emacs/misc.nix
# auto-revert, compile, windmove, shell/PATH, eat terminal, magit,
# clipboard (xclip) elisp.
{ pkgs, bashPath, ... }:
''
  ;; Auto-revert: pick up external edits (AI tools, git, etc.) quickly
  (setq auto-revert-interval 1                ; check every 1s instead of 5s
        auto-revert-avoid-polling t            ; use inotify/kqueue instead of polling
        auto-revert-check-vc-info nil          ; don't re-check VC on every revert (faster)
        auto-revert-verbose nil                ; don't spam *Messages* on every revert
        revert-without-query '(".*"))          ; never prompt "file changed, revert?" — just do it
  (global-auto-revert-mode 1)

  (require 'ansi-color)
  (add-hook 'compilation-filter-hook 'ansi-color-compilation-filter)

  ;; Compile — per-directory history stored in ~/.emacs.d/compile-history/
  (defvar my/compile-history-dir "~/.emacs.d/compile-history/")
  (defun my/compile-history-file ()
    (let ((dir (replace-regexp-in-string "/" "!" (abbreviate-file-name default-directory))))
      (expand-file-name dir my/compile-history-dir)))
  (defun my/compile-history-load ()
    (let ((file (my/compile-history-file)))
      (when (file-exists-p file)
        (with-temp-buffer (insert-file-contents file)
          (read (current-buffer))))))
  (defun my/compile-history-save (history)
    (make-directory my/compile-history-dir t)
    (with-temp-file (my/compile-history-file)
      (prin1 history (current-buffer))))
  (defun my/compile ()
    "Compile with per-directory command history."
    (interactive)
    (let* ((history (my/compile-history-load))
           (default (or (car history) compile-command))
           (cmd (read-string (format "Compile [%s]: " default) nil 'history default)))
      (my/compile-history-save (delete-dups (cons cmd history)))
      (compile cmd)))
  (global-set-key (kbd "C-c C-k") 'my/compile)

  (global-set-key (kbd "M-<up>") 'backward-paragraph)
  (global-set-key (kbd "M-<down>") 'forward-paragraph)

  (windmove-default-keybindings)
  (global-set-key (kbd "M-o") 'ace-window)
  (global-set-key (kbd "C-c w") 'windresize)

  ;; Use Home Manager bash for all shell operations
  (setq shell-file-name "${bashPath}"
        explicit-shell-file-name "${bashPath}")
  (add-to-list 'exec-path "${pkgs.bash}/bin")
  (setenv "SHELL" "${bashPath}")

  ;; Ensure /run/wrappers/bin (setuid wrappers: sudo, ping, etc.) is first in PATH
  (when (eq system-type 'gnu/linux)
    (add-to-list 'exec-path "/run/wrappers/bin")
    (setenv "PATH" (concat "/run/wrappers/bin:" (getenv "PATH"))))

  ;; On macOS GUI, inherit PATH from login shell (GUI apps don't get shell PATH)
  (when (and (eq system-type 'darwin) (display-graphic-p))
    (require 'exec-path-from-shell)
    (setq exec-path-from-shell-shell-name "${bashPath}")
    (exec-path-from-shell-initialize))

  ;; Eat terminal (pure elisp, fast, less flicker than vterm)
  ;; C-c t spawns a new eat terminal, C-c r lists existing eat sessions
  (require 'eat)
  (setq eat-shell "${bashPath}")

  (advice-add 'eat-emacs-mode :after (lambda (&rest _) (setq-local cursor-type 'box)))
  (global-set-key (kbd "C-c t") #'(lambda () (interactive) (let ((current-prefix-arg '(4))) (call-interactively 'eat))))
  (global-set-key (kbd "C-c r") #'(lambda () (interactive)
    (let ((eat-buffers (cl-remove-if-not
                        (lambda (buf) (with-current-buffer buf (derived-mode-p 'eat-mode)))
                        (buffer-list))))
      (if eat-buffers
          (switch-to-buffer (completing-read "Select eat session: "
                                             (mapcar #'buffer-name eat-buffers) nil t))
        (message "No eat sessions open")))))
  ;; Send modifier+arrow keys to the terminal in eat semi-char mode.
  ;; By default these fall through to global-map (left-word etc.),
  ;; but eat resets cursor to match terminal state, causing visual glitch.
  (dolist (key '("M-<left>" "M-<right>" "M-<up>" "M-<down>"
                 "C-<left>" "C-<right>" "C-<up>" "C-<down>"))
    (define-key eat-semi-char-mode-map (kbd key) #'eat-self-input))
  ;; Bracketed paste for eat — wrap yanked text so shell treats it as one input
  (defun my/eat-yank-with-bracketed-paste ()
    "Yank into eat using bracketed paste so multiline text isn't executed line-by-line."
    (interactive)
    (let ((text (or (current-kill 0 t) "")))
      (eat-term-send-string eat-terminal "\e[200~")
      (eat-term-send-string eat-terminal text)
      (eat-term-send-string eat-terminal "\e[201~")))
  (with-eval-after-load 'eat
    (define-key eat-semi-char-mode-map (kbd "C-c C-y") #'my/eat-yank-with-bracketed-paste))

  (add-hook 'eshell-load-hook #'eat-eshell-mode)
  (add-hook 'eshell-load-hook #'eat-eshell-visual-command-mode)

  (require 'magit)
  (global-set-key (kbd "C-c g") 'magit-status)
  ;; Open magit in the current window instead of splitting; diffs still get
  ;; their own window so they can be viewed alongside the status buffer.
  (setq magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1)

  (setq xclip-method (if (eq system-type 'darwin) 'pbpaste 'wl-copy))
  (xclip-mode 1)
  (setq select-enable-clipboard t)
  (unless (eq system-type 'darwin)
    (setq select-enable-primary t))
''
