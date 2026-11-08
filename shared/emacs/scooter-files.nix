# shared/emacs/scooter-files.nix
# A Scooter conversation's sandbox files over TRAMP: /scooter:<conversation-id>:/workspace/.
# The method is TRAMP's ssh one, logging in through scooter-ssh, whose ProxyCommand
# (`scooter-acp --tunnel`) pipes ssh over the sandbox's `ssh` web service WebSocket.
{ }:

''
  (defvar my/scooter-ssh-command
    (expand-file-name "scooter-ssh" (file-name-directory my/scooter-acp-command)))
  (defvar my/scooter-sandbox-user "root"
    "Who to log in as; a sandbox's sshd lets only root in.")
  (defvar my/scooter-sandbox-directory "/workspace/")

  (defun my/scooter--tramp-method ()
    "TRAMP's ssh method, with scooter-ssh as the login program."
    (let* ((ssh (cdr (assoc "ssh" tramp-methods)))
           (env (append (my/scooter--environment)
                        (list (concat "SCOOTER_SSH_USER=" my/scooter-sandbox-user)))))
      (append
       `((tramp-login-program "env")
         (tramp-login-args
          ,(append (mapcar (lambda (arg) (list (string-replace "%" "%%" arg)))
                           (append env (list my/scooter-ssh-command)))
                   (car (alist-get 'tramp-login-args ssh)))))
       (seq-remove (lambda (param) (memq (car param) '(tramp-login-program tramp-login-args)))
                   ssh))))

  (defun my/scooter--register-tramp ()
    (setf (alist-get "scooter" tramp-methods nil nil #'equal) (my/scooter--tramp-method))
    (connection-local-set-profile-variables
     'my/scooter-sandbox
     '((tramp-remote-path . (tramp-own-remote-path "/run/current-system/sw/bin" tramp-default-remote-path))))
    (connection-local-set-profiles '(:application tramp :protocol "scooter") 'my/scooter-sandbox))

  (with-eval-after-load 'tramp
    (my/guard "scooter-tramp"
      (my/scooter--register-tramp)))

  (defun my/scooter-sandbox-file (id &optional file)
    "The TRAMP name of FILE, relative to /workspace/, in conversation ID's sandbox."
    (concat "/scooter:" id ":"
            (if file (expand-file-name file my/scooter-sandbox-directory) my/scooter-sandbox-directory)))

  (defun my/scooter--conversation-id ()
    "This buffer's Scooter conversation, from its session or sandbox file."
    (or (and (derived-mode-p 'agent-shell-mode)
             (eq (map-nested-elt (agent-shell--state) '(:agent-config :identifier)) 'scooter)
             (map-nested-elt (agent-shell--state) '(:session :id)))
        (and (equal (file-remote-p default-directory 'method) "scooter")
             (file-remote-p default-directory 'host))
        (user-error "Not a Scooter agent-shell buffer or sandbox file")))

  (defun my/scooter--sandbox-root ()
    "This conversation's sandbox /workspace/, signing in first if needed."
    (let ((id (my/scooter--conversation-id)))
      (require 'tramp)
      (my/scooter--register-tramp)
      (when (my/scooter--cookie-refused-p)
        (my/scooter-login))
      (my/scooter-sandbox-file id)))

  (defun my/scooter-find-file ()
    "Visit a file in this Scooter conversation's sandbox."
    (interactive)
    (let ((default-directory (my/scooter--sandbox-root)))
      (call-interactively #'find-file)))

  (defun my/scooter-dired ()
    "Open dired on this Scooter conversation's sandbox /workspace/."
    (interactive)
    (dired (my/scooter--sandbox-root)))

  (defun my/scooter--path-regexp ()
    (rx (literal (directory-file-name my/scooter-sandbox-directory))
        (? "/" (* (any alnum "._~/@+-")))
        (? ":" (group (+ digit)) (? ":" (group (+ digit))))))

  (defun my/scooter-open-path (path &optional line column)
    "Visit PATH, a sandbox path, at LINE and COLUMN in this conversation's sandbox."
    (let ((file (my/scooter-sandbox-file (my/scooter--conversation-id) path)))
      (if (fboundp 'agent-shell-markdown-visit-file)
          (agent-shell-markdown-visit-file :file file :line-start line :column column)
        (find-file file)
        (when line (goto-char (point-min)) (forward-line (1- line)))
        (when column (move-to-column (1- column))))))

  (defun my/scooter-open-path-at-point (&optional event)
    "Visit the sandbox path linked at point, or where EVENT clicked."
    (interactive (list last-nonmenu-event))
    (let* ((pos (if (mouse-event-p event) (posn-point (event-end event)) (point)))
           (target (seq-some (lambda (ov) (overlay-get ov 'my/scooter-path)) (overlays-at pos))))
      (unless target (user-error "No sandbox path here"))
      (apply #'my/scooter-open-path target)))

  (defvar my/scooter-path-map
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "RET") #'my/scooter-open-path-at-point)
      (define-key map [mouse-1] #'my/scooter-open-path-at-point)
      (define-key map [mouse-2] #'my/scooter-open-path-at-point)
      map))

  (defun my/scooter--path-char-p (char)
    (and char (string-match-p "[[:alnum:]._~/@+-]" (string char))))

  (defun my/scooter--link-paths (beg end)
    "Link the /workspace paths around BEG..END to the sandbox files."
    (save-excursion
      (save-match-data
        (let ((beg (max (progn (goto-char beg) (line-beginning-position)) (- beg 512)))
              (end (min (progn (goto-char end) (line-end-position)) (+ end 512))))
          (dolist (ov (overlays-in beg end))
            (when (overlay-get ov 'my/scooter-path)
              (setq beg (min beg (overlay-start ov))
                    end (max end (overlay-end ov)))
              (delete-overlay ov)))
          (goto-char beg)
          (while (re-search-forward (my/scooter--path-regexp) end t)
            (let* ((start (match-beginning 0))
                   (line (and (match-beginning 1) (string-to-number (match-string 1))))
                   (column (and (match-beginning 2) (string-to-number (match-string 2))))
                   (path (string-trim-right
                          (buffer-substring-no-properties start (if line (1- (match-beginning 1)) (match-end 0)))
                          "[.]+")))
              (unless (or (my/scooter--path-char-p (char-before start))
                          (let ((root (length (directory-file-name my/scooter-sandbox-directory))))
                            (and (= (length path) root)
                                 (my/scooter--path-char-p (char-after (+ start root))))))
                (let ((ov (make-overlay start (if line (match-end 0) (+ start (length path))) nil t nil)))
                  (overlay-put ov 'my/scooter-path (list path line column))
                  (overlay-put ov 'face 'link)
                  (overlay-put ov 'mouse-face 'highlight)
                  (overlay-put ov 'help-echo "RET, mouse-1: open in the Scooter sandbox")
                  (overlay-put ov 'keymap my/scooter-path-map)
                  (overlay-put ov 'evaporate t)))))))))

  (defun my/scooter--link-changed (beg end _old-length)
    (my/scooter--link-paths beg end))

  (defvar my/scooter-files-mode-map
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "C-c C-f") #'my/scooter-find-file)
      (define-key map (kbd "C-c C-d") #'my/scooter-dired)
      map))

  (define-minor-mode my/scooter-files-mode
    "Open this Scooter conversation's sandbox files: \\{my/scooter-files-mode-map}
  /workspace paths in the shell link to the sandbox file."
    :keymap my/scooter-files-mode-map
    (if my/scooter-files-mode
        (progn
          (add-hook 'after-change-functions #'my/scooter--link-changed nil t)
          (my/scooter--link-paths (point-min) (point-max)))
      (remove-hook 'after-change-functions #'my/scooter--link-changed t)
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (overlay-get ov 'my/scooter-path)
          (delete-overlay ov)))))
''
