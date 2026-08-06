# shared/emacs/pair.nix
# Pair programmers: spin a second provider off the main agent to review
# work in progress and report back.
#
# The pair only ever produces suggestions -- it never edits. That direction is
# deliberate: arXiv 2607.21656 measured cross-model review as asymmetric, with a
# weaker reviewer rewriting a stronger model's code costing 8.6pp pass rate.
# Findings queue up tagged with branch and commit, and the main agent decides.
#
# agent-shell emits `agent-message-chunk' without accumulating the text, so the
# harvester collects chunks itself and finalises them on `turn-complete'.
{ ... }:
''
  (my/guard "pair"
    ;; API key rather than the default interactive login: sops already puts the
    ;; key in the environment, and a pair must start without a browser detour.
    ;; Deferred so a load failure here cannot take the commands below with it.
    (with-eval-after-load 'agent-shell-google
      (setq agent-shell-google-authentication
            (agent-shell-google-make-authentication
             :api-key (lambda () (getenv "GEMINI_API_KEY")))))

    (defvar my/pair-config-maker #'agent-shell-google-make-gemini-config
      "Function returning the agent config used for pair programmers.")

    (defvar my/pair-findings nil
      "Harvested findings, newest first.
  Each entry is a plist with :text :branch :sha :dir :agent :time.")

    (defvar my/pair--buffers nil
      "Alist of (directory . pair shell buffer).")

    (defvar-local my/pair--accumulator nil
      "Reversed list of streamed text chunks for this pair shell.")

    (defvar-local my/pair--context nil
      "Plist describing what this pair shell was dispatched against.")

    (defun my/pair--git (&rest args)
      "Run git with ARGS in `default-directory', returning trimmed output or nil."
      (with-temp-buffer
        (when (zerop (apply #'process-file "git" nil t nil args))
          (let ((out (string-trim (buffer-string))))
            (unless (string-empty-p out) out)))))

    (defun my/pair--make-context ()
      "Describe the current repository state."
      (list :branch (or (my/pair--git "branch" "--show-current") "(detached)")
            :sha (or (my/pair--git "rev-parse" "--short" "HEAD") "(no commit)")
            :dir default-directory))

    (defun my/pair--diff ()
      "Return staged and unstaged changes, or nil when the tree is clean."
      (let ((diff (string-trim (concat (or (my/pair--git "diff" "--cached") "")
                                      "\n"
                                      (or (my/pair--git "diff") "")))))
        (unless (string-empty-p diff) diff)))

    (defun my/pair--prompt (context diff)
      "Build the review prompt for CONTEXT and DIFF."
      (format (concat "You are pair programming. Review this work in progress on "
                      "branch `%s` at commit %s.\n\n"
                      "Do NOT edit files. Report only:\n"
                      "1. Edge cases the change does not handle.\n"
                      "2. Concrete test cases -- name plus what each asserts.\n"
                      "3. Anything outright wrong, cited as file:line.\n\n"
                      "Be terse and specific. If the change is trivial, say so and stop.\n\n"
                      "```diff\n%s\n```")
              (plist-get context :branch) (plist-get context :sha) diff))

    (defun my/pair--harvest (buffer)
      "Finalise accumulated text in BUFFER into `my/pair-findings'."
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let ((text (string-trim (apply #'concat (reverse my/pair--accumulator)))))
            (setq my/pair--accumulator nil)
            (unless (string-empty-p text)
              (push (append (list :text text
                                  :agent (buffer-name buffer)
                                  :time (format-time-string "%H:%M:%S"))
                            my/pair--context)
                    my/pair-findings)
              (message "[pair] finding on %s@%s -- M-x my/pair-show"
                       (plist-get my/pair--context :branch)
                       (plist-get my/pair--context :sha)))))))

    (defun my/pair--attach (buffer)
      "Subscribe the harvester to BUFFER.
  Only harvest events are wired here -- a pair shell never triggers a dispatch,
  which is what keeps its own writes from feeding back into another review."
      (agent-shell-subscribe-to
       :shell-buffer buffer :event 'agent-message-chunk
       :on-event (lambda (event)
                   (when-let* ((chunk (map-elt (map-elt event :data) :text-chunk)))
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (push chunk my/pair--accumulator))))))
      (agent-shell-subscribe-to
       :shell-buffer buffer :event 'turn-complete
       :on-event (lambda (_event) (my/pair--harvest buffer))))

    (defun my/pair--spawn ()
      "Start a pair shell in `default-directory' and return its buffer."
      (let* ((before (agent-shell-buffers))
             (_ (save-window-excursion
                  (agent-shell-start :config (funcall my/pair-config-maker))))
             (new (car (seq-difference (agent-shell-buffers) before))))
        (unless new
          (user-error "Could not identify the newly started pair shell"))
        (my/pair--attach new)
        new))

    (defun my/pair--send (buffer text fresh)
      "Submit TEXT to BUFFER, waiting for `prompt-ready' when FRESH."
      (if (not fresh)
          (agent-shell-insert :text text :submit t :no-focus t :shell-buffer buffer)
        (let ((token nil))
          (setq token
                (agent-shell-subscribe-to
                 :shell-buffer buffer :event 'prompt-ready
                 :on-event (lambda (_event)
                             (when (buffer-live-p buffer)
                               (with-current-buffer buffer
                                 (agent-shell-unsubscribe :subscription token))
                               (agent-shell-insert :text text :submit t
                                                   :no-focus t
                                                   :shell-buffer buffer))))))))

    (defun my/pair-dispatch ()
      "Send the current diff to a pair programmer for review."
      (interactive)
      (let ((default-directory (or (my/pair--git "rev-parse" "--show-toplevel")
                                   default-directory)))
        (unless (my/pair--git "rev-parse" "--git-dir")
          (user-error "Not in a git repository"))
        (let* ((diff (or (my/pair--diff)
                         (user-error "No staged or unstaged changes to review")))
               (context (my/pair--make-context))
               (existing (alist-get default-directory my/pair--buffers nil nil #'equal))
               (fresh (not (buffer-live-p existing)))
               (buffer (if fresh (my/pair--spawn) existing)))
          (setf (alist-get default-directory my/pair--buffers nil nil #'equal) buffer)
          (with-current-buffer buffer
            (setq my/pair--context context
                  my/pair--accumulator nil))
          (my/pair--send buffer (my/pair--prompt context diff) fresh)
          (message "[pair] reviewing %s@%s in %s"
                   (plist-get context :branch) (plist-get context :sha)
                   (buffer-name buffer)))))

    (defun my/pair-show ()
      "Show harvested pair findings, newest first."
      (interactive)
      (unless my/pair-findings
        (user-error "No pair findings yet"))
      (let ((buffer (get-buffer-create "*pair findings*")))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (dolist (finding my/pair-findings)
              (insert (format "* %s@%s  %s  %s\n\n%s\n\n"
                              (plist-get finding :branch)
                              (plist-get finding :sha)
                              (plist-get finding :time)
                              (plist-get finding :agent)
                              (plist-get finding :text))))
            (goto-char (point-min))
            (when (fboundp 'markdown-mode) (markdown-mode))
            (view-mode 1)))
        (pop-to-buffer buffer)))

    (defun my/pair-hand-off (shell)
      "Insert the newest pair finding into SHELL for the main agent to weigh."
      (interactive
       (list (get-buffer
              (completing-read "Hand off to shell: "
                               (mapcar #'buffer-name (agent-shell-buffers))
                               nil t))))
      (let ((finding (car my/pair-findings)))
        (unless finding (user-error "No pair findings yet"))
        (agent-shell-insert
         :shell-buffer shell :no-focus t
         :text (format (concat "A pair programmer reviewed %s@%s and suggested the "
                               "following. Judge it -- adopt only what holds up.\n\n%s")
                       (plist-get finding :branch)
                       (plist-get finding :sha)
                       (plist-get finding :text)))))

    (defun my/pair-clear ()
      "Drop all harvested findings."
      (interactive)
      (setq my/pair-findings nil)
      (message "[pair] findings cleared"))

    (global-set-key (kbd "C-c P d") #'my/pair-dispatch)
    (global-set-key (kbd "C-c P s") #'my/pair-show)
    (global-set-key (kbd "C-c P h") #'my/pair-hand-off))
''
