;;; drive.el --- screenshots of Scooter in agent-shell -*- lexical-binding: t -*-
;; Run by screenshots.sh in a GUI Emacs under Xvfb. Writes PNGs to $SHOTS_DIR.

(require 'agent-shell)
(require 'markdown-mode nil t)
(setq auth-sources (list (expand-file-name "authinfo" (getenv "HOME")))
      auth-source-save-behavior t)
(load (getenv "SCOOTER_EL"))
;; The demo server accepts this cookie; scooter-mode would otherwise ask for one.
(scooter-auth-set-cookie my/scooter-server "good")

(setq inhibit-startup-screen t
      ring-bell-function #'ignore
      agent-shell-session-strategy 'prompt
      completions-format 'one-column
      completion-show-help nil
      completions-header-format nil)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(load-theme 'modus-vivendi t)
(set-face-attribute 'default nil :family "DejaVu Sans Mono" :height 120)
(set-frame-size nil 118 36)

(defvar shot-dir (getenv "SHOTS_DIR"))
(defvar shot-buffer nil)

(defun shot (name)
  (message nil)
  (redisplay t)
  (with-temp-file (expand-file-name (concat name ".png") shot-dir)
    (set-buffer-multibyte nil)
    (insert (x-export-frames nil 'png))))

(defun shot-text (buf) (with-current-buffer buf (buffer-substring-no-properties (point-min) (point-max))))
(defun shot-has (buf s) (string-match-p (regexp-quote s) (shot-text buf)))

(defun shot-when (pred then &optional deadline)
  "Call THEN once PRED holds, polling from timers so the UI stays live."
  (let ((deadline (or deadline (+ (float-time) 30))))
    (cond ((funcall pred) (run-at-time 0.8 nil then))
          ((> (float-time) deadline) (shot-fail "timed out"))
          (t (run-at-time 0.2 nil #'shot-when pred then deadline)))))

(defun shot-fail (why)
  (princ (format "screenshots: FAIL %s\n" why) #'external-debugging-output)
  (when (getenv "SHOTS_DEBUG")
    (dolist (b (list "*Warnings*" "*Messages*" shot-buffer))
      (when (and b (get-buffer b))
        (princ (format "--- %s\n%s\n" b (shot-text b)) #'external-debugging-output))))
  (kill-emacs 1))

(defun shot-top (buf from)
  "Show BUF alone, scrolled to the line with FROM."
  (delete-other-windows)
  (switch-to-buffer buf)
  (goto-char (point-min))
  (search-forward from)
  (set-window-start nil (line-beginning-position)))

(defun shot-bottom (buf)
  (delete-other-windows)
  (switch-to-buffer buf)
  (goto-char (point-max))
  (recenter -1))

;; 1. C-c j: the picker lists the web UI's conversations.
(defun shot-1-picker ()
  (when (getenv "SHOTS_DEBUG")
    (princ (format "--- warnings\n%s\n" (and (get-buffer "*Warnings*") (shot-text "*Warnings*"))) #'external-debugging-output))
  (switch-to-buffer (get-buffer-create "*scratch*"))
  (erase-buffer)
  (delete-other-windows)
  (set-frame-size nil 100 17)
  (shot-when
   (lambda () (and (minibufferp (window-buffer (minibuffer-window)))
                   (> (minibuffer-depth) 0)))
   (lambda ()
     (with-selected-window (minibuffer-window)
       (minibuffer-completion-help)
       (shot-when
        (lambda () (get-buffer-window "*Completions*"))
        (lambda ()
          (with-selected-window (minibuffer-window)
            (shot "01-picker")
            (set-frame-size nil 118 36)
            (let ((pick (seq-find (lambda (c) (string-match-p "Fix the login redirect" c))
                                  (all-completions "" minibuffer-completion-table))))
              (delete-minibuffer-contents)
              (insert pick)
              (exit-minibuffer))))))))
  (call-interactively #'my/scooter))

;; 2. The conversation's history, replayed.
(defun shot-2-history ()
  (shot-when
   (lambda () (setq shot-buffer (seq-find (lambda (b) (shot-has b "Opened"))
                                          (match-buffers '(derived-mode . agent-shell-mode)))))
   (lambda ()
     (shot-top shot-buffer "Resuming session")
     (shot "02-history")
     (shot-3-web-run))))

;; 3. A run started from the browser streams into the open buffer.
(defun shot-3-web-run ()
  (with-temp-file (getenv "TRIGGER_FILE") (insert "web"))
  (shot-when
   (lambda () (and (shot-has shot-buffer "returns you to the page")
                   (with-current-buffer shot-buffer (not (shell-maker-busy)))))
   (lambda ()
     (shot-bottom shot-buffer)
     (shot "03-web-run")
     (shot-4-approval))))

;; 4. An approval card, answered from Emacs.
(defun shot-4-approval ()
  (agent-shell-insert :text "grant" :submit t :no-focus t :shell-buffer shot-buffer)
  (shot-when
   (lambda () (shot-has shot-buffer "s3:PutObject"))
   (lambda ()
     (shot-bottom shot-buffer)
     (shot "04-approval")
     (princ "screenshots: ok\n" #'external-debugging-output)
     (kill-emacs 0))))

(add-hook 'emacs-startup-hook
          (lambda ()
            (run-at-time 1 nil (lambda () (shot-2-history) (shot-1-picker)))))
